/// The composer's text crossing the wire contract: what a send carries, what
/// the budget refuses, which mentions survive, and what an edit loads.
///
/// Drives the real [ChatInputSet] and its composer; the markdown is checked
/// by decoding it back, so a dialect drift shows here.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

Future<AppServices> _services(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return services;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// A text of exactly [codePoints] plain code points that is heavily
/// formatted: a code block first, then words with every second one bold, the
/// first a link and the third inline code.
RichText _heavy(int codePoints) {
  const block = 'x = 1\n';
  // Words of two letters with a space between: three code points each but the
  // last; what does not divide goes onto the last word.
  final room = codePoints - block.length + 1;
  final count = room ~/ 3;
  final extra = room % 3;
  final plain = StringBuffer(block);
  final entities = <Entity>[const Entity(0, 5, EntityKind.codeBlock())];
  var offset = block.length;
  for (var i = 0; i < count; i++) {
    final word = i == count - 1 ? 'ab${'c' * extra}' : 'ab';
    if (i > 0) {
      plain.write(' ');
      offset++;
    }
    plain.write(word);
    if (i == 0) {
      entities.add(
        Entity(offset, word.length, const EntityKind.link('https://a.b')),
      );
    }
    if (i == 2) entities.add(Entity(offset, word.length, EntityKind.code));
    if (i.isOdd) entities.add(Entity(offset, word.length, EntityKind.bold));
    offset += word.length;
  }
  final text = RichText(plain.toString(), entities);
  assert(
    text.plain.runes.length == codePoints,
    'built ${text.plain.runes.length}',
  );
  return text;
}

/// A mention of a party the host has not resolved in the draft.
final RichText _ann = RichText('@Ann', const [
  Entity(0, 4, EntityKind.mention('7')),
]);

void main() {
  group('send', () {
    testWidgets('a bare URL, @name and #tag go out as links and decode back', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );

      await rig.typeInField(tester, 'https://a.b @al #tg');
      await rig.tapAction(tester, ChatComposerActions.primary);
      await _settle(tester);

      expect(rig.sent, [
        '[https://a.b](https://a.b) [@al](username:al) [#tg](hashtag:tg)',
      ]);
      expect(
        ChatBodyMarkdown.decode(rig.sent.single).entities.map((e) => e.kind),
        [
          const EntityKind.link('https://a.b'),
          const EntityKind.username('al'),
          const EntityKind.hashtag('tg'),
        ],
      );
    });
  });

  group('a message that begins with a marker character', () {
    // What the viewport paints is what the fork's parser reads from the sent
    // body: no backslash may reach it, and a hashtag must be a hashtag hit.
    Future<(String, List<String>, ChatInlineHit?)> sendAndRead(
      WidgetTester tester,
      String typed,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      await rig.typeInField(tester, typed);
      await rig.tapAction(tester, ChatComposerActions.primary);
      await _settle(tester);

      final body = rig.sent.single;
      final markdown = Markdown.fromString(body);
      final lines = [
        for (final block in markdown.blocks)
          if (block is MD$Paragraph)
            block.spans.map((span) => span.text).join(),
      ];
      final selection = ChatSelectionController();
      addTearDown(selection.dispose);
      selection.putBody(1, markdown);
      final hit = selection.inlineHitAt(messageId: 1, blockIndex: 0, offset: 1);
      return (body, lines, hit);
    }

    testWidgets(
      'a hashtag first is painted without a backslash, as a hashtag',
      (tester) async {
        final (body, lines, hit) = await sendAndRead(tester, '#design #travel');

        expect(body, '[#design](hashtag:design) [#travel](hashtag:travel)');
        expect(lines, ['#design #travel']);
        expect(hit, isA<ChatInlineHit$Hashtag>());
        expect((hit! as ChatInlineHit$Hashtag).tag, 'design');
      },
    );

    testWidgets('a message that is only a hashtag', (tester) async {
      final (_, lines, hit) = await sendAndRead(tester, '#tasks');

      expect(lines, ['#tasks']);
      expect((hit! as ChatInlineHit$Hashtag).tag, 'tasks');
    });

    testWidgets('an @name first is a mention hit with no backslash', (
      tester,
    ) async {
      final (_, lines, hit) = await sendAndRead(tester, '@user hi');

      expect(lines, ['@user hi']);
      expect(hit, isA<ChatInlineHit$Mention$Username>());
    });

    for (final typed in ['1. x', '- x', '> x', '# x']) {
      testWidgets('"$typed" typed as text stays text', (tester) async {
        final (_, lines, hit) = await sendAndRead(tester, typed);

        expect(lines, [typed]);
        expect(hit, isNull);
      });
    }
  });

  group('an emoji-only draft', () {
    testWidgets('is sent as typed, blank lines and trailing space kept', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      rig.set.composer.restore(const RichText.plain('\u{1F44D}\n\n\u{1F44D} '));

      await rig.set.submit();
      await _settle(tester);

      expect(rig.sent, ['\u{1F44D}\n\n\u{1F44D} ']);
    });

    testWidgets('and any other text is trimmed as before', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      rig.set.composer.restore(const RichText.plain(' hi '));

      await rig.set.submit();
      await _settle(tester);

      expect(rig.sent, ['hi']);
    });
  });

  group('the length budget', () {
    // The field of a full message grows past the window, so these send through
    // `submit`, which the button calls.
    testWidgets('4096 code points with heavy formatting send, nothing '
        'truncated', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      final text = _heavy(DemoConfig.messageLengthMax);
      rig.set.composer.restore(text);

      await rig.set.submit();
      await _settle(tester);

      expect(rig.sent, hasLength(1));
      final sent = ChatBodyMarkdown.decode(rig.sent.single);
      expect(sent.plain, text.plain);
      expect(sent.plain.runes, hasLength(4096));
    });

    testWidgets('4097 are refused and kept whole', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      final text = _heavy(DemoConfig.messageLengthMax + 1);
      rig.set.composer.restore(text);

      await rig.set.submit();
      await _settle(tester);

      expect(rig.sent, isEmpty);
      expect(rig.set.composer.length, 4097);
      expect(rig.set.composer.richText, text);
    });

    testWidgets('the button refuses an over-long text and sends the one '
        'that fits', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
        messageLengthLimit: 5,
      );

      await rig.typeInField(tester, 'abcdef');
      await rig.tapAction(tester, ChatComposerActions.primary);
      await _settle(tester);
      expect(rig.sent, isEmpty);

      rig.set.composer.restore(const RichText.plain('abcde'));
      await tester.pump();
      await rig.tapAction(tester, ChatComposerActions.primary);
      await _settle(tester);
      expect(rig.sent, ['abcde']);
    });

    testWidgets('the limit is the demo backend\'s message_length_max', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );

      expect(rig.set.messageLengthLimit, DemoConfig.messageLengthMax);
      expect(DemoConfig.messageLengthMax, 4096);
    });
  });

  group('mentions', () {
    testWidgets('one the host did not resolve in the draft is sent as a '
        'username', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      rig.set.composer.text.insert(_ann);
      await tester.pump();

      await rig.tapAction(tester, ChatComposerActions.primary);
      await _settle(tester);

      expect(rig.sent, ['[@Ann](username:Ann)']);
    });

    testWidgets('one the host marked as resolved stays a mention', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      rig.set.composer
        ..text.insert(_ann)
        ..trustMention('7');
      await tester.pump();

      await rig.tapAction(tester, ChatComposerActions.primary);
      await _settle(tester);

      expect(rig.sent, ['[@Ann](mention:7)']);
    });

    testWidgets('one loaded for edit survives the save', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      rig.set.beginEdit(5, 'hi [@Ann](mention:7)');
      await tester.pump();

      await rig.tapAction(tester, ChatComposerActions.primary);
      await _settle(tester);

      expect(rig.edited, ['5:hi [@Ann](mention:7)']);
    });
  });

  group('edit', () {
    testWidgets('a stored [url](url) edits as text and saves the same body', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      const stored = 'go [https://example.com](https://example.com)';

      rig.set.beginEdit(5, stored);
      await tester.pump();

      expect(rig.set.composer.richText.entities, isEmpty);
      expect(rig.set.composer.text.text, startsWith('go https://example.com'));

      await rig.tapAction(tester, ChatComposerActions.primary);
      await _settle(tester);

      expect(rig.edited, ['5:$stored']);
    });
  });
}
