/// Shared data of the emoji page tests: a small catalogue shaped like the real
/// one (tone variants, gender variants, entries without any), the collections
/// a source would publish for it, and a search source.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';

ContentKey$Unicode key(String glyph) =>
    ContentKey.unicode(glyph) as ContentKey$Unicode;

const _tones = [
  '\u{1F3FB}',
  '\u{1F3FC}',
  '\u{1F3FD}',
  '\u{1F3FE}',
  '\u{1F3FF}',
];

/// A hand with five tone variants: `👍🏻` .. `👍🏿`.
final EmojiEntry thumbsUp = EmojiEntry(
  base: key('👍'),
  variants: [
    for (var i = 0; i < _tones.length; i++)
      EmojiVariant(
        key('👍${_tones[i]}'),
        EmojiModifiers(tones: [SkinTone.values[i]]),
      ),
  ],
);

/// A person with gender variants only.
final EmojiEntry detective = EmojiEntry(
  base: key('🕵'),
  variants: [
    EmojiVariant(
      key('🕵‍♀'),
      EmojiModifiers(genders: const [EmojiGender.woman]),
    ),
    EmojiVariant(key('🕵‍♂'), EmojiModifiers(genders: const [EmojiGender.man])),
  ],
);

/// A couple: two people with a tone each, so many combinations.
final EmojiEntry couple = EmojiEntry(
  base: key('💑'),
  variants: [
    for (var a = 0; a < 3; a++)
      for (var b = 0; b < 3; b++)
        EmojiVariant(
          key('💑${_tones[a]}${_tones[b]}'),
          EmojiModifiers(tones: [SkinTone.values[a], SkinTone.values[b]]),
        ),
  ],
);

/// Entries without variants.
final EmojiEntry heart = EmojiEntry(base: key('❤'));
final EmojiEntry grin = EmojiEntry(base: key('😀'));
final EmojiEntry flagJapan = EmojiEntry(base: key('🇯🇵'));

/// Every entry of the fixture catalogue.
final List<EmojiEntry> catalogue = [
  grin,
  thumbsUp,
  detective,
  couple,
  heart,
  flagJapan,
];

/// The entry [k] is the base or a variant of, as the data layer answers it.
EmojiEntry? entryOf(ContentKey k) {
  for (final entry in catalogue) {
    if (entry.modifiersOf(k) != null) return entry;
  }
  return null;
}

CollectionItem item(String glyph) => CollectionItem.described(
  ContentDescriptor(
    key: key(glyph),
    semanticKind: SemanticKind.unicodeEmoji,
    mediaForm: MediaForm.glyph,
  ),
);

/// The ids the fixture source lists after the recents.
const categories = [
  'smileys-emotion',
  'people-body',
  'animals-nature',
  'flags',
];

/// Glyphs of a category: [count] copies of distinct private-use stand-ins
/// first, then the catalogue entries that belong to it.
List<String> glyphsOf(String category, {int count = 24}) {
  final base = categories.indexOf(category) * 100;
  return [
    for (var i = 0; i < count; i++) String.fromCharCode(0x1F400 + base + i),
    ...switch (category) {
      'smileys-emotion' => ['😀', '❤'],
      'people-body' => ['👍', '🕵', '💑'],
      'flags' => ['🇯🇵'],
      _ => const <String>[],
    },
  ];
}

/// A source of the fixture catalogue with [recents] as its recents.
FakeCollectionSource source({
  List<String> recents = const [],
  int count = 24,
}) => FakeCollectionSource([
  FakeCollectionSpec(
    CollectionId.recent,
    pages: FakePages([
      [for (final glyph in recents) item(glyph)],
    ]),
  ),
  for (final category in categories)
    FakeCollectionSpec(
      CollectionId.category(category),
      pages: FakePages([
        [for (final glyph in glyphsOf(category, count: count)) item(glyph)],
      ]),
    ),
]);
