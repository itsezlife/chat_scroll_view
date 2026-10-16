import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/src/generator/cldr_annotations.dart';
import 'package:emoji_catalog_pack/src/keywords/keyword_pack.dart';
import 'package:emoji_catalog_pack/src/structure/emoji_catalog_structure.dart';

/// Builds the keyword pack of [locale] for [structure] from [annotations].
///
/// A record exists for every entry's base and for every variant without a
/// skin tone (the gendered forms are emoji in their own right with names and
/// keywords of their own: "woman technologist"). Tone variants get no record:
/// a tone changes the look, not the meaning, so a host speaks and finds them
/// as their entry, and their per-locale names would add about a third to
/// every pack.
///
/// A keyword equal to the spoken name is left out; a search treats the name as
/// a keyword anyway, and CLDR repeats it in most lists.
///
/// Throws a [FormatException] naming the sequence when [annotations] has no
/// spoken name for a sequence that needs a record: a locale that does not
/// cover the catalog must stop the generator, not ship a pack with holes.
KeywordPack buildKeywordPack({
  required EmojiCatalogStructure structure,
  required CldrAnnotations annotations,
  required String locale,
  required String cldrVersion,
}) {
  KeywordRecord recordOf(ContentKey$Unicode key) {
    final annotation = annotations[key.sequence.runes.toList()];
    final name = annotation?.spokenName;
    if (annotation == null || name == null) {
      throw FormatException(
        'No spoken name for ${key.encoded.substring(8)} in $locale.',
      );
    }
    return KeywordRecord(
      key: key,
      spokenName: name,
      keywords: [
        for (final keyword in annotation.keywords)
          if (keyword != name) keyword,
      ],
    );
  }

  return KeywordPack(
    locale: locale,
    cldrVersion: cldrVersion,
    records: [
      for (final entry in structure.entries) ...[
        recordOf(entry.base),
        for (final variant in entry.variants)
          if (variant.modifiers.tones.isEmpty) recordOf(variant.key),
      ],
    ],
  );
}
