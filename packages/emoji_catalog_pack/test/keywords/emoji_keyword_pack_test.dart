import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:test/test.dart';

const _source =
    '@emoji-catalog-keywords\t1\n'
    '@locale\tde\n'
    '@cldr\t49\n'
    '1F600\tgrinsendes Gesicht\tGesicht|grinsen|lachen\n'
    '1F44B-1F3FB\twinkende Hand: helle Hautfarbe\n';

ContentKey$Unicode _key(List<int> codePoints) =>
    ContentKey$Unicode(String.fromCharCodes(codePoints));

void main() {
  group('EmojiKeywordPack.decode', () {
    final pack = EmojiKeywordPack.decode(_source);

    test('reads the locale and the CLDR version', () {
      expect(pack.locale, 'de');
      expect(pack.cldrVersion, '49');
    });

    test('finds a record by key', () {
      final record = pack[_key([0x1F600])]!;

      expect(record.spokenName, 'grinsendes Gesicht');
      expect(record.keywords, ['Gesicht', 'grinsen', 'lachen']);
    });

    test('gives a record without keywords an empty list', () {
      final record = pack[_key([0x1F44B, 0x1F3FB])]!;

      expect(record.spokenName, 'winkende Hand: helle Hautfarbe');
      expect(record.keywords, isEmpty);
    });

    test('has no record for a key it does not list', () {
      expect(pack[_key([0x1F603])], isNull);
    });

    test('lists its records in file order', () {
      expect(pack.records.map((r) => r.key), [
        _key([0x1F600]),
        _key([0x1F44B, 0x1F3FB]),
      ]);
    });

    test('reads back what encode wrote', () {
      expect(pack.encode(), _source);
    });

    test('rejects a key listed twice', () {
      expect(
        () => EmojiKeywordPack.decode('${_source}1F600\tagain\n'),
        throwsFormatException,
      );
    });

    test('rejects a record without a spoken name', () {
      expect(
        () => EmojiKeywordPack.decode(
          _source.replaceFirst('1F600\tgrinsendes Gesicht', '1F600\t'),
        ),
        throwsFormatException,
      );
    });

    test('rejects a file of another format version', () {
      expect(
        () => EmojiKeywordPack.decode(
          _source.replaceFirst('keywords\t1', 'keywords\t9'),
        ),
        throwsFormatException,
      );
    });
  });

  group('EmojiKeywordPack.encode', () {
    test('refuses a name the format cannot carry', () {
      final pack = EmojiKeywordPack(
        locale: 'en',
        cldrVersion: '49',
        records: [
          EmojiKeywordRecord(
            key: _key([0x1F600]),
            spokenName: 'tab\there',
            keywords: const [],
          ),
        ],
      );

      expect(pack.encode, throwsArgumentError);
    });

    test('refuses a keyword that contains the separator', () {
      final pack = EmojiKeywordPack(
        locale: 'en',
        cldrVersion: '49',
        records: [
          EmojiKeywordRecord(
            key: _key([0x1F600]),
            spokenName: 'grinning face',
            keywords: const ['a|b'],
          ),
        ],
      );

      expect(pack.encode, throwsArgumentError);
    });
  });
}
