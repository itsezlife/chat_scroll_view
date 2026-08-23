import 'package:emoji_data/src/emoji_item.dart';

/// Keyword search over a loaded Unicode catalog.
abstract final class EmojiCatalogSearch {
  static final RegExp _whitespace = RegExp(r'\s+');

  static List<UnicodeEmojiItem> search(
    String query,
    List<UnicodeEmojiItem> catalog,
  ) {
    final q = query.trim();
    if (q.isEmpty || catalog.isEmpty) return const <UnicodeEmojiItem>[];

    final keywordSet = q
        .split(_whitespace)
        .where((part) => part.isNotEmpty)
        .map((part) => part.toLowerCase())
        .toSet();
    if (keywordSet.isEmpty) return const <UnicodeEmojiItem>[];

    return catalog.where((item) {
      final emojiKeywordSet = item.keywords
          .map((k) => k.toLowerCase())
          .toSet();

      final matchFirstKeyword = emojiKeywordSet.any(
        (emojiKeyword) => emojiKeyword.startsWith(keywordSet.first),
      );

      var matchKeywords = false;
      if (matchFirstKeyword) {
        matchKeywords = keywordSet.skip(1).every((keyword) {
          return emojiKeywordSet.any(
            (emojiKeyword) => emojiKeyword.startsWith(keyword),
          );
        });
      }

      final matchEmoji = item.glyph == q;
      return matchKeywords || matchEmoji;
    }).toList(growable: false);
  }
}
