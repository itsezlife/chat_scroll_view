/// `content_model` classifies emoji-only text with a BMP emoji set of its own
/// (it depends on no workspace package, so it cannot read this catalogue).
/// This test is the guard that the two agree, in both directions.
///
/// **Seam:** `EmojiOnlyText.of` against the shipped `EmojiCatalog`.
library;

import 'package:content_model/content_model.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

import '../support/pack_assets.dart';

EmojiOnly? _classify(String text) => EmojiOnlyText.of(RichText.plain(text));

void main() {
  late EmojiCatalog catalog;
  late Set<String> sequences;

  setUpAll(() async {
    catalog = EmojiCatalog(
      await EmojiCatalogLoader(readShippedAsset).structure(),
    );
    sequences = {
      for (final entry in catalog.entries)
        for (final key in [entry.base, for (final v in entry.variants) v.key])
          key.sequence,
    };
  });

  test('every emoji of the catalogue is one emoji-only item', () {
    expect(sequences.length, greaterThan(1800));
    for (final sequence in sequences) {
      final result = _classify(sequence);
      expect(
        result?.items.map((item) => item.key),
        [ContentKey.unicode(sequence)],
        reason: sequence.runes
            .map((r) => r.toRadixString(16).toUpperCase())
            .join('-'),
      );
    }
  });

  test('every BMP symbol in the window that is no catalogue emoji is not', () {
    final starts = {for (final sequence in sequences) sequence.runes.first};
    for (final codePoint in [
      0x00A9,
      0x00AE,
      for (var c = 0x203C; c <= 0x3299; c++) c,
    ]) {
      expect(
        _classify(String.fromCharCode(codePoint)) != null,
        starts.contains(codePoint),
        reason: codePoint.toRadixString(16).toUpperCase(),
      );
    }
  });
}
