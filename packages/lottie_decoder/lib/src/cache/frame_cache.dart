import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lottie_decoder/src/cache/frame_cache_codec.dart';
import 'package:lottie_decoder/src/cache/frame_cache_files.dart';
import 'package:lottie_decoder/src/cache/frame_cache_key.dart';

/// Tells the time; injected so tests order recency without waiting.
typedef FrameCacheClock = DateTime Function();

/// Receives a file-system failure the cache degraded around.
typedef FrameCacheErrorHandler = void Function(Object error, StackTrace stack);

DateTime _systemClock() => DateTime.now();

void _reportToFlutter(Object error, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'lottie_decoder',
      context: ErrorDescription('while using the frame cache'),
    ),
  );
}

/// Compressed frames of rendered animations, kept in memory and, when the host
/// gives it a directory, on disk.
///
/// The cache holds **opaque** bytes: it knows nothing of the codec, the engine
/// or pixels, so the same store serves any renderer that can encode a frame
/// into bytes and decode it back.
///
/// ## Use
///
/// A renderer calls [open] once per animation, then reads [frame] and tests
/// [has] synchronously, and [put]s a frame after rendering one. A frame is
/// served from RAM only; [open] is what makes a file's frames resident.
///
/// ## Tiers
///
/// The RAM tier evicts whole animations, least recently used first: a
/// half-resident animation would serve some frames and re-render others, which
/// costs the same render as having none. The disk tier writes an animation
/// once, when its last frame arrives, and evicts files least recently used.
final class FrameCache {
  /// Creates a cache keeping files in [directory]; null keeps memory only.
  FrameCache({
    required Directory? directory,
    this.ramBudgetBytes = 32 * 1024 * 1024,
    this.diskBudgetBytes = 128 * 1024 * 1024,
    FrameCacheClock clock = _systemClock,
    FrameCacheErrorHandler onError = _reportToFlutter,
    @visibleForTesting FrameCacheFiles? files,
  }) : assert(
         files == null || directory != null,
         'files need the directory they live in',
       ),
       _files =
           files ?? (directory == null ? null : FrameCacheFiles(directory)),
       _clock = clock,
       _onError = onError;

  /// The most compressed bytes the RAM tier keeps (a single animation larger
  /// than this stays while it is the only one).
  final int ramBudgetBytes;

  /// The most bytes the disk tier keeps.
  final int diskBudgetBytes;

  final FrameCacheFiles? _files;
  final FrameCacheClock _clock;
  final FrameCacheErrorHandler _onError;

  final Map<FrameCacheKey, _Animation> _animations = {};
  int _ramBytes = 0;
  bool _disposed = false;

  // The disk tier, as this cache last saw it. Filled by one scan, lazily: a
  // cache that only ever misses in memory never lists the directory.
  final Map<String, _DiskFile> _disk = {};
  Future<void>? _scanned;
  final Set<Future<void>> _pending = {};
  final Map<FrameCacheKey, Future<int?>> _reads = {};
  // Writes stop after the first failure: a directory that refused one write
  // (read-only, full, gone) will refuse the next, and each attempt would only
  // allocate and fail. Reads keep trying; a miss is all they cost.
  bool _writable = true;
  bool _reported = false;

  /// Makes the animation's frames resident and returns its frame count, or
  /// null when nothing is cached for [key] (or [key] is not admitted).
  Future<int?> open(FrameCacheKey key) async {
    _checkAlive();
    if (!key.admitted()) return null;
    final animation = _animations[key];
    if (animation != null) {
      _touch(animation);
      return animation.frames.length;
    }
    if (_files == null) return null;
    // Concurrent opens of one key share one read: the second would only read
    // and decode the same file again, then lose the race to install it.
    // The callback is a block: `whenComplete` waits for a Future it returns,
    // and `remove` returns this very future.
    return _reads[key] ??= _load(key).whenComplete(() {
      _reads.remove(key);
    });
  }

  /// Whether frame [index] of [key] is resident.
  bool has(FrameCacheKey key, int index) {
    final frames = _animations[key]?.frames;
    return frames != null &&
        index >= 0 &&
        index < frames.length &&
        frames[index] != null;
  }

  /// The resident bytes of frame [index] of [key], or null; marks the
  /// animation recently used.
  Uint8List? frame(FrameCacheKey key, int index) {
    final animation = _animations[key];
    if (animation == null || index < 0 || index >= animation.frames.length) {
      return null;
    }
    _touch(animation);
    return animation.frames[index];
  }

