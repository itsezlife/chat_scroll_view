import 'dart:typed_data';

import 'package:meta/meta.dart';

/// What a scan found for one cached animation.
@immutable
final class FrameCacheFileInfo {
  /// Creates the description of a file.
  const FrameCacheFileInfo({
    required this.stem,
    required this.bytes,
    required this.modified,
  });

  /// The file name without extension: `FrameCacheKey.toFileStem`.
  final String stem;

  /// Its size.
  final int bytes;

  /// When it was last written or used, as the cache's clock told it.
  final DateTime modified;
}

/// The entries of one [FrameCache]'s disk tier: the only place that touches
/// the file system, so the cache's rules (budgets, recency, damage) are read
/// without any of its mechanics, and nothing else in the package needs
/// `dart:io`.
///
/// An entry is named by its stem (`FrameCacheKey.toFileStem`). The native
/// implementation is [DirectoryFrameCacheFiles]; the web has none, and a cache
/// there keeps memory only.
///
/// [FrameCache]: package:lottie_decoder/lottie_decoder.dart
/// [DirectoryFrameCacheFiles]: package:lottie_decoder/lottie_decoder.dart
abstract interface class FrameCacheFiles {
  /// Lists the entries and removes anything that is not a complete one. An
  /// absent store holds nothing.
  Future<List<FrameCacheFileInfo>> scan();

  /// The bytes of the entry [stem], or null when there is none.
  Future<Uint8List?> read(String stem);

  /// Writes the entry [stem] atomically and stamps it [modified].
  Future<void> write(
    String stem,
    Uint8List bytes, {
    required DateTime modified,
  });

  /// Stamps the entry [stem] used at [modified].
  Future<void> touch(String stem, DateTime modified);

  /// Deletes the entry [stem]; absent is fine.
  Future<void> delete(String stem);
}
