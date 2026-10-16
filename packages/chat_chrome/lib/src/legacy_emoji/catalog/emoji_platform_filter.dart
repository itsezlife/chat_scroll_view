import 'dart:async';

import 'package:chat_chrome/src/legacy_emoji/emoji_item.dart';

/// Filters glyphs unsupported on the host platform (Android IME font set).
abstract class EmojiPlatformFilter {
  /// Returns [items] unchanged when filtering is unavailable.
  FutureOr<List<UnicodeEmojiItem>> filter(List<UnicodeEmojiItem> items);
}

/// No-op filter — used in tests and when filtering is disabled.
final class PassthroughEmojiPlatformFilter implements EmojiPlatformFilter {
  @override
  FutureOr<List<UnicodeEmojiItem>> filter(List<UnicodeEmojiItem> items) =>
      items;
}