  /// Stores one compressed frame of an animation of [frameCount] frames.
  ///
  /// A frame already stored is kept (the first write wins). Throws
  /// [ArgumentError] when [key] is not admitted or [frameCount] is not
  /// positive, [RangeError] when [index] is outside the animation, and
  /// [StateError] when [frameCount] disagrees with an earlier put or the cache
  /// is disposed.
  void put(
    FrameCacheKey key,
    int index,
    Uint8List compressed, {
    required int frameCount,
  }) {
    _checkAlive();
    if (!key.admitted()) {
      throw ArgumentError.value(key, 'key', 'is above the cacheable size');
    }
    if (frameCount < 1) {
      throw ArgumentError.value(frameCount, 'frameCount', 'must be positive');
    }
    RangeError.checkValidIndex(index, List<void>.filled(frameCount, null));
    final animation = _animations.putIfAbsent(
      key,
      () => _Animation(key.toFileStem(), frameCount),
    );
    if (animation.frames.length != frameCount) {
      throw StateError(
        '$key has ${animation.frames.length} frames, not $frameCount',
      );
    }
    _touch(animation);
    if (animation.frames[index] != null) return;
    animation.frames[index] = compressed;
    animation.filled++;
    animation.bytes += compressed.length;
    _ramBytes += compressed.length;
    if (_files != null && animation.complete && !animation.persisted) {
      animation.persisted = true;
      // The frames are copied out now: the animation may be evicted from RAM
      // before the write runs.
      _track(_persist(key, List<Uint8List>.of(animation.frames.cast())));
    }
    _evictRam(keep: key);
  }

