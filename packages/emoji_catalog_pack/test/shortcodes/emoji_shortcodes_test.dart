import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:test/test.dart';

const _source =
    '@emoji-catalog-shortcodes\t1\n'
    '@source\temoji-toolkit 11.0.0\n'
    '1F600\t:grinning:\n'
    '1F3F3-FE0F\t:flag_white:\n';

ContentKey$Unicode _key(List<int> codePoints) =>
    ContentKey$Unicode(String.fromCharCodes(codePoints));

void main() {
  group('EmojiShortcodes.decode', () {
    final shortcodes = EmojiShortcodes.decode(_source);

    test('reads where the codes come from', () {
      expect(shortcodes.source, 'emoji-toolkit 11.0.0');
    });

    test('finds a code by key', () {
      expect(shortcodes[_key([0x1F600])], ':grinning:');
    });

    test('finds a key spelled with FE0F as the file spells it', () {
      expect(shortcodes[_key([0x1F3F3, 0xFE0F])], ':flag_white:');
    });

    test('has no code for a key it does not list', () {
      expect(shortcodes[_key([0x1F603])], isNull);
      expect(shortcodes[_key([0x1F3F3])], isNull);
    });

    test('lists its codes in file order', () {
      expect(shortcodes.codes.keys, [
        _key([0x1F600]),
        _key([0x1F3F3, 0xFE0F]),
      ]);
    });

    test('reads back what encode wrote', () {
      expect(shortcodes.encode(), _source);
    });

    test('rejects a key listed twice', () {
      expect(
        () => EmojiShortcodes.decode('${_source}1F600\t:grin:\n'),
        throwsFormatException,
      );
    });

    test('rejects a record without a code', () {
      expect(
        () => EmojiShortcodes.decode(
          _source.replaceFirst('1F600\t:grinning:', '1F600\t'),
        ),
        throwsFormatException,
      );
      expect(
        () => EmojiShortcodes.decode(
          _source.replaceFirst('1F600\t:grinning:', '1F600'),
        ),
        throwsFormatException,
      );
    });

    test('rejects a record with a field too many', () {
      expect(
        () => EmojiShortcodes.decode(
          _source.replaceFirst(':grinning:', ':grinning:\t:grin:'),
        ),
        throwsFormatException,
      );
    });

    test('rejects a key that is not a code point sequence', () {
      expect(
        () => EmojiShortcodes.decode(_source.replaceFirst('1F600', 'smile')),
        throwsFormatException,
      );
    });

    test('rejects a file without its header', () {
      expect(
        () => EmojiShortcodes.decode('1F600\t:grinning:\n'),
        throwsFormatException,
      );
      expect(
        () => EmojiShortcodes.decode(
          _source.replaceFirst('@source\temoji-toolkit 11.0.0\n', ''),
        ),
        throwsFormatException,
      );
    });

    test('rejects a file of another format version', () {
      expect(
        () => EmojiShortcodes.decode(
          _source.replaceFirst('shortcodes\t1', 'shortcodes\t9'),
        ),
        throwsFormatException,
      );
    });
  });

  group('EmojiShortcodes.encode', () {
    EmojiShortcodes withCode(String code) => EmojiShortcodes(
      source: 'test',
      codes: {
        _key([0x1F600]): code,
      },
    );

    test('refuses a code the format cannot carry', () {
      for (final code in ['', 'tab\there', 'line\nbreak', ' :padded: ']) {
        expect(withCode(code).encode, throwsArgumentError, reason: code);
      }
    });
  });
}
