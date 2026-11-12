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

  /// Where the entry [stem] is, for a reader on another isolate that reads
  /// its frames one at a time (`CachedFrameFile`); the entry need not exist.
  String pathOf(String stem);

  /// Writes the entry [stem] atomically, as [chunks] one after another, and
  /// stamps it [modified]. The chunks are written as they are, never joined
  /// into one buffer first: an entry is tens of megabytes.
  ///
  /// Returns why the stamp failed, or null. The entry is published before it
  /// is stamped, so a stamp that fails (a file system without timestamps) is
  /// not a failed write: the entry is there, and only its recency is off. The
  /// caller decides whether to tell anyone.
  Future<Object?> write(
    String stem,
    List<Uint8List> chunks, {
    required DateTime modified,
  });

  /// Stamps the entry [stem] used at [modified].
  Future<void> touch(String stem, DateTime modified);

  /// Deletes the entry [stem]; absent is fine.
  Future<void> delete(String stem);
}
