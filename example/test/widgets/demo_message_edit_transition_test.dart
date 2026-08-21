import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_edit_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget harness({
    required String content,
    required bool edited,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: DemoMessageEditBody(
            content: content,
            createdAt: DateTime.utc(2024, 1, 1, 12),
            edited: edited,
            showStatus: true,
            metaColor: Colors.white70,
            textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.35,
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

  testWidgets('short→long content animates then settles', (tester) async {
    await tester.pumpWidget(harness(content: 'hi', edited: false));
    await tester.pump();
    final shortH = tester.getSize(find.byType(DemoMessageEditBody)).height;

    await tester.pumpWidget(
      harness(
        content: 'this is a much longer message that should wrap lines',
        edited: true,
      ),
    );
    await tester.pump(); // measure frame
    await tester.pump(const Duration(milliseconds: 16)); // start + tick
    // Mid-flight: height should be between short and final.
    await tester.pump(const Duration(milliseconds: 80));
    final midH = tester.getSize(find.byType(DemoMessageEditBody)).height;

    await tester.pumpAndSettle();
    final longH = tester.getSize(find.byType(DemoMessageEditBody)).height;

    expect(longH, greaterThan(shortH));
    expect(midH, greaterThanOrEqualTo(shortH - 0.5));
    expect(midH, lessThanOrEqualTo(longH + 0.5));
    expect(find.text('edited'), findsOneWidget);
    expect(
      find.text('this is a much longer message that should wrap lines'),
      findsOneWidget,
    );
  });

  testWidgets('long→short content animates without throw', (tester) async {
    await tester.pumpWidget(
      harness(
        content: 'this is a much longer message that should wrap lines',
        edited: true,
      ),
    );
    await tester.pumpAndSettle();
    final longH = tester.getSize(find.byType(DemoMessageEditBody)).height;

    await tester.pumpWidget(harness(content: 'ok', edited: true));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    final shortH = tester.getSize(find.byType(DemoMessageEditBody)).height;
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
