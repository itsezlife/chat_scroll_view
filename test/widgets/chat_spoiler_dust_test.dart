import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

// A host's own markdown outside the viewport (a chat list preview) moves its
// dust on the same clock as the bubbles, through the public ChatSpoilerDust.
void main() {
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late MarkdownSpoilerController spoilers;

  setUp(() {
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    spoilers = MarkdownSpoilerController();
  });
  tearDown(() {
    spoilers.dispose();
    clock.dispose();
  });

  Future<void> pumpBody(WidgetTester tester, {required bool mounted}) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: mounted
          ? MarkdownWidget(
              markdown: Markdown.fromString('x ||secret|| y'),
              documentId: 'preview',
              spoilerController: spoilers,
            )
          : const SizedBox.shrink(),
    ),
  );

  testWidgets('follows the clock only while a hidden spoiler is mounted', (tester) async {
    final dust = ChatSpoilerDust(spoilers: spoilers, clock: clock);
    addTearDown(dust.dispose);
    expect(ticks.isRunning, isFalse);

    await pumpBody(tester, mounted: true);
    expect(ticks.isRunning, isTrue);
    ticks.tick(const Duration(seconds: 1));
    expect(spoilers.fillFrame, 30);

    await pumpBody(tester, mounted: false);
    expect(ticks.isRunning, isFalse);
  });

  testWidgets('dispose gives the clock back', (tester) async {
    final dust = ChatSpoilerDust(spoilers: spoilers, clock: clock);
    await pumpBody(tester, mounted: true);
    expect(ticks.isRunning, isTrue);

    dust.dispose();

    expect(ticks.isRunning, isFalse);
  });
}
