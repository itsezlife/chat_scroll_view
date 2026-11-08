import 'package:chat_scroll_view_example/src/features/chat/data/byte_cache.dart';

/// The web hook behind [ByteCache.directory]: no files here, so no disk tier.
ByteCache? $directoryByteCache(String directory, {required int budgetBytes}) =>
    null;
