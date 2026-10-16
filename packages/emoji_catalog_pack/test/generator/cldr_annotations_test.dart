import 'package:emoji_catalog_pack/generator.dart';
import 'package:test/test.dart';

const _xml = '''
<?xml version="1.0" encoding="UTF-8" ?>
<ldml>
	<identity><language type="en"/></identity>
	<annotations>
		<annotation cp="😀">face | grin | grinning face</annotation>
		<annotation cp="😀" type="tts">grinning face</annotation>
		<annotation cp="❤" draft="contributed">heart | love</annotation>
		<annotation cp="❤" type="tts" draft="contributed">red heart</annotation>
		<annotation cp="&amp;">ampersand | and</annotation>
		<annotation cp="&amp;" type="tts">ampersand</annotation>
		<!-- <annotation cp="🫥">hidden</annotation> -->
	</annotations>
</ldml>
''';

void main() {
  group('CldrAnnotations.parse', () {
    final annotations = CldrAnnotations.parse(_xml);

    test('splits the keyword list on the pipe', () {
      expect(annotations[[0x1F600]]!.keywords, [
        'face',
        'grin',
        'grinning face',
      ]);
    });

    test('reads the spoken name from the tts annotation', () {
      expect(annotations[[0x1F600]]!.spokenName, 'grinning face');
    });

    test('finds a sequence whichever way it spells FE0F', () {
      expect(annotations[[0x2764, 0xFE0F]]!.spokenName, 'red heart');
      expect(annotations[[0x2764]]!.spokenName, 'red heart');
    });

    test('decodes XML entities', () {
      expect(annotations[[0x26]]!.keywords, ['ampersand', 'and']);
    });

    test('ignores commented-out annotations', () {
      expect(annotations[[0x1FAE5]], isNull);
    });

    test('lets the first source win over a later one', () {
      final merged = CldrAnnotations.merge([
        CldrAnnotations.parse(
          '<annotation cp="😀">a</annotation> '
          '<annotation cp="😀" type="tts">first</annotation>',
        ),
        CldrAnnotations.parse(
          '<annotation cp="😀">b</annotation> '
          '<annotation cp="😀" type="tts">second</annotation> '
          '<annotation cp="😃" type="tts">only second</annotation>',
        ),
      ]);

      expect(merged[[0x1F600]]!.spokenName, 'first');
      expect(merged[[0x1F603]]!.spokenName, 'only second');
    });

    test('has no keywords for an annotation that only names', () {
      final names = CldrAnnotations.parse(
        '<annotation cp="😃" type="tts">smile</annotation>',
      );

      expect(names[[0x1F603]]!.keywords, isEmpty);
    });
  });
}
