import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const maxWidth = 280.0;
  const spacing = 4.0;
  const textStyle = TextStyle(fontSize: 16, height: 1);

  /// Loose max-width only — shrink-wrap needs `minWidth == 0`.
  Widget harness({required Widget body, double width = maxWidth}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: body,
          ),
        ),
      );

  Size sizeOf(WidgetTester tester, Finder finder) => tester.getSize(finder);

  Offset offsetOf(WidgetTester tester, Key key) {
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    final parentData = box.parentData! as BoxParentData;
    return parentData.offset;
  }

  group('ChatMessageBody', () {
    testWidgets('short single line packs meta inline and shrink-wraps width', (
      tester,
    ) async {
      const contentKey = ValueKey('content');
      const metaKey = ValueKey('meta');

      await tester.pumpWidget(
        harness(
          body: const ChatMessageBody(
            spacing: spacing,
            content: Text('Hi', key: contentKey, style: textStyle),
            meta: SizedBox(key: metaKey, width: 40, height: 12),
          ),
        ),
      );

      final bodySize = sizeOf(tester, find.byType(ChatMessageBody));
      final contentSize = sizeOf(tester, find.byKey(contentKey));
      final metaSize = sizeOf(tester, find.byKey(metaKey));

      expect(bodySize.height, contentSize.height);
      expect(bodySize.width, lessThan(maxWidth));
      expect(
        bodySize.width,
        closeTo(contentSize.width + spacing + metaSize.width, 1.0),
      );

      final metaOffset = offsetOf(tester, metaKey);
      expect(metaOffset.dy, closeTo(bodySize.height - metaSize.height, 0.5));
      expect(metaOffset.dx, closeTo(bodySize.width - metaSize.width, 0.5));
    });

    testWidgets('long last line wraps meta onto the next row', (tester) async {
      const contentKey = ValueKey('content');
      const metaKey = ValueKey('meta');

      // Non-text content falls back to full width as last-line width, so a
      // near-full-width body plus meta must wrap.
      await tester.pumpWidget(
        harness(
          body: const ChatMessageBody(
            spacing: spacing,
            content: SizedBox(key: contentKey, width: 250, height: 40),
            meta: SizedBox(key: metaKey, width: 72, height: 14),
          ),
        ),
      );

      final bodySize = sizeOf(tester, find.byType(ChatMessageBody));
      final contentSize = sizeOf(tester, find.byKey(contentKey));
      final metaSize = sizeOf(tester, find.byKey(metaKey));

      expect(bodySize.height, contentSize.height + metaSize.height);
      expect(bodySize.width, lessThanOrEqualTo(maxWidth));

      final metaOffset = offsetOf(tester, metaKey);
      expect(metaOffset.dy, closeTo(contentSize.height, 0.5));
      expect(metaOffset.dx, closeTo(bodySize.width - metaSize.width, 0.5));
    });

    testWidgets('multi-line with short last line keeps meta inline', (
      tester,
    ) async {
      const contentKey = ValueKey('content');
      const metaKey = ValueKey('meta');

      await tester.pumpWidget(
        harness(
          body: const ChatMessageBody(
            spacing: spacing,
            content: Text(
              'First line that wraps across the bubble width nicely\nOk',
              key: contentKey,
              style: textStyle,
            ),
            meta: SizedBox(key: metaKey, width: 40, height: 12),
          ),
        ),
      );

      final bodySize = sizeOf(tester, find.byType(ChatMessageBody));
      final contentSize = sizeOf(tester, find.byKey(contentKey));

      expect(bodySize.height, contentSize.height);
      expect(offsetOf(tester, metaKey).dy, lessThan(contentSize.height));
    });

    testWidgets('padding insets content and meta', (tester) async {
      const contentKey = ValueKey('content');
      const metaKey = ValueKey('meta');
      const padding = EdgeInsets.fromLTRB(8, 4, 10, 6);

      await tester.pumpWidget(
        harness(
          body: const ChatMessageBody(
            spacing: spacing,
            padding: padding,
            content: Text('Hi', key: contentKey, style: textStyle),
            meta: SizedBox(key: metaKey, width: 40, height: 12),
          ),
        ),
      );

      expect(offsetOf(tester, contentKey), const Offset(8, 4));
      final bodySize = sizeOf(tester, find.byType(ChatMessageBody));
      final metaSize = sizeOf(tester, find.byKey(metaKey));
      expect(
        offsetOf(tester, metaKey).dx,
        closeTo(bodySize.width - padding.right - metaSize.width, 0.5),
      );
    });

    testWidgets('meta-only sizes to meta plus padding', (tester) async {
      const metaKey = ValueKey('meta');
      const padding = EdgeInsets.all(5);

      await tester.pumpWidget(
        harness(
          body: const ChatMessageBody(
            padding: padding,
            meta: SizedBox(key: metaKey, width: 50, height: 16),
          ),
        ),
      );

      expect(sizeOf(tester, find.byType(ChatMessageBody)), const Size(60, 26));
      expect(offsetOf(tester, metaKey), const Offset(5, 5));
    });

    testWidgets('hit-test reaches meta and content', (tester) async {
      var contentTaps = 0;
      var metaTaps = 0;

      await tester.pumpWidget(
        harness(
          body: ChatMessageBody(
            spacing: spacing,
            content: GestureDetector(
              onTap: () => contentTaps++,
              child: const SizedBox(
                width: 80,
                height: 40,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ),
            meta: GestureDetector(
              onTap: () => metaTaps++,
              child: const SizedBox(
                width: 30,
                height: 12,
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
            ),
          ),
        ),
      );

      final bodyBox = tester.renderObject<RenderBox>(
        find.byType(ChatMessageBody),
      );
      final bodyTopLeft = tester.getTopLeft(find.byType(ChatMessageBody));

      // Meta sits bottom-right when short content packs inline.
      await tester.tapAt(
        bodyTopLeft + Offset(bodyBox.size.width - 5, bodyBox.size.height - 5),
      );
      expect(metaTaps, 1);

      await tester.tapAt(bodyTopLeft + const Offset(10, 10));
      expect(contentTaps, 1);
    });
  });
}
