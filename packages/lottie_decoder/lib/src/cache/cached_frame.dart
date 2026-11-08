import 'dart:typed_data';

import 'package:lottie_decoder/src/cache/frame_cache_key.dart';
import 'package:meta/meta.dart';

/// Where a frame the cache holds can be restored from: what
/// `FrameCache.frame` answers and what a restore job carries to the isolate
/// that decompresses it. A closed set.
@immutable
sealed class CachedFrame {
  const CachedFrame();

  /// A frame resident in memory.
  const factory CachedFrame.bytes(Uint8List bytes) = CachedFrameBytes;

  /// Frame [index] of [key] in the file at [path].
  const factory CachedFrame.file(String path, FrameCacheKey key, int index) =
      CachedFrameFile;
}

/// A frame resident in memory: an animation still being filled, or kept in a
/// cache that has no files.
final class CachedFrameBytes extends CachedFrame {
  /// Creates the frame of [bytes].
  const CachedFrameBytes(this.bytes);

  /// The compressed frame.
  final Uint8List bytes;
}

/// A frame of a persisted animation, read from its file by whoever restores
/// it: the UI isolate keeps only this reference, never the bytes.
///
/// [key] travels with it so the reader checks the file is that key's (the
/// header repeats it), and [index] is the frame of the animation: the file
/// holds the frames of its parity (`FrameParity`), and the reader finds it
/// among them.
final class CachedFrameFile extends CachedFrame {
  /// Creates the reference to frame [index] of [key] in the file at [path].
  const CachedFrameFile(this.path, this.key, this.index);

  /// The file.
  final String path;

  /// The animation the file must hold.
  final FrameCacheKey key;

  /// The frame of the animation.
  final int index;
}
