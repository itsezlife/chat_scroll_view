/// The message length budget: a code-point count of the plain text, a counter
/// at 100 or fewer remaining, and a primary action that refuses and shakes
/// when the count is negative.
///
/// **Seam:** [ComposerView] over a [ComposerSpec] with a
/// `messageLengthLimit`, observed through what the primary action's handler
/// receives and what the counter draws.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

const _limit = 4096;

/// [length] code units of `abcd abcd ...` ending in a letter, with bold over
/// every second word and a link over the third.
RichText _formatted(int length) {
  final buffer = StringBuffer();
  while (buffer.length < length) {
    buffer.write('abcd ');
  }
  final plain = '${buffer.toString().substring(0, length - 1)}z';
  final words = (plain.length / 5).floor();
  return RichText(plain, [
    for (var word = 1; word < words; word += 2)
      Entity(word * 5, 4, EntityKind.bold),
    const Entity(10, 4, EntityKind.link('https://example.com')),
  ]);
}

void main() {
  late ComposerController composer;
  late List<String> sent;

  setUp(() {
    composer = ComposerController();
    sent = [];
    addTearDown(composer.dispose);
  });

  Future<void> pump(
    WidgetTester tester, {
    int? limit = _limit,
    Map<ShortcutActivator, Intent>? shortcuts,
  }) {
    // Registered after the controller's disposal, so it runs before it.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    return tester.pumpWidget(
      composerHarness(
        ComposerView(
          controller: composer,
          shortcuts: shortcuts,
          spec: ComposerSpec(
            messageLengthLimit: limit,
            actions: [
              ActionDescriptor(
                id: 'send',
                icon: ChromeIconId.send,
                semanticLabel: 'Send',
                primary: true,
                onTap: () => sent.add(composer.richText.plain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Finder send() => find.byKey(const ValueKey<String>('send'));

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(send());
    await tester.pump();
  }

  group('the count', () {
    test('is code points of the plain text, not code units', () {
      composer.restore(RichText.plain('\u{1F600}' * 4096));

      expect(composer.length, 4096);
      expect(composer.text.text.length, 8192);
    });

    test('ignores formatting', () {
      composer.restore(_formatted(_limit));

      expect(composer.length, _limit);
      expect(composer.richText.entities, isNotEmpty);
    });
  });

  group('the send', () {
    testWidgets('a text of exactly the limit with heavy formatting goes', (
      tester,
    ) async {
      await pump(tester);
      composer.restore(
        RichText('${_formatted(_limit - 10).plain}\nprint(1);', [
          ..._formatted(_limit - 10).entities,
          const Entity(_limit - 9, 9, EntityKind.codeBlock()),
        ]),
      );
      await tester.pumpAndSettle();
      expect(composer.length, _limit);

      await tapSend(tester);

      expect(sent, hasLength(1));
    });

    testWidgets('a text of 4096 surrogate pairs goes', (tester) async {
      await pump(tester);
      composer.restore(RichText.plain('\u{1F600}' * 4096));
      await tester.pumpAndSettle();

      await tapSend(tester);

      expect(sent, hasLength(1));
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('one past the limit is refused and shakes the counter', (
      tester,
    ) async {
      await pump(tester);
      composer.restore(_formatted(_limit + 1));
      await tester.pumpAndSettle();
      final resting = tester.getTopLeft(find.text('-1'));

      await tapSend(tester);
      await tester.pump(const Duration(milliseconds: 40));

      expect(sent, isEmpty);
      expect(tester.getTopLeft(find.text('-1')).dx, isNot(resting.dx));

      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopLeft(find.text('-1')), resting);
    });

    testWidgets(
      'the submit key sends within the budget and is refused over it',
      (tester) async {
        await pump(
          tester,
          shortcuts: const ComposerShortcutPolicy.desktop().shortcuts,
        );
        composer
          ..restore(_formatted(_limit))
          ..requestFocus();
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(sent, hasLength(1));

        composer.insertText('x');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(sent, hasLength(1));
      },
    );

    testWidgets('without a limit nothing is refused or counted', (
      tester,
    ) async {
      await pump(tester, limit: null);
      composer.restore(_formatted(_limit * 2));
      await tester.pumpAndSettle();

      await tapSend(tester);

      expect(sent, hasLength(1));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && RegExp(r'^-?\d+$').hasMatch(widget.data ?? ''),
        ),
        findsNothing,
      );
    });
  });

  group('the counter', () {
    testWidgets('is hidden at 101 remaining and shown at 100', (tester) async {
      await pump(tester);

      composer.restore(_formatted(_limit - 101));
      await tester.pumpAndSettle();
      expect(find.text('101'), findsNothing);

      composer.restore(_formatted(_limit - 100));
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('follows the typing and goes negative', (tester) async {
      await pump(tester);
      composer.restore(_formatted(_limit - 2));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);

      composer.insertText('xyz');
      await tester.pumpAndSettle();

      expect(find.text('-1'), findsOneWidget);
    });

    testWidgets('counts a limit change at once', (tester) async {
      await pump(tester, limit: 1000);
      composer.restore(_formatted(950));
      await tester.pumpAndSettle();
      expect(find.text('50'), findsOneWidget);

      await pump(tester, limit: 960);
      expect(find.text('10'), findsOneWidget);
    });
  });
}
