import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/streaming/streaming_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Send streams a reply into a row, then settles it', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<StreamingScreenState>();
    await tester.pumpWidget(MaterialApp(home: StreamingScreen(key: key)));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('streaming-send')));
    await tester.pump(const Duration(milliseconds: 200));
    final state = key.currentState!;
    final live = state.body!;
    expect(find.byType(ChatStreamingBody), findsOneWidget);
    expect(live.value.markdown, isNotEmpty);
    expect(live.value.markdown.length, lessThan(streamingDemoReply.length));

    for (var i = 0; i < 200 && state.busy; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(live.isSettled, isTrue);
    expect(live.value.markdown, streamingDemoReply);
    expect(state.selection.bodyOf(state.liveId!)?.markdown, streamingDemoReply);
  });

  testWidgets('plain toggle streams literally with the [Nn] hook', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<StreamingScreenState>();
    await tester.pumpWidget(MaterialApp(home: StreamingScreen(key: key)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('streaming-plain')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('streaming-send')));
    final state = key.currentState!;
    for (var i = 0; i < 300 && (state.busy || i < 2); i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));
    final block = state.body!.value.blocks.first as MD$Paragraph;
    expect(block.spans.single.text, startsWith('# not a heading'));
    final marks = state.body!.value.blocks
        .whereType<MD$Paragraph>()
        .expand((p) => p.spans)
        .where((s) => s.style == MD$Style.chip)
        .map((s) => s.text);
    expect(marks, ['[N1]', '[N12]']);
  });
}
