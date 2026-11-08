import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/data/environment_specific/byte_cache.dart'
    as environment_specific;

/// Bytes kept between launches under a name: the disk tier a host
/// `ContentFetcher` owns (ADR 022).
///
/// A cache, not a store: [read] may answer null for a name once written (the
/// media store removed it, or the platform cleared the folder), and a failed
/// [write] is lost without a word. Neither ever throws.
abstract interface class ByteCache {
  /// The bytes kept under [name], or null.
  Future<Uint8List?> read(String name);

  /// Keeps [bytes] under [name], replacing what was there.
  Future<void> write(String name, Uint8List bytes);

  /// A cache in the folder [directory], or null where there are no files (the
  /// web). It keeps no budget: the folder is a tier of a `MediaDiskCache`,
  /// which removes what goes unused, and a read marks its file used.
  static ByteCache? directory(String directory) =>
      environment_specific.$directoryByteCache(directory);
}
