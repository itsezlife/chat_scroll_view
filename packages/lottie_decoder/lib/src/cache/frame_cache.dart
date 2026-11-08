import 'package:flutter/foundation.dart';
import 'package:lottie_decoder/src/cache/cached_frame.dart';
import 'package:lottie_decoder/src/cache/frame_cache_codec.dart';
import 'package:lottie_decoder/src/cache/frame_cache_files.dart';
import 'package:lottie_decoder/src/cache/frame_cache_key.dart';
import 'package:lottie_decoder/src/environment_specific/frame_cache_files.dart'
    as environment_specific;

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

/// Compressed frames of rendered animations, kept in memory while an
/// animation is being filled and, when the host gives it a directory, in one
/// file per animation once it is complete.
///
/// The cache holds **opaque** bytes: it knows nothing of the codec, the engine
/// or pixels, so the same store serves any renderer that can encode a frame
/// into bytes and decode it back.
///
/// ## Use
///
/// A renderer calls [open] once per animation (it learns what the directory
/// holds), then asks [frame] synchronously and [put]s a frame after rendering
/// one. [frame] answers where the frame can be restored from: its bytes while
/// the animation is in memory, or a reference into its file once it is on
/// disk, which the isolate that restores it reads one frame at a time
/// (`FrameFileReader`). The cache never reads a file's frames itself, so a
/// persisted animation costs this isolate no bytes and no work per frame.
///
/// ## Tiers
///
/// The RAM tier holds the animations being filled, and with no directory the
/// complete ones too. It evicts whole animations: a half-resident animation
/// would serve some frames and re-render others, which costs the same render
/// as having none. Over [ramBudgetBytes] it first evicts the animations not
/// used for [playingFor], least recently used first; if every one left plays,
/// it drops the one that started filling last, never the oldest, so one fill
/// always completes (and leaves RAM for its file). A dropped animation that
/// plays renders as without a cache until there is room: the budget degrades
/// by not keeping, never by reloading in a loop.
///
/// The disk tier writes an animation once, when its last frame arrives, and
/// evicts files least recently used past [diskBudgetBytes]; with no budget it
/// evicts none, and the host's store keeps the directory. A file in use is
/// stamped when it is opened and at most every 30 seconds while it serves
/// frames, so such a store sees it as in use.
final class FrameCache {
  /// Creates a cache keeping files in the directory at [directoryPath]; null
  /// keeps memory only, which is all the web can do (a path there is an
  /// [ArgumentError]).
  FrameCache({
    required String? directoryPath,
    this.ramBudgetBytes = 32 * 1024 * 1024,
    this.diskBudgetBytes = 128 * 1024 * 1024,
    this.playingFor = const Duration(seconds: 2),
    FrameCacheClock clock = _systemClock,
    FrameCacheErrorHandler onError = _reportToFlutter,
    @visibleForTesting FrameCacheFiles? files,
  }) : assert(
         files == null || directoryPath != null,
         'files need the directory they live in',
       ),
       _files =
           files ??
           (directoryPath == null
               ? null
               : environment_specific.$openFrameCacheFiles(directoryPath)),
       _clock = clock,
       _onError = onError;

  /// The most compressed bytes the RAM tier keeps (the animation that started
  /// filling first stays even when it alone is larger).
  final int ramBudgetBytes;

  /// The most bytes the disk tier keeps, or null for no budget of its own:
  /// the directory is then a tier of a store the host keeps (one folder for
  /// all its media, say, removing files unused for a while), and a file the
  /// store removed is a miss like any other.
  final int? diskBudgetBytes;

  /// How recently an animation must have been used to count as playing, which
  /// the RAM tier evicts last. The default is the frame scheduler's longest
  /// unpainted lease (twice its idle period of one second): an animation used
  /// within it may still be on screen.
  final Duration playingFor;

  /// How often a file that serves frames is stamped used: well inside the
  /// grace a host's store gives files in use (a minute), so a file that plays
  /// is never the least recently used one there.
  static const Duration _restampEvery = Duration(seconds: 30);

  final FrameCacheFiles? _files;
  final FrameCacheClock _clock;
  final FrameCacheErrorHandler _onError;

  final Map<FrameCacheKey, _Animation> _animations = {};
  int _ramBytes = 0;
  // Orders fills by when they started: the youngest is dropped first.
  int _nextFill = 0;
  bool _disposed = false;

  // The disk tier, as this cache last saw it. Filled by one scan, lazily: a
  // cache that only ever misses in memory never lists the directory.
  final Map<String, _DiskFile> _disk = {};
  Future<void>? _scanned;
  final Set<Future<void>> _pending = {};
  // Writes stop after the first failure: a directory that refused one write
  // (read-only, full, gone) will refuse the next, and each attempt would only
  // allocate and fail. Stamps keep trying; they are cheap.
  bool _writable = true;
  bool _reported = false;

