/// The probe as the emoji data layer's platform filter: items the system
/// cannot draw are dropped, everything unknown stays.
///
/// **Seam:** `EmojiPlatformFilter.filter`, the contract the catalog provider
/// already filters through; the probe is fed bytes directly.
library;

import 'dart:typed_data';

import 'package:chat_chrome/src/legacy_emoji/legacy_emoji.dart';
import 'package:emoji_data/emoji_data.dart' show MissingGlyphProbe;
import 'package:flutter_test/flutter_test.dart';

const _reference = 'REF';
final Uint8List _tofu = Uint8List.fromList(List.filled(16, 7));
final Uint8List _art = Uint8List.fromList(List.filled(16, 9));

void main() {
  const cat = UnicodeEmojiItem(glyph: 'cat');
  const dog = UnicodeEmojiItem(glyph: 'dog');
  const owl = UnicodeEmojiItem(glyph: 'owl');

  MissingGlyphProbe newProbe() => MissingGlyphProbe(
    glyphs: ['cat', 'dog', 'owl'],
    artVersion: 'art-1',
    references: const [_reference],
  );

  test('drops the items the probe found unsupported, keeps the rest', () async {
    final probe = newProbe()
      ..observe(_reference, _tofu)
      ..observe('cat', _art)
      ..observe('dog', _tofu)
      ..observe('owl', _art);

    final kept = await GlyphProbeEmojiPlatformFilter(
      probe,
    ).filter([cat, dog, owl]);

    expect(kept, [cat, owl]);
  });

  test('keeps items that have no verdict yet', () async {
    final probe = newProbe()..observe('cat', _art);

    final kept = await GlyphProbeEmojiPlatformFilter(
      probe,
    ).filter([cat, dog, owl]);

    expect(kept, [cat, dog, owl]);
  });
}
