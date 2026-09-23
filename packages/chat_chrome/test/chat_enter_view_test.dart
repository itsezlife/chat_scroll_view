import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ChatComposerController composer;

  setUp(() {
    composer = ChatComposerController();
  });

  tearDown(() {
    composer.dispose();
  });

  testWidgets('default path mounts the stock text field', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('inputBuilder replaces the stock row', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
          inputBuilder: (context, field) => const Text(
            key: Key('custom-enter-row'),
            'custom row',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('custom-enter-row')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'inputBuilder field handle uses the same controller and focusNode',
    (tester) async {
      ChatEnterFieldHandle? seen;

      await tester.pumpWidget(
        _harness(
          ChatEnterView(
            composer: composer,
            onSend: () {},
            onEmojiPressed: () {},
            inputBuilder: (context, field) {
              seen = field;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(seen, isNotNull);
      expect(identical(seen!.controller, composer.text), isTrue);
      expect(identical(seen!.focusNode, composer.focusNode), isTrue);
    },
  );

  testWidgets('topBanner mounts stock ChatEnterTopView', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
          topBanner: const ChatEnterTopBanner(
            title: 'Ada',
            subtitle: 'hello',
          ),
          onTopBannerClose: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatEnterTopView), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('topBannerBuilder replaces stock top banner', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
          topBanner: const ChatEnterTopBanner(
            title: 'ignored',
            subtitle: 'ignored',
          ),
          topBannerBuilder: (context) => const Text(
            key: Key('custom-top-banner'),
            'custom banner',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('custom-top-banner')), findsOneWidget);
    expect(find.byType(ChatEnterTopView), findsNothing);
    expect(find.text('ignored'), findsNothing);
  });

  testWidgets('top banner clip-reveals when it appears', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ChatEnterTopView), findsNothing);

    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
          topBanner: const ChatEnterTopBanner(
            title: 'Edit message',
            subtitle: 'hello',
          ),
          onTopBannerClose: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ChatEnterTopView), findsOneWidget);

    // Mid-flight: host height is between 0 and barHeight.
    await tester.pump(KeyboardPanelMotion.duration * 0.4);
    final sized = tester.widgetList<SizedBox>(find.byType(SizedBox));
    final reveal = sized.where(
      (s) =>
          s.height != null &&
          s.height! > 0 &&
          s.height! < ChatEnterTopView.barHeight,
    );
    expect(reveal, isNotEmpty);

    await tester.pumpAndSettle();
    expect(find.text('Edit message'), findsOneWidget);
  });

  testWidgets('top banner stays mounted until hide settles', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
          topBanner: const ChatEnterTopBanner(
            title: 'Ada',
            subtitle: 'hello',
          ),
          onTopBannerClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatEnterTopView), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
        ),
      ),
    );
    await tester.pump();
    // Still painting while t → 0.
    expect(find.byType(ChatEnterTopView), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(ChatEnterTopView), findsNothing);
  });

  /// User symptom: during edit-banner reveal the field content "floats"
  /// vertically instead of the island growing upward from a fixed bottom.
  testWidgets(
    'banner reveal keeps input bottom Y fixed (bottom-anchored host)',
    (tester) async {
      const inputKey = Key('enter-input');

      await tester.pumpWidget(
        _bottomAnchoredHarness(
          ChatEnterView(
            composer: composer,
            onSend: () {},
            onEmojiPressed: () {},
            inputBuilder: (context, field) => SizedBox(
              key: inputKey,
              height: ChatEnterView.rowHeight,
              width: double.infinity,
              child: const ColoredBox(color: Color(0xFF00FF00)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final before = tester.getBottomLeft(find.byKey(inputKey)).dy;

      await tester.pumpWidget(
        _bottomAnchoredHarness(
          ChatEnterView(
            composer: composer,
            onSend: () {},
            onEmojiPressed: () {},
            topBanner: const ChatEnterTopBanner(
              title: 'Edit message',
              subtitle: 'hello',
            ),
            onTopBannerClose: () {},
            inputBuilder: (context, field) => SizedBox(
              key: inputKey,
              height: ChatEnterView.rowHeight,
              width: double.infinity,
              child: const ColoredBox(color: Color(0xFF00FF00)),
            ),
          ),
        ),
      );

      // Sample mid-flight — bottom of the input row must not drift.
      for (var i = 0; i < 5; i++) {
        await tester.pump(KeyboardPanelMotion.duration * 0.15);
        final mid = tester.getBottomLeft(find.byKey(inputKey)).dy;
        expect(
          mid,
          moreOrLessEquals(before, epsilon: 1.0),
          reason: 'input bottom drifted at sample $i (before=$before mid=$mid)',
        );
      }
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byKey(inputKey)).dy,
        moreOrLessEquals(before, epsilon: 1.0),
      );
    },
  );

  /// User symptom: focus blinks during banner / height animation.
  testWidgets('focus stays through banner reveal', (tester) async {
    await tester.pumpWidget(
      _bottomAnchoredHarness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    composer.focusNode.requestFocus();
    await tester.pump();
    expect(composer.focusNode.hasFocus, isTrue);

    await tester.pumpWidget(
      _bottomAnchoredHarness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
          topBanner: const ChatEnterTopBanner(
            title: 'Edit',
            subtitle: 'x',
          ),
          onTopBannerClose: () {},
        ),
      ),
    );

    for (var i = 0; i < 8; i++) {
      await tester.pump(KeyboardPanelMotion.duration * 0.1);
      expect(
        composer.focusNode.hasFocus,
        isTrue,
        reason: 'focus lost at sample $i',
      );
    }
    await tester.pumpAndSettle();
    expect(composer.focusNode.hasFocus, isTrue);
  });

  /// Mid-reveal must show the **top** of the banner first as `t` rises.
  /// A bottom-aligned overflow clip shows the wrong half and reads as float.
  testWidgets('banner mid-reveal shows top of strip first', (tester) async {
    const topKey = Key('banner-top');
    const botKey = Key('banner-bot');

    await tester.pumpWidget(
      _bottomAnchoredHarness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _bottomAnchoredHarness(
        ChatEnterView(
          composer: composer,
          onSend: () {},
          onEmojiPressed: () {},
          topBannerBuilder: (context) => SizedBox(
            height: ChatEnterTopView.barHeight,
            child: Column(
              children: const [
                SizedBox(key: topKey, height: 24, width: double.infinity),
                SizedBox(key: botKey, height: 24, width: double.infinity),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(KeyboardPanelMotion.duration * 0.5);

    final topRect = tester.getRect(find.byKey(topKey));
    final botRect = tester.getRect(find.byKey(botKey));
    final enterBottom = tester.getBottomLeft(find.byType(ChatEnterView)).dy;
    final fieldTop = enterBottom - ChatEnterView.rowHeight;
    // Bottom-aligned OverflowBox parked the strip at fieldTop - barH (fully
    // above the clip). Top-aligned reveal keeps the strip's top flush with
    // the growing host (between fieldTop-barH and fieldTop).
    final bottomAlignedBugTop = fieldTop - ChatEnterTopView.barHeight;
    expect(topRect.top, greaterThan(bottomAlignedBugTop + 5));
    expect(topRect.top, lessThan(fieldTop));
    expect(botRect.top, moreOrLessEquals(topRect.top + 24, epsilon: 1));
  });
}

Widget _harness(Widget child) {
  return MaterialApp(
    home: ChatChromeTheme(
      colors: const ChatChromeColors(),
      child: Scaffold(body: child),
    ),
  );
}

/// Mirrors the product host: [Positioned] bottom + [Column] min — island
/// must grow upward, not re-center.
Widget _bottomAnchoredHarness(Widget child) {
  return MaterialApp(
    home: ChatChromeTheme(
      colors: const ChatChromeColors(),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: child,
            ),
          ],
        ),
      ),
    ),
  );
}