  /// The compressed bytes held in memory now: the animations being filled
  /// (and, without files, the complete ones). A persisted animation adds none.
  int get residentBytes => _ramBytes;

  /// Learns whether anything is cached for [key] (listing the directory the
  /// first time) and marks it used; false when nothing is, or when [key] is
  /// not admitted. Reads no frame.
  Future<bool> open(FrameCacheKey key) async {
    _checkAlive();
    if (!key.admitted()) return false;
    if (_animations[key] case final animation?) {
      _touch(animation);
      return true;
    }
    if (_files == null) return false;
    await _ensureScanned();
    final stem = key.toFileStem();
    if (!_disk.containsKey(stem)) return false;
    _useFile(stem, opened: true);
    return true;
  }

  /// Whether frame [index] of [key] is cached, in memory or in a file.
  bool has(FrameCacheKey key, int index) => _lookup(key, index) != null;

  /// Where frame [index] of [key] can be restored from, or null; marks the
  /// animation recently used.
  ///
  /// A frame of a file is answered for any index that is not negative: the
  /// reader checks the file's own table, and a frame it cannot serve is a
  /// restore that fails (see [invalidate]).
  CachedFrame? frame(FrameCacheKey key, int index) {
    final found = _lookup(key, index);
    switch (found) {
      case CachedFrameBytes():
        _touch(_animations[key]!);
      case CachedFrameFile():
        _useFile(key.toFileStem());
      case null:
        break;
    }
    return found;
  }

  CachedFrame? _lookup(FrameCacheKey key, int index) {
    if (index < 0) return null;
    if (_animations[key] case final animation?
        when index < animation.frames.length) {
      if (animation.frames[index] case final bytes?) {
        return CachedFrame.bytes(bytes);
      }
    }
    final stem = key.toFileStem();
    if (!_disk.containsKey(stem)) return null;
    return CachedFrame.file(_files!.pathOf(stem), key, index);
  }

