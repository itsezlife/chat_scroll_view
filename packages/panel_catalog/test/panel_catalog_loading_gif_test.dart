/// What a GIF cell shows while its clip loads, and how a thumbnail hands over
/// to the clip.
///
/// **Seam:** [PanelCatalogViewport] over a real [AssetCacheScope] and a
/// [FakeAssetProducer] the test plays by hand; what is observed is what the
/// viewport asks a recording canvas to draw and what it paints into the fake
/// paintables, never render-object fields. The reference client draws a GIF
/// that is loading as its blurred thumbnail with a turning arc in a dark disc
/// over it, and keeps a bitmap thumbnail opaque under the content that fades
/// in (`ImageReceiver.draw`).
library;

import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/recording_canvas.dart';

const _theme = PanelCatalogThemeData.light;
const _fade = Duration(milliseconds: 150);

// 4 columns of 80 x 40 cells under a 24 px header: cell 0 is centred at
// (40, 44) and a GIF fills its cell.
const _centre = Offset(40, 44);

CatalogLeaf _gif(int i) => CatalogLeaf.document(
  'gif-$i',
  semanticKind: SemanticKind.gif,
  mediaForm: MediaForm.video,
  animated: true,
);

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
  late AssetCacheScope scope;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    producer = FakeAssetProducer();
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    scope = AssetCacheScope(producer: producer, clock: clock);
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
    scope.dispose();
    clock.dispose();
  });

  Future<void> pump(WidgetTester tester, List<CatalogLeaf> leaves) {
    snapshots.replaceSections([
      CatalogSection(id: 'a', title: 'A', leaves: leaves),
    ]);
    return tester.pumpWidget(
      MaterialApp(
        home: PanelCatalogTheme(
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
    );
  }

  RenderPanelCatalog render(WidgetTester tester) =>
      tester.renderObject(find.byType(PanelCatalogViewport));

  RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = RecordingCanvas();
    render(tester).paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  Iterable<DrawnCircle> discs(RecordingCanvas canvas) =>
      canvas.circles.where((c) => c.radius == 12);

  group('a GIF whose clip has not arrived', () {
    testWidgets('is the quiet silhouette with the radial progress over it', (
      tester,
    ) async {
      await pump(tester, [_gif(0)]);

      final canvas = paintOnce(tester);

      expect(canvas.rrects, hasLength(1));
      expect(
        canvas.rrects.single.color.toARGB32(),
        _theme.thumbColor.toARGB32(),
      );
      final disc = discs(canvas).single;
      expect(disc.center, _centre);
      expect(disc.color.toARGB32(), 0x66000000);
      final arc = canvas.arcs.single;
      expect(arc.rect, Rect.fromCircle(center: _centre, radius: 8));
    });

    testWidgets('a thumbnail fills the cell, a sticker\'s stays whole', (
      tester,
    ) async {
      await pump(tester, [_gif(0), _sticker(1)]);

      final gif = producer.attempts.first.advance(AssetStage.placeholder);
      final sticker = producer.attempts.last.advance(AssetStage.placeholder);
      await tester.pump();
      paintOnce(tester);

      expect(gif.paints.last.context.fit, AssetFit.cover);
      expect(sticker.paints.last.context.fit, AssetFit.contain);
    });

    testWidgets('with a thumbnail, draws the thumbnail under the progress', (
      tester,
    ) async {
      await pump(tester, [_gif(0)]);

      final thumb = producer.last.advance(AssetStage.placeholder);
      await tester.pump();
      final canvas = paintOnce(tester);

      expect(thumb.paints.last.context.opacity, 1);
      expect(canvas.rrects, isEmpty);
      expect(discs(canvas), hasLength(1));
      expect(canvas.arcs, hasLength(1));
    });

    testWidgets('the arc turns with the frame time of the pass', (
      tester,
    ) async {
      await pump(tester, [_gif(0)]);
      var now = const Duration(seconds: 10);
      render(tester).debugFrameTime = () => now;

      final first = paintOnce(tester).arcs.single.start;
      now += const Duration(milliseconds: 625);
      final quarter = paintOnce(tester).arcs.single.start;

      expect(quarter - first, closeTo(math.pi / 2, 1e-6));
    });

    testWidgets('keeps frames coming, and stops while playback is paused', (
      tester,
    ) async {
      await pump(tester, [_gif(0)]);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);

      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: true);
      render(tester).markNeedsPaint();
      await tester.pump();
      await tester.pump();

      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(paintOnce(tester).arcs.single.start, 0);
    });

    testWidgets('a sticker and a custom emoji get no progress', (tester) async {
      await pump(tester, [
        _sticker(0),
        CatalogLeaf.document(
          'emoji-1',
          semanticKind: SemanticKind.customEmoji,
          mediaForm: MediaForm.still,
        ),
      ]);

      final canvas = paintOnce(tester);

      expect(canvas.arcs, isEmpty);
      expect(discs(canvas), isEmpty);
    });
  });

  group('the clip arrives over its thumbnail', () {
    testWidgets('the thumbnail stays opaque until the clip is, then goes', (
      tester,
    ) async {
      await pump(tester, [_gif(0)]);
      var now = const Duration(seconds: 10);
      render(tester).debugFrameTime = () => now;
      final thumb = producer.last.advance(AssetStage.placeholder);
      await tester.pump();
      final content = producer.last.advance(AssetStage.firstFrame);
      await tester.pump();

      paintOnce(tester);
      final before = thumb.paints.length;
      expect(content.paints.last.context.opacity, 0);

      now += _fade ~/ 2;
      paintOnce(tester);
      expect(content.paints.last.context.opacity, closeTo(0.5, 1e-6));
      expect(thumb.paints, hasLength(before + 1));
      expect(thumb.paints.last.context.opacity, 1);
      expect(thumb.isDisposed, isFalse);

      now += _fade;
      final done = paintOnce(tester);
      expect(content.paints.last.context.opacity, 1);
      expect(thumb.paints, hasLength(before + 1));
      expect(thumb.isDisposed, isTrue);
      expect(done.arcs, isEmpty);
    });

    testWidgets('the progress fades out with the fade, not before', (
      tester,
    ) async {
      await pump(tester, [_gif(0)]);
      var now = const Duration(seconds: 10);
      render(tester).debugFrameTime = () => now;
      producer.last.advance(AssetStage.placeholder);
      await tester.pump();
      producer.last.advance(AssetStage.firstFrame);
      await tester.pump();

      final start = paintOnce(tester);
      now += _fade ~/ 2;
      final middle = paintOnce(tester);

      expect(discs(start).single.color.a, closeTo(0x66 / 255, 0.01));
      expect(discs(middle).single.color.a, closeTo(0x66 / 255 * 0.5, 0.01));
    });
  });
}