  /// Drops one animation from both tiers: the resident frames at once, the
  /// file once a write under way has finished. For an entry a renderer found
  /// damaged (its bytes decoded to nothing), which would otherwise be served
  /// again on every launch. Unknown keys are fine.
  ///
  /// The RAM entry goes before the first `await`, so a caller that renders on
  /// and [put]s again need not wait: the new frames build a fresh animation.
  /// A file-system failure is reported like any other, never thrown.
  Future<void> invalidate(FrameCacheKey key) async {
    _checkAlive();
    final dropped = _animations.remove(key);
    if (dropped != null) _ramBytes -= dropped.bytes;
    final files = _files;
    if (files == null) return;
    await _settle();
    try {
      _disk.remove(key.toFileStem());
      await files.delete(key.toFileStem());
    } on Object catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Drops both tiers.
  Future<void> clear() async {
    _animations.clear();
    _ramBytes = 0;
    // A write already under way finishes first, so that its file is among
    // those removed rather than appearing after the clear.
    await _settle();
    final files = _files;
    if (files == null) return;
    try {
      await _ensureScanned();
      for (final stem in _disk.keys.toList()) {
        await files.delete(stem);
      }
      _disk.clear();
    } on Object catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Whether [dispose] was called: [open], [put] and [invalidate] then throw.
  bool get isDisposed => _disposed;

  /// Finishes pending reads and writes, then stops; idempotent.
  Future<void> dispose() async {
    _disposed = true;
    await _settle();
  }

  /// Waits until no read or write is under way.
  Future<void> _settle() async {
    while (_pending.isNotEmpty || _reads.isNotEmpty) {
      await Future.wait<Object?>([..._pending, ..._reads.values]);
    }
  }

  // --- Disk tier ---

  void _track(Future<void> work) {
    _pending.add(work);
    work.whenComplete(() {
      _pending.remove(work);
    });
  }

  Future<void> _ensureScanned() => _scanned ??= _scan();

  Future<void> _scan() async {
    try {
      for (final info in await _files!.scan()) {
        _disk[info.stem] = _DiskFile(info.bytes, info.modified);
      }
    } on Object catch (error, stack) {
      // An unlistable directory is an empty one: its files are simply not
      // found, and the first write will report if it cannot write either.
      _report(error, stack);
    }
    await _evictDisk();
  }

  /// Deletes files, least recently used first, until the rest fits the
  /// budget. A file larger than the whole budget goes too: the budget is the
  /// host's, and a tier that exceeded it would be a leak with extra steps.
  Future<void> _evictDisk() async {
    var total = _disk.values.fold<int>(0, (sum, f) => sum + f.bytes);
    while (total > diskBudgetBytes && _disk.isNotEmpty) {
      MapEntry<String, _DiskFile>? oldest;
      for (final entry in _disk.entries) {
        if (oldest == null ||
            entry.value.lastUsed.isBefore(oldest.value.lastUsed)) {
          oldest = entry;
        }
      }
      _disk.remove(oldest!.key);
      total -= oldest.value.bytes;
      try {
        await _files!.delete(oldest.key);
      } on Object catch (error, stack) {
        _report(error, stack);
      }
    }
  }

  Future<int?> _load(FrameCacheKey key) async {
    final stem = key.toFileStem();
    try {
      await _ensureScanned();
      if (!_disk.containsKey(stem)) return null;
      final bytes = await _files!.read(stem);
      final frames = bytes == null ? null : FrameCacheCodec.decode(key, bytes);
      if (frames == null) {
        // Damage is a miss, and the file goes: left in place it would be
        // read, rejected and re-rendered over on every launch.
        _disk.remove(stem);
        await _files.delete(stem);
        return null;
      }
      final raced = _animations[key];
      if (raced != null) return raced.frames.length;
      final now = _clock();
      final animation = _Animation.complete(stem, frames)
        ..persisted = true
        ..lastUsed = now;
      _animations[key] = animation;
      _ramBytes += animation.bytes;
      _disk[stem]?.lastUsed = now;
      await _files.touch(stem, now);
      _evictRam(keep: key);
      return frames.length;
    } on Object catch (error, stack) {
      _report(error, stack);
      return null;
    }
  }

  Future<void> _persist(FrameCacheKey key, List<Uint8List> frames) async {
    if (!_writable) return;
    final stem = key.toFileStem();
    try {
      await _ensureScanned();
      final bytes = FrameCacheCodec.encode(key, frames);
      final now = _clock();
      await _files!.write(stem, bytes, modified: now);
      _disk[stem] = _DiskFile(bytes.length, now);
      await _evictDisk();
    } on Object catch (error, stack) {
      _writable = false;
      _report(error, stack);
    }
  }

  /// Reports the first file-system failure only: after one, the rest are the
  /// same fault again, and a host does not need a report per frame.
  void _report(Object error, StackTrace stack) {
    if (_reported) return;
    _reported = true;
    _onError(error, stack);
  }

  /// Marks [animation] used now, in both tiers. The file's time on disk is
  /// stamped when it is read or written, not per frame: a stat per painted
  /// frame would cost more than the recency it buys.
  void _touch(_Animation animation) {
    final now = _clock();
    animation.lastUsed = now;
    _disk[animation.stem]?.lastUsed = now;
  }

  void _checkAlive() {
    if (_disposed) throw StateError('FrameCache is disposed');
  }

  void _evictRam({required FrameCacheKey keep}) {
    while (_ramBytes > ramBudgetBytes) {
      FrameCacheKey? oldest;
      DateTime? oldestUsed;
      for (final entry in _animations.entries) {
        if (entry.key == keep) continue;
        final used = entry.value.lastUsed;
        if (oldestUsed == null || used.isBefore(oldestUsed)) {
          oldest = entry.key;
          oldestUsed = used;
        }
      }
      if (oldest == null) return;
      _ramBytes -= _animations.remove(oldest)!.bytes;
    }
  }
}

/// One animation's resident frames; a slot is null until its frame arrives.
final class _Animation {
  _Animation(this.stem, int frameCount)
    : frames = List<Uint8List?>.filled(frameCount, null),
      filled = 0;

  /// An animation read whole from a file.
  _Animation.complete(this.stem, List<Uint8List> read)
    : frames = List<Uint8List?>.of(read),
      filled = read.length,
      bytes = read.fold<int>(0, (sum, f) => sum + f.length);

  /// The file this animation lives in, spelled once: reads are per frame.
  final String stem;
  final List<Uint8List?> frames;
  int filled;
  int bytes = 0;
  late DateTime lastUsed;

  /// Whether a file holds exactly these frames (read from one, or written).
  bool persisted = false;

  bool get complete => filled == frames.length;
}

/// What the cache knows of one file in the directory.
final class _DiskFile {
  _DiskFile(this.bytes, this.lastUsed);

  final int bytes;
  DateTime lastUsed;
}
