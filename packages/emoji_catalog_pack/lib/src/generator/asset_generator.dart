import 'package:emoji_catalog_pack/src/generator/cldr_annotations.dart';
import 'package:emoji_catalog_pack/src/generator/emoji_keyword_pack_builder.dart';
import 'package:emoji_catalog_pack/src/generator/emoji_test_file.dart';
import 'package:emoji_catalog_pack/src/generator/inputs_lock.dart';
import 'package:emoji_catalog_pack/src/generator/structure_builder.dart';

/// The text of every shipped asset of the pack, by path inside the package.
///
/// [readInput] returns the text of a pinned input by its name (see
/// [InputsPlan.sources]); the caller is responsible for it being the bytes
/// [lock] pins. The result is a pure function of the inputs: equal inputs give
/// equal text, which is what the reproducibility check relies on.
///
/// Throws a [FormatException] when `emoji-test.txt` is of another Emoji
/// version than the lock states, or any step finds the data does not fit.
Map<String, String> generateAssets({
  required InputsLock lock,
  required String Function(String name) readInput,
}) {
  final emojiTest = EmojiTestFile.parse(readInput('emoji-test.txt'));
  if (emojiTest.emojiVersion != lock.emojiVersion) {
    throw FormatException(
      'emoji-test.txt is Emoji ${emojiTest.emojiVersion}, '
      'the lock pins ${lock.emojiVersion}.',
    );
  }
  final structure = buildStructure(emojiTest);
  final cldrVersion = lock.plan.cldrVersion;
  return {
    'assets/structure.tsv': structure.encode(),
    for (final locale in lock.locales)
      'assets/keywords/$locale.tsv': buildEmojiKeywordPack(
        structure: structure,
        annotations: CldrAnnotations.merge([
          CldrAnnotations.parse(readInput('cldr/annotations/$locale.xml')),
          CldrAnnotations.parse(
            readInput('cldr/annotationsDerived/$locale.xml'),
          ),
        ]),
        locale: locale,
        cldrVersion: cldrVersion,
      ).encode(),
    'assets/LICENSE-UNICODE.txt': _licence(
      lock.emojiVersion,
      cldrVersion,
      readInput('cldr/LICENSE'),
    ),
  };
}

String _licence(String emojiVersion, String cldrVersion, String text) =>
    'The structure and keyword assets in this directory are generated from\n'
    'Unicode Emoji $emojiVersion (emoji-test.txt) and CLDR $cldrVersion\n'
    '(annotations), which are licensed as follows.\n'
    '\n'
    '${text.trim()}\n';
