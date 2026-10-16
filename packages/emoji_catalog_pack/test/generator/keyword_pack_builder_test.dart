import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_catalog_pack/generator.dart';
import 'package:test/test.dart';

// A woman technologist is a variant of the technologist; a light-skinned one
// is a tone variant of the technologist.
final _structure = EmojiCatalogStructure.decode(
  '@emoji-catalog-structure\t1\n'
  '@emoji\t18.0\n'
  '@group\tpeople-body\n'
  '@subgroup\tperson\n'
  '1F9D1-200D-1F4BB\t1F9D1-1F3FB-200D-1F4BB/1/\t1F469-200D-1F4BB//w\n'
  '@subgroup\tflag\n'
  '1F3F3-FE0F\n',
);

CldrAnnotations _annotations(String body) => CldrAnnotations.parse(body);

final _complete = [
  '<annotation cp="🧑‍💻">computer | technologist</annotation>',
  '<annotation cp="🧑‍💻" type="tts">technologist</annotation>',
  '<annotation cp="👩‍💻">woman | technologist | woman technologist</annotation>',
  '<annotation cp="👩‍💻" type="tts">woman technologist</annotation>',
  '<annotation cp="🏳" type="tts">white flag</annotation>',
].join();

KeywordPack _build(String xml) => buildKeywordPack(
  structure: _structure,
  annotations: _annotations(xml),
  locale: 'en',
  cldrVersion: '49',
);

ContentKey$Unicode _key(List<int> codePoints) =>
    ContentKey$Unicode(String.fromCharCodes(codePoints));

void main() {
  group('buildKeywordPack', () {
    test('has a record per entry and per gender-only variant, in order', () {
      final pack = _build(_complete);

      expect(pack.records.map((r) => r.key), [
        _key([0x1F9D1, 0x200D, 0x1F4BB]),
        _key([0x1F469, 0x200D, 0x1F4BB]),
        _key([0x1F3F3, 0xFE0F]),
      ]);
    });

    test('leaves out the tone variants, which are spoken as their entry', () {
      final pack = _build(_complete);

      expect(pack[_key([0x1F9D1, 0x1F3FB, 0x200D, 0x1F4BB])], isNull);
    });

    test('takes the name and keywords from CLDR', () {
      final record = _build(_complete)[_key([0x1F9D1, 0x200D, 0x1F4BB])]!;

      expect(record.spokenName, 'technologist');
    });

    test('drops a keyword that repeats the spoken name', () {
      final record = _build(_complete)[_key([0x1F469, 0x200D, 0x1F4BB])]!;

      expect(record.keywords, ['woman', 'technologist']);
    });

    test('finds an entry spelled with FE0F under the FE0F-less CLDR cp', () {
      final record = _build(_complete)[_key([0x1F3F3, 0xFE0F])]!;

      expect(record.spokenName, 'white flag');
      expect(record.keywords, isEmpty);
    });

    test('stamps the locale and the CLDR version', () {
      final pack = _build(_complete);

      expect(pack.locale, 'en');
      expect(pack.cldrVersion, '49');
    });

    test('names the entry that has no spoken name in the locale', () {
      expect(
        () => _build(
          _complete.replaceFirst(
            '<annotation cp="🏳" type="tts">white flag</annotation>',
            '',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('1F3F3-FE0F'),
          ),
        ),
      );
    });
  });
}
