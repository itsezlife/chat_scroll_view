import 'dart:convert';

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

const _family = '\u{1F468}‍\u{1F469}‍\u{1F467}';

RichText _draft() {
  const smile = InlineContentRef(
    key: ContentKey.document('5368'),
    alternativeText: '\u{1F642}',
  );
  const text = 'Hi bold $_family @al link \u{1F642}!';
  final bold = text.indexOf('bold');
  final family = text.indexOf(_family);
  final mention = text.indexOf('@al');
  final link = text.indexOf('link');
  final emoji = text.indexOf('\u{1F642}');
  return RichText(text, [
    Entity(bold, 4, EntityKind.bold),
    Entity(
      family,
      _family.length,
      const EntityKind.inlineContent(
        ContentKey.unicode('1F468-200D-1F469-200D-1F467'),
      ),
    ),
    Entity(mention, 3, const EntityKind.mention('al')),
    Entity(link, 4, const EntityKind.link('https://example.com')),
    Entity(emoji, 2, EntityKind.inlineContent(smile.key)),
  ]);
}

void main() {
  late ComposerTextController controller;

  setUp(() => controller = ComposerTextController());
  tearDown(() => controller.dispose());

  group('restore', () {
    test('puts the text, entities and caret in place', () {
      final draft = _draft();

      controller.restore(draft);

      expect(controller.text, draft.plain);
      expect(controller.richText, draft);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: draft.length),
      );
    });

    test('keeps a given selection', () {
      controller.restore(
        RichText('abc'),
        selection: const TextSelection(baseOffset: 0, extentOffset: 2),
      );

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
    });

    test('notifies when only the entities differ', () {
      controller.restore(RichText('abc'));
      var notified = 0;
      controller.addListener(() => notified++);

      controller.restore(
        RichText('abc', const [Entity(0, 3, EntityKind.bold)]),
      );

      expect(notified, 1);
      expect(controller.richText.entities, hasLength(1));
    });

    test('replaces earlier content wholesale', () {
      controller.restore(
        RichText('old', const [Entity(0, 3, EntityKind.bold)]),
      );

      controller.restore(RichText('new'));

      expect(controller.richText, RichText('new'));
    });
  });

  group('draft round trip', () {
    test('survives JSON into a fresh controller', () {
      controller.restore(_draft());

      final stored = jsonEncode(controller.richText.toJson());
      final fresh = ComposerTextController();
      addTearDown(fresh.dispose);
      fresh.restore(RichText.fromJson(jsonDecode(stored)));

      expect(fresh.text, controller.text);
      expect(fresh.richText, controller.richText);
    });

    test('survives markdown into a fresh controller', () {
      controller.restore(_draft());

      final fresh = ComposerTextController(
        initial: RichTextMarkdown.decode(
          RichTextMarkdown.encode(controller.richText),
        ),
      );
      addTearDown(fresh.dispose);

      expect(fresh.richText, controller.richText);
    });

    test('edits after a restore keep the restored entities in step', () {
      controller.restore(_draft());
      final bold = controller.text.indexOf('bold');

      controller.selection = TextSelection.collapsed(offset: bold + 2);
      controller.value = controller.value.copyWith(
        text: controller.text.replaceRange(bold + 2, bold + 2, '-'),
        selection: TextSelection.collapsed(offset: bold + 3),
      );

      expect(
        controller.richText.entities.first,
        Entity(bold, 5, EntityKind.bold),
      );
      expect(
        RichText.fromJson(controller.richText.toJson()),
        controller.richText,
      );
    });
  });
}
