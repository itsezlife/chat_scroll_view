import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget harness({
    required String content,
    required bool edited,
    bool outgoing = false,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: ChatMessageChangeTransition(
            contentIdentity: content,
            content: Text(
              content,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            edited: edited,
            outgoing: outgoing,
            color: const Color(0xFF2B5278),
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            metaBuilder: (context, editedOpacity) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reserve edited width at opacity 0.
                if (edited) ...[
                  Opacity(
                    opacity: editedOpacity.clamp(0.0, 1.0),
                    child: const Text(
                      'edited',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                const Text(
                  '12:00',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('settled edit shows edited label', (tester) async {
    await tester.pumpWidget(harness(content: 'hello', edited: true));
    await tester.pump();
    expect(find.text('edited'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('short→long settled size is final; host tracks painted', (
    tester,
  ) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble';

    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pump();
    final shortH = tester.getSize(find.byType(ChatMessageChangeTransition)).height;

    await tester.pumpWidget(harness(content: long, edited: true));
    await tester.pump(); // begin + measure frame
    await tester.pump(); // apply begin params

    final ro = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final midHost = ro.size;
    final midSettled = ro.finalBackgroundRect;
    final midPainted = ro.lastPaintedBackground;

    await tester.pumpAndSettle();
    final settled = tester.getSize(find.byType(ChatMessageChangeTransition));

    // Content measure is already final; host/paint morph from the old size.
    expect(midSettled.height, closeTo(settled.height, 1.0));
    expect(settled.height, greaterThan(shortH));
    expect(midHost.height, closeTo(midPainted.height, 2.0));
    expect(midHost.height, lessThan(settled.height - 4));
    expect(find.text('edited'), findsOneWidget);
    expect(find.text(long), findsWidgets);
  });

  testWidgets('painted background height lerps during short→long', (
    tester,
  ) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble';

    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pump();
    final shortRo = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    // Force a paint so lastPaintedBackground is set.
    shortRo.markNeedsPaint();
    await tester.pump();
    final shortBgH = shortRo.lastPaintedBackground.height;

    await tester.pumpWidget(harness(content: long, edited: true));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final ro = tester.renderObject<RenderChatMessageChangeTransition>(
      find.byType(ChatMessageChangeTransition),
    );
    final midBgH = ro.lastPaintedBackground.height;

    await tester.pumpAndSettle();
    final endBgH = ro.lastPaintedBackground.height;

    expect(endBgH, greaterThan(shortBgH));
    expect(midBgH, greaterThanOrEqualTo(shortBgH - 0.5));
    expect(midBgH, lessThanOrEqualTo(endBgH + 0.5));
  });

  testWidgets('long→short animates without throw', (tester) async {
    const long =
        'this is a much longer message that should wrap lines across the bubble';

    await tester.pumpWidget(harness(content: long, edited: true));
    await tester.pumpAndSettle();
    final longH = tester.getSize(find.byType(ChatMessageChangeTransition)).height;

    await tester.pumpWidget(harness(content: 'ok', edited: true));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    final shortH = tester.getSize(find.byType(ChatMessageChangeTransition)).height;
    expect(shortH, lessThan(longH));
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('rapid re-edit cancels prior animation cleanly', (tester) async {
    await tester.pumpWidget(harness(content: 'a', edited: false));
    await tester.pump();

    await tester.pumpWidget(harness(content: 'bbbbbbbbbb', edited: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    await tester.pumpWidget(harness(content: 'c', edited: true));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('c'), findsOneWidget);
    expect(find.text('edited'), findsOneWidget);
  });
}
