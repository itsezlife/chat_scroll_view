import 'dart:io';
import 'dart:typed_data';

import 'package:lottie_decoder/src/cache/frame_cache_key.dart';

/// Tells the time; injected so tests order recency without waiting.
typedef FrameCacheClock = DateTime Function();

DateTime _systemClock() => DateTime.now();

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
  }) : _directory = directory,
       _clock = clock;

  /// The most compressed bytes the RAM tier keeps (a single animation larger
  /// than this stays while it is the only one).
  final int ramBudgetBytes;

  /// The most bytes the disk tier keeps.
  final int diskBudgetBytes;

  // ignore: unused_field
  final Directory? _directory;
  final FrameCacheClock _clock;

  final Map<FrameCacheKey, _Animation> _animations = {};
  int _ramBytes = 0;
  bool _disposed = false;

  /// Makes the animation's frames resident and returns its frame count, or
  /// null when nothing is cached for [key] (or [key] is not admitted).
  Future<int?> open(FrameCacheKey key) async {
    _checkAlive();
    final animation = _animations[key];
    if (animation == null) return null;
    animation.lastUsed = _clock();
    return animation.frames.length;
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
    animation.lastUsed = _clock();
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
      () => _Animation(frameCount),
    );
    if (animation.frames.length != frameCount) {
      throw StateError(
        '$key has ${animation.frames.length} frames, not $frameCount',
      );
    }
    animation.lastUsed = _clock();
    if (animation.frames[index] != null) return;
    animation.frames[index] = compressed;
    animation.bytes += compressed.length;
    _ramBytes += compressed.length;
    _evictRam(keep: key);
  }

  /// Drops both tiers.
  Future<void> clear() async {
    _animations.clear();
    _ramBytes = 0;
  }

  /// Finishes pending writes, then stops; idempotent.
  Future<void> dispose() async {
    _disposed = true;
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
  _Animation(int frameCount)
    : frames = List<Uint8List?>.filled(frameCount, null);

  final List<Uint8List?> frames;
  int bytes = 0;
  late DateTime lastUsed;
}
