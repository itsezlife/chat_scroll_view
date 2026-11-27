/// The message length budget: a code-point count of the plain text, a counter
/// at 100 or fewer remaining, and a primary action that refuses and shakes
/// when the count is negative.
///
/// **Seam:** [ComposerView] over a [ComposerSpec] with a
/// `messageLengthLimit`, observed through what the primary action's handler
/// receives and what the counter draws.
library;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;

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
    int? counterFrom,
    Map<ShortcutActivator, Intent>? shortcuts,
    listen.ValueListenable<ChatCapabilities>? capabilities,
  }) {
    // Registered after the controller's disposal, so it runs before it.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    return tester.pumpWidget(
      composerHarness(
        ComposerView(
          controller: composer,
          capabilities: capabilities,
          shortcuts: shortcuts,
          spec: ComposerSpec(
            messageLengthLimit: limit,
            messageLengthCounterFrom: counterFrom,
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

  final counterKey = find.byKey(const ValueKey('composer-length-counter'));

  // The count the counter shows (or rolls to); null with no counter up.
  String? counter(WidgetTester tester) {
    if (counterKey.evaluate().isEmpty) return null;
    return '${tester.widget<ComposerRollingNumber>(counterKey).value}';
  }

  Color? counterColor(WidgetTester tester) =>
      tester.widget<ComposerRollingNumber>(counterKey).style.color;

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(send());
    await tester.pump();
  }

  group('from the chat capabilities', () {
    testWidgets('the default capabilities give 4096 code points', (
      tester,
    ) async {
      await pump(
        tester,
        limit: null,
        capabilities: FakeChatCapabilitiesSource(),
      );
      composer.restore(RichText.plain('a' * 4097));
      await tester.pumpAndSettle();
      expect(counter(tester), '-1');
      await tapSend(tester);
      expect(sent, isEmpty);

      composer.restore(RichText.plain('a' * 4096));
      await tester.pumpAndSettle();
      await tapSend(tester);
      expect(sent, hasLength(1));
    });

    testWidgets('a changed limit reaches the counter live', (tester) async {
      final source = FakeChatCapabilitiesSource();
      await pump(tester, limit: null, capabilities: source);
      composer.restore(RichText.plain('a' * 50));
      await tester.pumpAndSettle();
      expect(counter(tester), isNull);

      source.update(limits: const ChatLimits(messageLength: 120));
      await tester.pumpAndSettle();
      expect(counter(tester), '70');
    });

    testWidgets('an explicit spec limit wins', (tester) async {
      await pump(
        tester,
        limit: 200,
        capabilities: FakeChatCapabilitiesSource(
          const ChatCapabilities(limits: ChatLimits(messageLength: 120)),
        ),
      );
      composer.restore(RichText.plain('a' * 150));
      await tester.pumpAndSettle();
      expect(counter(tester), '50');
    });

    testWidgets('no capabilities and no limit: no budget', (tester) async {
      await pump(tester, limit: null);
      composer.restore(RichText.plain('a' * 5000));
      await tester.pumpAndSettle();
      expect(counter(tester), isNull);
    });
  });

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
      expect(counter(tester), '0');
    });

    testWidgets('one past the limit is refused and shakes the counter', (
      tester,
    ) async {
      await pump(tester);
      composer.restore(_formatted(_limit + 1));
      await tester.pumpAndSettle();
      final resting = tester.getTopLeft(counterKey);

      await tapSend(tester);
      await tester.pump(const Duration(milliseconds: 40));

      expect(sent, isEmpty);
      expect(tester.getTopLeft(counterKey).dx, isNot(resting.dx));

      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopLeft(counterKey), resting);
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
      expect(counter(tester), isNull);

      composer.restore(_formatted(_limit - 100));
      await tester.pumpAndSettle();
      expect(counter(tester), '100');
    });

    testWidgets('follows the typing and goes negative', (tester) async {
      await pump(tester);
      composer.restore(_formatted(_limit - 2));
      await tester.pumpAndSettle();
      expect(counter(tester), '2');

      composer.insertText('xyz');
      await tester.pumpAndSettle();

      expect(counter(tester), '-1');
    });

    testWidgets('counts a limit change at once', (tester) async {
      await pump(tester, limit: 1000);
      composer.restore(_formatted(950));
      await tester.pumpAndSettle();
      expect(counter(tester), '50');

      await pump(tester, limit: 960);
      expect(counter(tester), '10');
    });

    testWidgets('a host threshold of 800 of 1000 hides at 799, shows at 800', (
      tester,
    ) async {
      await pump(tester, limit: 1000, counterFrom: 800);

      composer.restore(_formatted(799));
      await tester.pumpAndSettle();
      expect(counter(tester), isNull);

      composer.restore(_formatted(800));
      await tester.pumpAndSettle();
      expect(counter(tester), '200');
    });

    testWidgets('the count takes the destructive colour at 1000 and over', (
      tester,
    ) async {
      await pump(tester, limit: 1000, counterFrom: 800);
      final palette = ChromePalette.forBrightness(Brightness.light);

      composer.restore(_formatted(999));
      await tester.pumpAndSettle();
      expect(counterColor(tester), isNot(palette.destructive));

      composer.restore(_formatted(1001));
      await tester.pumpAndSettle();
      expect(counterColor(tester), palette.destructive);

      composer.restore(_formatted(1000));
      await tester.pumpAndSettle();
      expect(counterColor(tester), isNot(palette.destructive));
    });
  });

  group('the counter stands and moves as the reference has it', () {
    Iterable<Text> digits(WidgetTester tester) => tester.widgetList<Text>(
      find.descendant(of: counterKey, matching: find.byType(Text)),
    );

    // The slide of the digit [digit] in the counter.
    Offset slideOf(WidgetTester tester, String digit) => tester
        .widgetList<FractionalTranslation>(
          find.descendant(
            of: counterKey,
            matching: find.byType(FractionalTranslation),
          ),
        )
        .firstWhere((slide) => (slide.child! as Text).data == digit)
        .translation;

    testWidgets('over the primary button, centred on it, its bottom on the '
        "button's top, outside the island and taking none of its room", (
      tester,
    ) async {
      await pump(tester);
      composer.restore(_formatted(_limit - 150));
      await tester.pumpAndSettle();
      final island = tester.getRect(find.byType(GlassSurface)).height;

      composer.restore(_formatted(_limit - 50));
      await tester.pumpAndSettle();
      final count = tester.getRect(counterKey);
      final button = tester.getRect(send());
      expect(count.center.dx, closeTo(button.center.dx, 0.5));
      expect(count.bottom, lessThanOrEqualTo(button.top + 0.5));
      expect(
        count.bottom,
        greaterThan(button.top - ComposerLengthCounter.height),
      );
      expect(
        tester.getRect(find.byType(GlassSurface)).height,
        island,
        reason: 'the island keeps its height',
      );
    });

    testWidgets('it scales in from half its size as it fades in, over '
        '100 ms', (tester) async {
      await pump(tester);
      composer.restore(_formatted(_limit - 101));
      await tester.pumpAndSettle();
      composer.restore(_formatted(_limit - 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: counterKey, matching: find.byType(Opacity)).last,
      );
      expect(opacity.opacity, inExclusiveRange(0, 1));
      final scales = tester
          .widgetList<Transform>(
            find.ancestor(of: counterKey, matching: find.byType(Transform)),
          )
          .map((t) => t.transform.entry(0, 0));
      expect(
        scales,
        contains(inExclusiveRange(ComposerLengthCounter.hiddenScale, 1)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(of: counterKey, matching: find.byType(Opacity))
                  .last,
            )
            .opacity,
        1,
      );
    });

    testWidgets('a count change rolls the digits that changed: up from below '
        'as the count falls, the unchanged digit still', (tester) async {
      await pump(tester);
      composer.restore(_formatted(_limit - 52));
      await tester.pumpAndSettle();
      expect(digits(tester).map((t) => t.data), ['5', '2']);

      composer.insertText('x');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Mid-roll: the 5 stays, the 2 goes out as the 1 comes in.
      expect(digits(tester).map((t) => t.data), ['5', '2', '1']);
      expect(slideOf(tester, '1').dy, greaterThan(0), reason: 'from below');

      await tester.pump(const ChromeMotion.standard().digitRoll.duration);
      expect(digits(tester).map((t) => t.data), ['5', '1']);

      // Growing: the new digit comes down from above.
      composer.backspace();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(slideOf(tester, '2').dy, lessThan(0), reason: 'from above');
      await tester.pumpAndSettle();
    });
  });
}
