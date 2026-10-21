import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

/// Links addressed by position instead of by selection: what the edit menu
/// needs to edit the link under the pointer while the selection stays where
/// it is.
void main() {
  late ComposerTextController controller;

  setUp(() => controller = ComposerTextController());
  tearDown(() => controller.dispose());

  // 'go to site now', 'site' (6..10) linked.
  final linked = RichText('go to site now', const [
    Entity(6, 4, EntityKind.link('https://a.example')),
  ]);

  void load({int selection = 0}) => controller.restore(
    linked,
    selection: TextSelection.collapsed(offset: selection),
  );

  group('linkAt', () {
    test('finds the link over a character of it', () {
      load();

      for (final index in [6, 8, 9]) {
        final link = controller.linkAt(index);
        expect(
          link?.range,
          const TextRange(start: 6, end: 10),
          reason: '$index',
        );
        expect(link?.url, 'https://a.example');
      }
    });

    test('finds nothing before, after or away from the link', () {
      load();

      for (final index in [0, 5, 10, 13]) {
        expect(controller.linkAt(index), isNull, reason: '$index');
      }
    });

    test('finds nothing outside the text', () {
      load();

      expect(controller.linkAt(-1), isNull);
      expect(controller.linkAt(99), isNull);
    });
  });

  group('applyLinkTo', () {
    test('re-points the link and leaves the selection where it was', () {
      load(selection: 2);

      controller.applyLinkTo(
        const TextRange(start: 6, end: 10),
        'https://b.example',
      );

      expect(
        controller.richText,
        RichText('go to site now', const [
          Entity(6, 4, EntityKind.link('https://b.example')),
        ]),
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    test('is refused for an empty URL', () {
      load();

      controller.applyLinkTo(const TextRange(start: 6, end: 10), '');

      expect(controller.richText, linked);
    });
  });

  group('removeLinkFrom', () {
    test('takes the link off and keeps the text and the selection', () {
      load(selection: 12);

      controller.removeLinkFrom(const TextRange(start: 6, end: 10));

      expect(controller.richText, const RichText.plain('go to site now'));
      expect(controller.selection, const TextSelection.collapsed(offset: 12));
    });
  });
}
