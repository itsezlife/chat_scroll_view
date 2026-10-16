import 'package:chat_chrome/src/legacy_emoji/catalog/emoji_catalog_search.dart';
import 'package:chat_chrome/src/legacy_emoji/emoji_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = <UnicodeEmojiItem>[
    UnicodeEmojiItem(
      glyph: '🐱',
      keywords: <String>['cat', 'kitten', 'pet'],
      supportsSkinTone: false,
    ),
    UnicodeEmojiItem(
      glyph: '🐶',
      keywords: <String>['dog', 'puppy', 'pet'],
      supportsSkinTone: false,
    ),
  ];

  test('prefix keyword search returns matches', () {
    final hits = EmojiCatalogSearch.search('cat', catalog);
    expect(hits.map((e) => e.glyph), ['🐱']);
  });

  test('empty query returns nothing', () {
    expect(EmojiCatalogSearch.search('   ', catalog), isEmpty);
  });
}
