import 'package:chat_scroll_view_example/src/common/frame_rate_boost.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('chat_scroll_view_example/frame_rate');
  late List<String> votes;

  setUp(() {
    votes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          votes.add(call.method);
          return null;
        });
    FrameRateBoost.debugInstall();
  });

  tearDown(() {
    FrameRateBoost.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('votes high while animating and withdraws once quiet', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(votes, isEmpty);

    // An animation no finger started.
    await tester.pumpWidget(
      const Center(child: CircularProgressIndicator(value: null)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(votes, ['high']);

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Still animating: one vote, not one per frame.
    expect(votes, ['high']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 700));
    expect(votes, ['high', 'default']);
  });

  testWidgets('a still app votes nothing', (tester) async {
    await tester.pumpWidget(const Center(child: SizedBox.square(dimension: 8)));
    await tester.pump(const Duration(seconds: 1));
    expect(votes, isEmpty);
  });
}