  /// Stores one compressed frame of an animation of [frameCount] frames.
  ///
  /// A frame already stored is kept (the first write wins), and so is an
  /// animation already on disk (its file serves it). Throws [ArgumentError]
  /// when [key] is not admitted or [frameCount] is not positive, [RangeError]
  /// when [index] is outside the animation, and [StateError] when
  /// [frameCount] disagrees with an earlier put or the cache is disposed.
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
    RangeError.checkValueInInterval(index, 0, frameCount - 1, 'index');
    final stem = key.toFileStem();
    if (_disk.containsKey(stem) && !_animations.containsKey(key)) return;
    final animation = _animations.putIfAbsent(
      key,
      () => _Animation(stem, frameCount, _nextFill++, lastUsed: _clock()),
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
      _track(_persist(key, animation));
    }
    _evictRam();
  }

  /// Drops one animation from both tiers: the resident frames and the file's
  /// entry at once (so [frame] stops answering it), the file itself once a
  /// write under way has finished. For an entry a renderer found damaged (its
  /// bytes decoded to nothing), which would otherwise be served again on
  /// every launch. Unknown keys are fine.
  ///
  /// A caller that renders on and [put]s again need not wait: the new frames
  /// build a fresh animation. A file-system failure is reported like any
  /// other, never thrown. An animation put again meanwhile and written keeps
  /// its file.
  Future<void> invalidate(FrameCacheKey key) {
    _checkAlive();
    if (_animations.remove(key) case final dropped?) {
      _ramBytes -= dropped.bytes;
      dropped.invalidated = true;
    }
    if (_files == null) return Future.value();
    final stem = key.toFileStem();
    _disk.remove(stem);
    // Tracked like a write, so that [dispose] and [clear] wait for it too.
    final deletion = _deleteDamaged(key, stem, List.of(_pending));
    _track(deletion);
    return deletion;
  }

  /// Deletes the file [stem] once the writes in [before] have finished,
  /// unless [key] was put again and written meanwhile.
  Future<void> _deleteDamaged(
    FrameCacheKey key,
    String stem,
    List<Future<void>> before,
  ) async {
    await Future.wait(before);
    // Frames put again while this waited built a new animation and, once
    // complete, a new file under the same name: it is not the damaged one.
    if (_disk.containsKey(stem) || (_animations[key]?.persisted ?? false)) {
      return;
    }
    try {
      await _files!.delete(stem);
    } on Object catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Drops both tiers.
  Future<void> clear() async {
    final cleared = {
      for (final animation in _animations.values)
        (animation..invalidated = true).stem,
    };
    _animations.clear();
    _ramBytes = 0;
    // A write already under way finishes first, so that its file is among
    // those removed rather than appearing after the clear.
    await _settle();
    final files = _files;
    if (files == null) return;
    try {
      await _ensureScanned();
      // A write under way of a cleared animation published a file the disk
      // tier never listed: it goes too.
      for (final stem in {..._disk.keys, ...cleared}) {
        await files.delete(stem);
      }
      _disk.clear();
    } on Object catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Whether [dispose] was called: [open], [put] and [invalidate] then throw.
  bool get isDisposed => _disposed;

  /// Finishes pending writes, then stops; idempotent.
  Future<void> dispose() async {
    _disposed = true;
    await _settle();
  }

  /// Waits until no write or stamp is under way.
  Future<void> _settle() async {
    while (_pending.isNotEmpty) {
      await Future.wait<void>(List.of(_pending));
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
    final budget = diskBudgetBytes;
    if (budget == null) return;
    var total = _disk.values.fold<int>(0, (sum, f) => sum + f.bytes);
    while (total > budget && _disk.isNotEmpty) {
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

  /// Writes [animation], complete, as its file: the header, then the frames
  /// as they are, handed to the file system one by one. Once it is on disk
  /// its frames leave RAM.
  Future<void> _persist(FrameCacheKey key, _Animation animation) async {
    if (!_writable) return;
    final stem = animation.stem;
    // Copied out now: the animation may leave RAM before the write runs.
    final frames = List<Uint8List>.of(animation.frames.cast());
    try {
      await _ensureScanned();
      final header = FrameCacheCodec.header(key, [
        for (final frame in frames) frame.length,
      ]);
      final now = _clock();
      final unstamped = await _files!.write(stem, [
        header,
        ...frames,
      ], modified: now);
      // Invalidated (or cleared) while it was written: these are the damaged
      // frames, and invalidate deletes the file once this write settles.
      if (animation.invalidated) return;
      _disk[stem] = _DiskFile(header.length + animation.bytes, now);
      if (identical(_animations[key], animation)) {
        _animations.remove(key);
        _ramBytes -= animation.bytes;
      }
      // The entry is on disk: track it for eviction, keep writing, and only
      // tell the host that its timestamps do not stick.
      if (unstamped != null) _report(unstamped, StackTrace.current);
      await _evictDisk();
    } on Object catch (error, stack) {
      _writable = false;
      _report(error, stack);
    }
  }

  /// Marks the file [stem] used now and stamps it when it was just [opened]
  /// or its stamp is older than [_restampEvery] (not awaited: a stamp is
  /// bookkeeping).
  void _useFile(String stem, {bool opened = false}) {
    final file = _disk[stem];
    if (file == null) return;
    final now = _clock();
    file.lastUsed = now;
    if (!opened && now.difference(file.stamped) < _restampEvery) return;
    file.stamped = now;
    _track(_stamp(stem, now));
  }

  Future<void> _stamp(String stem, DateTime now) async {
    try {
      await _files!.touch(stem, now);
    } on Object catch (error, stack) {
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

  /// Marks [animation] used now.
  void _touch(_Animation animation) => animation.lastUsed = _clock();

  void _checkAlive() {
    if (_disposed) throw StateError('FrameCache is disposed');
  }

  /// Evicts until RAM fits the budget, keeping at least one animation: the
  /// idle ones first, least recently used first; then, when all that are
  /// left play, the one that started filling last.
  void _evictRam() {
    while (_ramBytes > ramBudgetBytes && _animations.length > 1) {
      final now = _clock();
      MapEntry<FrameCacheKey, _Animation>? idle;
      MapEntry<FrameCacheKey, _Animation>? youngest;
      for (final entry in _animations.entries) {
        final animation = entry.value;
        if (now.difference(animation.lastUsed) >= playingFor &&
            (idle == null ||
                animation.lastUsed.isBefore(idle.value.lastUsed))) {
          idle = entry;
        }
        if (youngest == null || animation.fill > youngest.value.fill) {
          youngest = entry;
        }
      }
      final victim = (idle ?? youngest)!;
      _animations.remove(victim.key);
      _ramBytes -= victim.value.bytes;
    }
  }
}

/// One animation's resident frames; a slot is null until its frame arrives.
final class _Animation {
  _Animation(this.stem, int frameCount, this.fill, {required this.lastUsed})
    : frames = List<Uint8List?>.filled(frameCount, null);

  /// The file this animation lives in, spelled once: lookups are per frame.
  final String stem;
  final List<Uint8List?> frames;

  /// When the fill started, as an order: larger is younger.
  final int fill;
  int filled = 0;
  int bytes = 0;
  DateTime lastUsed;

  /// Whether its file was (or is being) written.
  bool persisted = false;

  /// Whether it was found damaged (or cleared): a write under way of its
  /// frames does not count as a file.
  bool invalidated = false;

  bool get complete => filled == frames.length;
}

/// What the cache knows of one file in the directory.
final class _DiskFile {
  _DiskFile(this.bytes, this.lastUsed) : stamped = lastUsed;

  final int bytes;
  DateTime lastUsed;

  /// The time last written to the file's stamp.
  DateTime stamped;
}
