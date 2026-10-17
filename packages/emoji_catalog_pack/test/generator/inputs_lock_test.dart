import 'package:emoji_catalog_pack/generator.dart';
import 'package:test/test.dart';

final String _sha = 'a' * 64;

InputsLock _lock({List<String> locales = const ['en', 'de']}) => InputsLock.pin(
  InputsPlan(
    emojiVersion: '18.0',
    cldrTag: 'release-49-beta4',
    shortcodesRef: '11.0.0',
    locales: locales,
  ),
  (source) => _sha,
);

void main() {
  group('InputsPlan', () {
    final plan = InputsPlan(
      emojiVersion: '18.0',
      cldrTag: 'release-49-beta4',
      shortcodesRef: '11.0.0',
      locales: const ['en', 'de'],
    );
    String urlOf(String name) =>
        plan.sources.singleWhere((s) => s.name == name).url;

    test('pins Emoji data by versioned URL', () {
      expect(
        urlOf('emoji-test.txt'),
        'https://unicode.org/Public/18.0.0/emoji/emoji-test.txt',
      );
    });

    test('pins CLDR files by release tag', () {
      expect(
        urlOf('cldr/annotationsDerived/de.xml'),
        'https://raw.githubusercontent.com/unicode-org/cldr/'
        'release-49-beta4/common/annotationsDerived/de.xml',
      );
    });

    test('lists annotations and derived annotations of every locale', () {
      expect(
        plan.sources.map((s) => s.name),
        unorderedEquals([
          'emoji-test.txt',
          'cldr/LICENSE',
          'cldr/annotations/en.xml',
          'cldr/annotationsDerived/en.xml',
          'cldr/annotations/de.xml',
          'cldr/annotationsDerived/de.xml',
          'emoji-toolkit/emoji.json',
          'emoji-toolkit/LICENSE.md',
        ]),
      );
    });

    test('pins the shortcode data and its licence by toolkit tag', () {
      expect(
        urlOf('emoji-toolkit/emoji.json'),
        'https://raw.githubusercontent.com/joypixels/emoji-toolkit/'
        '11.0.0/emoji.json',
      );
      expect(
        urlOf('emoji-toolkit/LICENSE.md'),
        'https://raw.githubusercontent.com/joypixels/emoji-toolkit/'
        '11.0.0/LICENSE.md',
      );
    });

    test('labels the CLDR release without the tag prefix', () {
      expect(plan.cldrVersion, '49-beta4');
    });
  });

  group('InputsLock text', () {
    test('reads back what encode wrote', () {
      final lock = _lock();

      final parsed = InputsLock.parse(lock.encode());

      expect(parsed.encode(), lock.encode());
      expect(parsed.locales, ['en', 'de']);
      expect(parsed.emojiVersion, '18.0');
      expect(parsed.shortcodesRef, '11.0.0');
      expect(parsed.input('emoji-test.txt').sha256, _sha);
    });

    test('rejects a checksum that is not 64 hex digits', () {
      final text = _lock().encode().replaceFirst(_sha, 'abc');

      expect(() => InputsLock.parse(text), throwsFormatException);
    });

    test('rejects a locale without its inputs', () {
      final text = _lock()
          .encode()
          .split('\n')
          .where((line) => !line.contains('annotationsDerived/de.xml'))
          .join('\n');

      expect(() => InputsLock.parse(text), throwsFormatException);
    });

    test('rejects an input pinned to a URL of another version', () {
      // Only the URLs move; the cldr-tag line keeps the planned release.
      final text = _lock().encode().replaceAll(
        'release-49-beta4/',
        'release-48/',
      );

      expect(() => InputsLock.parse(text), throwsFormatException);
    });

    test('rejects a lock without the shortcodes ref', () {
      final text = _lock()
          .encode()
          .split('\n')
          .where((line) => !line.startsWith('shortcodes-ref '))
          .join('\n');

      expect(() => InputsLock.parse(text), throwsFormatException);
    });

    test('rejects shortcode data pinned to another toolkit tag', () {
      final text = _lock().encode().replaceFirst(
        'shortcodes-ref 11.0.0',
        'shortcodes-ref 10.0.0',
      );

      expect(() => InputsLock.parse(text), throwsFormatException);
    });

    test('ignores comments and blank lines', () {
      final text = '# pinned\n\n${_lock().encode()}';

      expect(InputsLock.parse(text).locales, ['en', 'de']);
    });
  });
}
