import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_catalog_pack/generator.dart';
import 'package:test/test.dart';

final String _sha = '0' * 64;

final InputsLock _lock = InputsLock.pin(
  InputsPlan(
    emojiVersion: '18.0',
    cldrTag: 'release-49',
    locales: const ['en', 'de'],
  ),
  (source) => _sha,
);

String _annotations(String tts) => [
  '<annotation cp="😀">face | $tts</annotation>',
  '<annotation cp="😀" type="tts">$tts</annotation>',
].join();

final Map<String, String> _inputs = {
  'emoji-test.txt': [
    '# Version: 18.0',
    '# group: Smileys & Emotion',
    '# subgroup: face-smiling',
    '1F600 ; fully-qualified # 😀 E1.0 grinning face',
  ].join('\n'),
  'cldr/LICENSE': 'UNICODE LICENSE V3',
  'cldr/annotations/en.xml': _annotations('grinning face'),
  'cldr/annotationsDerived/en.xml': '',
  'cldr/annotations/de.xml': _annotations('grinsendes Gesicht'),
  'cldr/annotationsDerived/de.xml': '',
};

Map<String, String> _generate([Map<String, String>? inputs]) => generateAssets(
  lock: _lock,
  readInput: (name) => (inputs ?? _inputs)[name]!,
);

void main() {
  group('generateAssets', () {
    test('produces the structure, one pack per locale and the licence', () {
      expect(
        _generate().keys,
        unorderedEquals([
          'assets/structure.tsv',
          'assets/keywords/en.tsv',
          'assets/keywords/de.tsv',
          'assets/LICENSE-UNICODE.txt',
        ]),
      );
    });

    test('writes a structure the reader accepts', () {
      final structure = EmojiCatalogStructure.decode(
        _generate()['assets/structure.tsv']!,
      );

      expect(structure.emojiVersion, '18.0');
      expect(structure.entries, hasLength(1));
    });

    test('stamps each pack with its locale and the CLDR release', () {
      final pack = KeywordPack.decode(_generate()['assets/keywords/de.tsv']!);

      expect(pack.locale, 'de');
      expect(pack.cldrVersion, '49');
      expect(pack.records.single.spokenName, 'grinsendes Gesicht');
    });

    test('ships the Unicode licence text after the provenance', () {
      final licence = _generate()['assets/LICENSE-UNICODE.txt']!;

      expect(licence, contains('Emoji 18.0'));
      expect(licence, contains('CLDR 49'));
      expect(licence, endsWith('UNICODE LICENSE V3\n'));
    });

    test('is deterministic', () {
      expect(_generate(), _generate());
    });

    test('refuses an emoji-test file of another version than the lock', () {
      final other = {
        ..._inputs,
        'emoji-test.txt': _inputs['emoji-test.txt']!.replaceFirst(
          '18.0',
          '17.0',
        ),
      };

      expect(() => _generate(other), throwsFormatException);
    });
  });
}
