/// The status control and badge a host lays over a [ContentEmbed] that a
/// body paints on its canvas.
///
/// **Seam:** [ContentEmbedOverlay] over a real embed on a [ContentAssetScope]
/// and a [FakeAssetProducer] the test plays by hand; observed are the
/// controls it builds and what a tap does to the embed's download.
library;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

const _gif = ContentKey.document('7');
const _size = Size(200, 120);

void main() {
  late FakeAssetProducer producer;
  late PlaybackClock clock;
  late ContentAssetScope scope;
  late ContentEmbed embed;

  setUp(() {
    producer = FakeAssetProducer();
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    scope = ContentAssetScope.withMedia(producer: producer, clock: clock);
    embed = ContentEmbed(
      scope: scope,
      content: _gif,
      preset: AssetPresets.media(
        size: _size,
        devicePixelRatio: 1,
        profile: const AssetProfile(animate: true),
      ),
    );
  });
  tearDown(() {
    embed.dispose();
    scope.dispose();
    clock.dispose();
  });

  Future<void> pump(WidgetTester tester, Widget overlay) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox.fromSize(size: _size, child: overlay),
      ),
    ),
  );

  testWidgets('shows the embed\'s download as the full control and its badge', (
    tester,
  ) async {
    producer.last.transfer(10, 100);
    await pump(tester, ContentEmbedOverlay(embed: embed));

    final control = tester.widget<MediaStatusControl>(
      find.byType(MediaStatusControl),
    );
    expect(control.binding, same(embed.binding));
    expect(control.arcOnly, isFalse);
    expect(
      tester.widget<MediaBadge>(find.byType(MediaBadge)).binding,
      same(embed.binding),
    );
  });

  testWidgets('a tap on the control cancels the download', (tester) async {
    producer.last.transfer(10, 100);
    await pump(tester, ContentEmbedOverlay(embed: embed));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byType(MediaStatusControl));

    expect(producer.attempts.first.isCancelled, isTrue);
  });

  testWidgets('the arc mode is a bare arc, and no badge when asked for none', (
    tester,
  ) async {
    await pump(
      tester,
      ContentEmbedOverlay(
        embed: embed,
        status: const MediaStatusMode.arc(12),
        badge: false,
      ),
    );

    final control = tester.widget<MediaStatusControl>(
      find.byType(MediaStatusControl),
    );
    expect(control.arcOnly, isTrue);
    expect(control.diameter, 24);
    expect(find.byType(MediaBadge), findsNothing);
  });

  testWidgets('no control in the none mode', (tester) async {
    await pump(
      tester,
      ContentEmbedOverlay(embed: embed, status: MediaStatusMode.none),
    );

    expect(find.byType(MediaStatusControl), findsNothing);
    expect(find.byType(MediaBadge), findsOneWidget);
  });
}
