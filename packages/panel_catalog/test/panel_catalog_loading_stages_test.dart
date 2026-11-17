/// How a cell rises through the loading stages before its content: an
/// outline preview drawn in the media loading style's fill and sweep, and a
/// thumbnail that fades in over the preview it replaces.
///
/// **Seam:** [PanelCatalogViewport] under a [MediaLoadingStyleScope], over a
/// real [ContentAssetScope] and a [FakeAssetProducer] the test plays by hand;
/// what is observed is what the viewport paints into the fake paintables.
library;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/recording_canvas.dart';

const _theme = PanelCatalogThemeData.light;
const _outlineFill = Color(0x33123456);
const _stageFade = Duration(milliseconds: 200);

CatalogLeaf _sticker(int i) => CatalogLeaf.document(
  'sticker-$i',
  semanticKind: SemanticKind.sticker,
  mediaForm: MediaForm.still,
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late FakeAssetProducer producer;
  late PlaybackClock clock;
  late ContentAssetScope scope;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    producer = FakeAssetProducer();
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    scope = ContentAssetScope.withMedia(producer: producer, clock: clock);
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
    scope.dispose();
    clock.dispose();
  });

  Future<void> pump(WidgetTester tester, {OutlineShimmer? shimmer}) {
    snapshots.replaceSections([
      CatalogSection(id: 'a', title: 'A', leaves: [_sticker(0)]),
    ]);
    return tester.pumpWidget(
      MaterialApp(
        home: MediaLoadingStyleScope(
          style: (platform) => platform.copyWith(
            stages: platform.stages.copyWith(
              outlineFill: _outlineFill,
              stageFade: _stageFade,
              outlineShimmer: shimmer,
              clearOutlineShimmer: shimmer == null,
            ),
          ),
          child: PanelCatalogTheme(
            data: _theme,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 480,
                  child: PanelCatalogViewport(
                    snapshots: snapshots,
                    assets: scope,
                    controller: controller,
                    spanCount: 4,
                    cellExtent: 40,
                    headerExtent: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  RenderPanelCatalog render(WidgetTester tester) =>
      tester.renderObject(find.byType(PanelCatalogViewport));

  void paintOnce(WidgetTester tester) => render(
    tester,
  ).paint(TestRecordingPaintingContext(RecordingCanvas()), Offset.zero);

  void describeOutline(FakeAssetAttempt attempt) => attempt.describe(
    MediaDescriptor(
      key: attempt.request.key,
      kind: MediaKind.still,
      preview: const MediaPreview.outline('M0 0h1v1z', MediaDimensions(1, 1)),
    ),
  );

  group('an outline preview', () {
    testWidgets('is drawn in the style\'s outline fill', (tester) async {
      await pump(tester);
      describeOutline(producer.last);
      final preview = producer.last.advance(AssetStage.preview);
      await tester.pump();

      paintOnce(tester);

      expect(
        preview.paints.last.context.outline,
        const OutlineLook(fill: _outlineFill),
      );
    });

    testWidgets('carries the shimmer\'s highlight while playback runs', (
      tester,
    ) async {
      await pump(
        tester,
        shimmer: const OutlineShimmer(sweep: Duration(milliseconds: 1000)),
      );
      describeOutline(producer.last);
      final preview = producer.last.advance(AssetStage.preview);
      await tester.pump();
      render(tester).debugFrameTime = () => const Duration(milliseconds: 250);

      paintOnce(tester);

      expect(preview.paints.last.context.outline?.fill, _outlineFill);
      expect(
        preview.paints.last.context.outline?.highlight,
        closeTo(0.25, 1e-6),
      );
    });

    testWidgets('rests flat while playback is paused', (tester) async {
      await pump(
        tester,
        shimmer: const OutlineShimmer(sweep: Duration(milliseconds: 1000)),
      );
      describeOutline(producer.last);
      final preview = producer.last.advance(AssetStage.preview);
      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: true);
      await tester.pump();
      render(tester).debugFrameTime = () => const Duration(milliseconds: 250);

      paintOnce(tester);

      expect(
        preview.paints.last.context.outline,
        const OutlineLook(fill: _outlineFill),
      );
    });
  });

  group('a thumbnail over the preview', () {
    testWidgets('fades in over the style\'s stage fade, the preview under it', (
      tester,
    ) async {
      await pump(tester);
      var now = const Duration(seconds: 10);
      render(tester).debugFrameTime = () => now;
      final preview = producer.last.advance(AssetStage.preview);
      await tester.pump();
      paintOnce(tester);
      final thumb = producer.last.advance(AssetStage.placeholder);
      await tester.pump();

      paintOnce(tester);
      expect(thumb.paints.last.context.opacity, 0);
      now += _stageFade ~/ 2;
      final under = preview.paints.length;
      paintOnce(tester);
      expect(thumb.paints.last.context.opacity, closeTo(0.5, 1e-6));
      expect(preview.paints, hasLength(under + 1));

      now += _stageFade;
      paintOnce(tester);
      expect(thumb.paints.last.context.opacity, 1);
    });

    testWidgets('a thumbnail with no preview before it shows at once', (
      tester,
    ) async {
      await pump(tester);
      render(tester).debugFrameTime = () => const Duration(seconds: 10);
      final thumb = producer.last.advance(AssetStage.placeholder);
      await tester.pump();

      paintOnce(tester);

      expect(thumb.paints.last.context.opacity, 1);
    });
  });
}
