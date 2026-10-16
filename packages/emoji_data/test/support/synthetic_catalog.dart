import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_data/emoji_data.dart';

/// The key spelled by [hex] code points (`1F44D-1F3FB`).
ContentKey$Unicode key(String hex) =>
    ContentKey.parse('unicode:$hex') as ContentKey$Unicode;

/// An entry with a light and a dark tone variant (`<hex>-1F3FB`, `-1F3FF`).
EmojiEntry toned(String hex) => EmojiEntry(
  base: key(hex),
  variants: [
    EmojiVariant(
      key('$hex-1F3FB'),
      EmojiModifiers(tones: const [SkinTone.light]),
    ),
    EmojiVariant(
      key('$hex-1F3FF'),
      EmojiModifiers(tones: const [SkinTone.dark]),
    ),
  ],
);

/// An entry without variants.
EmojiEntry plain(String hex) => EmojiEntry(base: key(hex));

/// Groups named by [groups] id, each holding the entries given.
EmojiCatalog catalogOf(Map<String, List<EmojiEntry>> groups) => EmojiCatalog(
  EmojiCatalogStructure(
    emojiVersion: '18.0',
    groups: [
      for (final MapEntry(key: id, value: entries) in groups.entries)
        EmojiCatalogGroup(
          id: id,
          subgroups: [EmojiCatalogSubgroup(id: '$id-sub', entries: entries)],
        ),
    ],
  ),
);

/// Five faces in `faces` and a toned hand and a plain heart in `things`.
EmojiCatalog sampleCatalog() => catalogOf({
  'faces': [
    plain('1F600'),
    plain('1F603'),
    plain('1F604'),
    plain('1F601'),
    plain('1F606'),
  ],
  'things': [toned('1F44D'), plain('2764-FE0F')],
});
