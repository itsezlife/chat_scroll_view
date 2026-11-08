import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/data/byte_cache_stub.dart'
    if (dart.library.io) 'package:chat_scroll_view_example/src/features/chat/data/byte_cache_io.dart'
    as platform;

/// Bytes kept between launches under a name: the disk tier a host
/// `ContentFetcher` owns (ADR 022).
///
/// A cache, not a store: [read] may answer null for a name once written (the
/// budget evicted it, or the platform cleared the folder), and a failed
/// [write] is lost without a word. Neither ever throws.
abstract interface class ByteCache {
  /// The bytes kept under [name], or null.
  Future<Uint8List?> read(String name);

  /// Keeps [bytes] under [name], replacing what was there.
  Future<void> write(String name, Uint8List bytes);

  /// A cache in the folder [directory] that keeps at most [budgetBytes],
  /// least recently used out first, or null where there are no files (the
  /// web).
  static ByteCache? directory(String directory, {required int budgetBytes}) =>
      platform.directoryByteCache(directory, budgetBytes: budgetBytes);
}
