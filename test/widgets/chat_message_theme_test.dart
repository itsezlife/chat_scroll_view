import 'package:chat_scroll_view/src/chat_widgets/chat_message_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_chrome.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessageThemeData metrics', () {
    const layout = ChatMessageThemeData.fallback;

    test('columnWidth caps at contentMaxWidth', () {
      expect(layout.columnWidth(300), 300);
      expect(layout.columnWidth(1200), layout.contentMaxWidth);
    });

    test('innerWidth subtracts horizontal padding', () {
      expect(
        layout.innerWidth(layout.contentMaxWidth),
        layout.contentMaxWidth - layout.padding.horizontal,
      );
    });

    test(
      'bubbleCap subtracts the avatar gutter and caps at bubbleMaxWidth',
      () {
        const tokens = ChatMessageThemeData(
          contentMaxWidth: 800,
          bubbleMaxWidth: 480,
          padding: EdgeInsets.symmetric(horizontal: 12),
          avatarSize: 32,
          avatarGap: 8,
        );
        expect(tokens.bubbleCap(400, hasAvatarGutter: false), 376);
        expect(tokens.bubbleCap(400, hasAvatarGutter: true), 336);
        expect(tokens.bubbleCap(1200, hasAvatarGutter: false), 480);
      },
    );

    test('gutter fits when the remainder covers row padding', () {
      expect(
        layout.selectionGutterFits(viewportWidth: 400, slotWidth: 44),
        isTrue,
      );
      expect(
        layout.selectionGutterFits(viewportWidth: 60, slotWidth: 44),
        isFalse,
      );
      expect(
        layout.selectionGutterFits(viewportWidth: 40, slotWidth: 44),
        isFalse,
      );
    });

    test('columnAlignment follows placement on a wide viewport', () {
      expect(
        layout.columnAlignment(viewportWidth: 1200, outgoing: true),
        AlignmentDirectional.centerStart,
      );
      expect(
        layout.columnAlignment(viewportWidth: 400, outgoing: true),
        AlignmentDirectional.centerEnd,
      );
      expect(
        layout.columnAlignment(viewportWidth: 400, outgoing: false),
        AlignmentDirectional.centerStart,
      );
    });

    test('run spacing defaults split runGap top and bottom', () {
      expect(layout.padding.top, 8);
      expect(layout.padding.bottom, 2);
      expect(layout.runGap, 2);
      expect(layout.topInset(isFirstInRun: true), 8);
      expect(layout.topInset(isFirstInRun: false), 1);
      expect(layout.bottomInset(isLastInRun: true), 2);
      expect(layout.bottomInset(isLastInRun: false), 1);
    });
  });

  group('DefaultSelectionChrome gutter', () {
    const slot = ChatSelectionMetrics.slotWidth;

    ChatSelectionChromeState stateAt(double mode) => ChatSelectionChromeState(
      id: 1,
      modeProgress: mode,
      selectProgress: 1,
      isSelectionMode: mode > 0,
      isSelected: true,
      onTap: () {},
      onLongPress: () {},
    );

    Widget app({
      required double mode,
      required Widget child,
      double width = 400,
    }) => MaterialApp(
      home: ChatScrollTheme(
        data: const ChatScrollThemeData(),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: 80,
            child: DefaultSelectionChrome(state: stateAt(mode), child: child),
          ),
        ),
      ),
    );

    double dx(WidgetTester tester, String text) {
      final textBox = tester.renderObject<RenderBox>(find.text(text));
      final chrome = tester.renderObject<RenderBox>(
        find.byType(DefaultSelectionChrome),
      );
      return textBox.localToGlobal(Offset.zero).dx -
          chrome.localToGlobal(Offset.zero).dx;
    }

    testWidgets('start-aligned body shifts with the sliding check', (
      tester,
    ) async {
      const child = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 80, height: 20, child: Text('in')),
      );
      await tester.pumpWidget(app(mode: 0, child: child));
      final closed = dx(tester, 'in');
      await tester.pumpWidget(app(mode: 1, child: child));
      expect(dx(tester, 'in') - closed, closeTo(slot, 0.5));
      expect(
        find.byKey(const ValueKey<String>('chatSelectionCheck')),
        findsOneWidget,
      );
    });

    testWidgets('end-aligned body stays on the trailing edge', (tester) async {
      const child = Align(
        alignment: Alignment.centerRight,
        child: SizedBox(width: 80, height: 20, child: Text('out')),
      );
      await tester.pumpWidget(app(mode: 0, child: child));
      final closed = dx(tester, 'out');
      await tester.pumpWidget(app(mode: 1, child: child));
      expect(dx(tester, 'out'), closeTo(closed, 0.5));
    });

    testWidgets('wide end-aligned body is squeezed by the check', (
      tester,
    ) async {
      const child = Align(
        alignment: Alignment.centerRight,
        child: SizedBox(width: 380, height: 20, child: Text('wide')),
      );
      await tester.pumpWidget(app(mode: 0, child: child));
      expect(dx(tester, 'wide'), lessThan(slot));
      await tester.pumpWidget(app(mode: 1, child: child));
      expect(dx(tester, 'wide'), closeTo(slot, 0.5));
    });

    testWidgets('omits check and spacer when the gutter would not fit', (
      tester,
    ) async {
      const child = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 40, height: 20, child: Text('in')),
      );
      await tester.pumpWidget(app(mode: 0, width: 50, child: child));
      final closed = dx(tester, 'in');
      await tester.pumpWidget(app(mode: 1, width: 50, child: child));
      expect(dx(tester, 'in'), closeTo(closed, 0.5));
      expect(
        find.byKey(const ValueKey<String>('chatSelectionCheck')),
        findsNothing,
      );
    });

    testWidgets('selected tint is painted outside the checkbox ClipRect', (
      tester,
    ) async {
      const child = SizedBox(width: 80, height: 20, child: Text('row'));
      await tester.pumpWidget(app(mode: 1, child: child));

      final tintFinder = find.byKey(
        const ValueKey<String>('chatSelectionTint'),
      );
      expect(tintFinder, findsOneWidget);

      // Tint must not be a descendant of ClipRect — that hard-clip was
      // cutting AA edges and opening seams between abutting selected rows.
      expect(
        find.descendant(of: find.byType(ClipRect), matching: tintFinder),
        findsNothing,
      );

      final tint = tester.renderObject<RenderBox>(tintFinder);
      final chrome = tester.renderObject<RenderBox>(
        find.byType(DefaultSelectionChrome),
      );
      expect(tint.size, chrome.size);
      expect(
        tint.localToGlobal(Offset.zero),
        chrome.localToGlobal(Offset.zero),
      );
    });
  });
}
