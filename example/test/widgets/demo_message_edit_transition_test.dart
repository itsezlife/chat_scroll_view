import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _meta({required bool edited, required double editedOpacity}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: DemoMessageMeta(
            createdAt: DateTime.utc(2024, 1, 1, 12),
            color: Colors.white70,
            showStatus: true,
            edited: edited,
            editedOpacity: editedOpacity,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DemoMessageMeta shows edited when opacity > 0', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_meta(edited: true, editedOpacity: 1));
    final time = DemoMessageMeta.formatTime(DateTime.utc(2024, 1, 1, 12));
    expect(find.bySemanticsLabel('edited $time'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('DemoMessageMeta reserves edited width at opacity 0', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_meta(edited: true, editedOpacity: 1));
    final shown = tester.getSize(find.byType(DemoMessageMeta));

    await tester.pumpWidget(_meta(edited: true, editedOpacity: 0));
    // Width stays reserved while the label fades; unseen, it is not read.
    expect(tester.getSize(find.byType(DemoMessageMeta)), shown);
    final time = DemoMessageMeta.formatTime(DateTime.utc(2024, 1, 1, 12));
    expect(find.bySemanticsLabel(time), findsOneWidget);

    await tester.pumpWidget(_meta(edited: false, editedOpacity: 0));
    expect(
      tester.getSize(find.byType(DemoMessageMeta)).width,
      lessThan(shown.width),
    );
    semantics.dispose();
  });
}
