import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DemoMessageMeta shows edited when opacity > 0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DemoMessageMeta(
            createdAt: DateTime.utc(2024, 1, 1, 12),
            color: Colors.white70,
            showStatus: true,
            edited: true,
            editedOpacity: 1,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('edited'), findsOneWidget);
    expect(find.textContaining(':'), findsOneWidget);
  });

  testWidgets('DemoMessageMeta reserves edited width at opacity 0', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DemoMessageMeta(
            createdAt: DateTime.utc(2024, 1, 1, 12),
            color: Colors.white70,
            showStatus: false,
            edited: true,
            editedOpacity: 0,
          ),
        ),
      ),
    );
    await tester.pump();
    // Still in the tree — Opacity handles the fade while width stays reserved.
    expect(find.text('edited'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('edited'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 0);
  });
}
