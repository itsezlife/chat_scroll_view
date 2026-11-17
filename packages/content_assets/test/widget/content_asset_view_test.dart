/// What [ContentAssetView] hands the media core's view.
///
/// **Seam:** the [ContentView] it builds for media, over a
/// [ContentAssetScope] with a [FakeAssetProducer].
library;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

const _clip = ContentKey.document('clip-1');
const _context = AutoDownloadContext('channels');

final _preset = AssetPresets.square(
  extent: 100,
  devicePixelRatio: 1,
  profile: const AssetProfile(animate: true),
);

void main() {
  late FakeAssetProducer producer;
  late ContentAssetScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    scope = ContentAssetScope.withMedia(producer: producer);
    addTearDown(scope.dispose);
  });

  Future<void> pump(WidgetTester tester, ContentAssetView view) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: view),
        ),
      );

  testWidgets('forwards the status, badge, play, placeholder rank, download '
      'context and underlay', (tester) async {
    void play() {}
    const placeholder = SoftPlaceholder();
    await pump(
      tester,
      ContentAssetView(
        content: _clip,
        preset: _preset,
        scope: scope,
        status: const MediaStatusMode.control(playAction: true),
        badge: true,
        onPlay: play,
        placeholder: placeholder,
        placeholderUntil: AssetStage.firstFrame,
        downloadContext: _context,
        underlay: const Color(0xFF336699),
      ),
    );

    final view = tester.widget<ContentView>(find.byType(ContentView));
    expect(view.content, _clip.mediaKey);
    expect(view.scope, same(scope.media));
    expect(view.status, const MediaStatusMode.control(playAction: true));
    expect(view.badge, isTrue);
    expect(view.onPlay, same(play));
    expect(view.placeholder, same(placeholder));
    expect(view.placeholderUntil, AssetStage.firstFrame);
    expect(view.downloadContext, _context);
    expect(view.underlay, const Color(0xFF336699));
  });

  testWidgets('keeps the core view\'s defaults: no control, no badge, no tag', (
    tester,
  ) async {
    await pump(
      tester,
      ContentAssetView(content: _clip, preset: _preset, scope: scope),
    );

    final view = tester.widget<ContentView>(find.byType(ContentView));
    expect(view.status, MediaStatusMode.none);
    expect(view.badge, isFalse);
    expect(view.onPlay, isNull);
    expect(view.placeholderUntil, AssetStage.none);
    expect(view.downloadContext, isNull);
    expect(view.underlay, isNull);
  });

  testWidgets('the download context reaches the media scope\'s demand', (
    tester,
  ) async {
    await pump(
      tester,
      ContentAssetView(
        content: _clip,
        preset: _preset,
        scope: scope,
        downloadContext: _context,
      ),
    );

    expect(producer.last.demand.downloadContexts, contains(_context));
  });

  testWidgets('an arc shows over the content while it downloads', (
    tester,
  ) async {
    await pump(
      tester,
      ContentAssetView(
        content: _clip,
        preset: _preset,
        scope: scope,
        status: const MediaStatusMode.arc(12),
      ),
    );

    producer.last.transfer(40, 100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(MediaStatusControl), findsOneWidget);
    expect(
      tester.renderObject(find.byType(ContentAssetView)),
      paints..circle(radius: 12),
    );
  });

  testWidgets('a glyph builds no media view, whatever the status asked', (
    tester,
  ) async {
    await pump(
      tester,
      ContentAssetView(
        content: const ContentKey.unicode('\u{1F44D}'),
        preset: _preset,
        scope: scope,
        status: const MediaStatusMode.arc(12),
        badge: true,
        downloadContext: _context,
      ),
    );

    expect(find.byType(ContentView), findsNothing);
    expect(find.byType(MediaStatusControl), findsNothing);
  });
}
