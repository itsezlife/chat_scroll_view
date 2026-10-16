/// How the Panel Catalog Viewport uses the host's asset cache: what it asks of
/// it for each visible leaf, what it paints at each stage, and what it does
/// when content never arrives.
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource] and
/// a real [AssetCacheScope] over a [FakeAssetProducer], so a test plays the
/// producer by hand (answer at once, answer later, hang, fail). What is observed
/// is the requests the producer receives and what the viewport asks its canvas
/// to draw (a recording canvas passed to `paint`), never render-object fields.
/// The baked-glyph path is pinned in `panel_catalog_baked_sprites_test.dart`.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/panel_catalog_diagnostics.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/recording_canvas.dart';

// Geometry: 4 columns of 80 x 40 cells under a 24 px header in a 480 px
// viewport, so the glyph box is 28.8 and the first row starts at 24. Rows 0..11
// are in view; row 12 starts at 504 and is in the one-cell overscan.
const _span = 4;
const _theme = PanelCatalogThemeData.light;

// The documented fade of content that was not there at attach.
const _fade = Duration(milliseconds: 150);

CatalogLeaf _doc(int i, {bool animated = false, bool tintable = false}) =>
    CatalogLeaf.document(
      'doc-$i',
      semanticKind: SemanticKind.customEmoji,
      mediaForm: MediaForm.still,
      animated: animated,
      tintable: tintable,
    );

CatalogLeaf _sticker(int i) => CatalogLeaf.document(
  'sticker-$i',
  semanticKind: SemanticKind.sticker,
  mediaForm: MediaForm.still,
);

CatalogSection _section(List<CatalogLeaf> leaves) =>
    CatalogSection(id: 'a', title: 'A', leaves: leaves);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late FakeAssetProducer producer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late AssetCacheScope scope;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    producer = FakeAssetProducer();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    scope = AssetCacheScope(producer: producer, clock: clock);
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
    scope.dispose();
    clock.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester, {
    AssetCacheScope? assets,
    double? devicePixelRatio,
  }) {
    if (devicePixelRatio != null) {
      tester.view.devicePixelRatio = devicePixelRatio;
      addTearDown(tester.view.resetDevicePixelRatio);
    }
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
                  assets: assets ?? scope,
                  controller: controller,
                  spanCount: _span,
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

  AssetRequest requestOf(CatalogLeaf leaf) => producer.attempts
      .firstWhere((attempt) => attempt.request.key == leaf.key)
      .request;

  group('what a leaf asks of the cache', () {
    testWidgets('its glyph box in physical pixels at the view density', (
      tester,
    ) async {
      final leaf = _doc(0);
      snapshots.replaceSections([
        _section([leaf]),
      ]);
      await pumpViewport(tester, devicePixelRatio: 2);

      final spec = requestOf(leaf).spec;

      // 0.72 of the 40 px cell is 28.8 logical px, 57.6 physical, rounded up.
      expect((spec.pixelWidth, spec.pixelHeight), (58, 58));
      expect(spec.decodeMode, AssetDecodeMode.original);
      expect(spec.variant, AssetVariant.full);
    });

    testWidgets('the template decode for a tintable leaf', (tester) async {
      final leaf = _doc(0, tintable: true);
      snapshots.replaceSections([
        _section([leaf]),
      ]);
      await pumpViewport(tester);

      expect(requestOf(leaf).spec.decodeMode, AssetDecodeMode.template);
    });

    testWidgets(
      'a change of density swaps the attach for one at the new size',
      (tester) async {
        final leaf = _doc(0);
        snapshots.replaceSections([
          _section([leaf]),
        ]);
        await pumpViewport(tester, devicePixelRatio: 2);
        expect(producer.attempts, hasLength(1));

        tester.view.devicePixelRatio = 3;
        await tester.pump();

        expect(producer.attempts, hasLength(2));
        expect(producer.attempts.first.isCancelled, isTrue);
        expect(producer.attempts.last.request.spec.pixelWidth, 87);
      },
    );

    testWidgets('far bindings detach and give their attempt back', (
      tester,
    ) async {
      final leaves = [for (var i = 0; i < 400; i++) _doc(i)];
      snapshots.replaceSections([_section(leaves)]);
      await pumpViewport(tester);
      final first = producer.attemptsFor(requestOf(leaves.first)).single;
      expect(first.isCancelled, isFalse);

      controller.jumpTo(5000);
      await tester.pump();

      expect(first.isCancelled, isTrue);
      expect(scope.isAttached(leaves.first.key, first.request.spec), isFalse);
      expect(render(tester).attachedLeafCount, lessThan(80));
    });

    testWidgets('leaves in the overscan load below the ones in view', (
      tester,
    ) async {
      final leaves = [for (var i = 0; i < 80; i++) _doc(i)];
      snapshots.replaceSections([_section(leaves)]);
      await pumpViewport(tester);

      final inView = producer.attemptsFor(requestOf(leaves[0])).single;
      final overscan = producer.attemptsFor(requestOf(leaves[48])).single;

      expect(inView.demand.priority, AssetPriority.visible);
      expect(overscan.demand.priority, AssetPriority.preload);
    });

    testWidgets('an animated leaf plays only while no fling runs', (
      tester,
    ) async {
      producer.onProduce = (attempt) =>
          attempt.advance(AssetStage.full, animated: true);
      final leaves = [for (var i = 0; i < 400; i++) _doc(i, animated: true)];
      snapshots.replaceSections([_section(leaves)]);
      await pumpViewport(tester);
      expect(ticks.isRunning, isTrue);

      await tester.fling(
        find.byType(PanelCatalogViewport),
        const Offset(0, -300),
        2000,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(render(tester).isFlinging, isTrue);
      expect(ticks.isRunning, isFalse);

      await tester.pumpAndSettle();
      expect(render(tester).isFlinging, isFalse);
      expect(ticks.isRunning, isTrue);
    });
  });

  group('the box a leaf is asked for and drawn in', () {
    testWidgets('a sticker fills its cell, an emoji the glyph box', (
      tester,
    ) async {
      final emoji = _doc(0);
      final sticker = _sticker(1);
      snapshots.replaceSections([
        _section([emoji, sticker]),
      ]);
      await pumpViewport(tester, devicePixelRatio: 2);

      // 40 px is the cell's shorter side; 0.72 of it is 28.8.
      expect(requestOf(emoji).spec.pixelWidth, 58);
      expect(requestOf(sticker).spec.pixelWidth, 80);
      final drawn = paintOnce(tester).rrects.map((r) => r.rrect.width);
      expect(drawn, [closeTo(28.8, 1e-9), closeTo(40, 1e-9)]);
    });

    testWidgets('a section overrides the box and the placeholder style', (
      tester,
    ) async {
      final sticker = _sticker(1);
      snapshots.replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [sticker],
          contentBox: CatalogContentBox.glyph,
          placeholderStyle: CatalogPlaceholderStyle.circle,
        ),
      ]);
      await pumpViewport(tester, devicePixelRatio: 2);

      expect(requestOf(sticker).spec.pixelWidth, 58);
      final canvas = paintOnce(tester);
      expect(canvas.rrects, isEmpty);
      expect(canvas.circles.single.radius, closeTo(28.8 * 0.4, 1e-9));
    });
  });

  group('a leaf whose content has not arrived', () {
    testWidgets('keeps the thumb-first silhouette while the load hangs', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section([_doc(0)]),
      ]);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      expect(canvas.rrects, hasLength(1));
      expect(
        canvas.rrects.single.color.toARGB32(),
        _theme.thumbColor.toARGB32(),
      );
      expect(canvas.rrects.single.rrect.width, closeTo(28.8, 1e-9));
      expect(canvas.circles, isEmpty);
    });

    testWidgets('keeps its placeholder when the load fails', (tester) async {
      snapshots.replaceSections([
        _section([_doc(0), _sticker(1)]),
      ]);
      await pumpViewport(tester);

      for (final attempt in producer.attempts) {
        attempt.fail(StateError('offline'));
      }
      await tester.pump();
      final canvas = paintOnce(tester);

      // No failed stand-in: the same silhouette and the same sweeping wash as
      // before.
      expect(canvas.rrects, hasLength(2));
      expect(
        canvas.rrects.first.color.toARGB32(),
        _theme.thumbColor.toARGB32(),
      );
      expect(canvas.rrects.last.shader, isNotNull);
    });

    testWidgets('a sticker is a wash that sweeps while playback runs', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section([_sticker(0)]),
      ]);
      await pumpViewport(tester);

      final moving = paintOnce(tester).rrects.single;
      expect(moving.shader, isNotNull);
      // A paint's alpha multiplies its shader's: the colours are in the
      // gradient, so the paint itself must be opaque or the wash vanishes.
      expect(moving.color.a, 1);

      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: true);
      final paused = paintOnce(tester).rrects.single;
      expect(paused.shader, isNull);
      expect(paused.color.toARGB32(), _theme.washColor.toARGB32());
    });

    testWidgets('the wash keeps frames coming, a still catalogue does not', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section([_sticker(0)]),
      ]);
      await pumpViewport(tester);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);

      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: true);
      render(tester).markNeedsPaint();
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('an unbaked unicode leaf is the circle, never text', (
      tester,
    ) async {
      PanelCatalogDiagnostics.reset();
      snapshots.replaceSections([
        _section([CatalogLeaf.unicode('😀')]),
      ]);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      expect(canvas.circles, hasLength(1));
      expect(
        canvas.circles.single.color.toARGB32(),
        _theme.circleColor.toARGB32(),
      );
      expect(canvas.circles.single.radius, closeTo(28.8 * 0.4, 1e-9));
      expect(PanelCatalogDiagnostics.glyphParagraphDraws, 0);
    });
  });

  group('content that has arrived', () {
    testWidgets('a memory hit paints at once, with no placeholder or fade', (
      tester,
    ) async {
      late FakeAssetPaintable paintable;
      producer.onProduce = (attempt) =>
          paintable = attempt.advance(AssetStage.full);
      snapshots.replaceSections([
        _section([_doc(0)]),
      ]);
      await pumpViewport(tester);

      final canvas = paintOnce(tester);

      expect(canvas.rrects, isEmpty);
      expect(paintable.paints.last.context.opacity, 1);
      expect(paintable.paints.last.rect.width, closeTo(28.8, 1e-9));
      await tester.pumpAndSettle();
    });

    testWidgets('content that was not there fades in over the placeholder', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section([_doc(0)]),
      ]);
      await pumpViewport(tester);
      var now = const Duration(seconds: 10);
      render(tester).debugFrameTime = () => now;

      final paintable = producer.last.advance(AssetStage.full);
      await tester.pump();
      final start = paintOnce(tester);
      expect(paintable.paints.last.context.opacity, 0);
      expect(start.rrects.single.color.a, closeTo(_theme.thumbColor.a, 1e-3));

      now += _fade ~/ 2;
      final middle = paintOnce(tester);
      expect(paintable.paints.last.context.opacity, closeTo(0.5, 1e-6));
      expect(
        middle.rrects.single.color.a,
        closeTo(_theme.thumbColor.a * 0.5, 1e-3),
      );

      now += _fade;
      final done = paintOnce(tester);
      expect(paintable.paints.last.context.opacity, 1);
      expect(done.rrects, isEmpty);
    });

    testWidgets('the fade stops asking for frames when it is done', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section([_doc(0)]),
      ]);
      await pumpViewport(tester);

      final paintable = producer.last.advance(AssetStage.full);
      // pumpAndSettle fails if frames never stop.
      await tester.pumpAndSettle(const Duration(milliseconds: 16));

      expect(paintable.paints.last.context.opacity, 1);
    });

    testWidgets('a stand-in paintable is drawn as it is, not faded', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section([_doc(0)]),
      ]);
      await pumpViewport(tester);

      final thumb = producer.last.advance(AssetStage.placeholder);
      await tester.pump();
      final canvas = paintOnce(tester);

      expect(thumb.paints.last.context.opacity, 1);
      expect(canvas.rrects, isEmpty);
    });

    testWidgets('content already cached paints at once on re-attach', (
      tester,
    ) async {
      snapshots.replaceSections([
        _section([_doc(0)]),
      ]);
      await pumpViewport(tester);
      final paintable = producer.last.advance(AssetStage.full);
      await tester.pumpAndSettle();

      // A pager leaves and returns: bindings go, the cache keeps the entry.
      render(tester).debugDetachBindings();
      render(tester).markCatalogNeedsUpdate();
      await tester.pump();
      final canvas = paintOnce(tester);

      expect(producer.attempts, hasLength(1));
      expect(canvas.rrects, isEmpty);
      expect(paintable.paints.last.context.opacity, 1);
    });
  });

  group('the scope', () {
    testWidgets('a different scope takes over every attach', (tester) async {
      final leaf = _doc(0);
      snapshots.replaceSections([
        _section([leaf]),
      ]);
      await pumpViewport(tester);
      final other = FakeAssetProducer();
      final otherScope = AssetCacheScope(producer: other, clock: clock);
      addTearDown(otherScope.dispose);

      await pumpViewport(tester, assets: otherScope);

      expect(scope.isAttached(leaf.key, requestOf(leaf).spec), isFalse);
      expect(other.attempts, hasLength(1));
    });

    testWidgets('the same scope on a rebuild changes nothing', (tester) async {
      snapshots.replaceSections([
        _section([_doc(0)]),
      ]);
      await pumpViewport(tester);

      await pumpViewport(tester);

      expect(producer.attempts, hasLength(1));
      expect(producer.attempts.single.isCancelled, isFalse);
    });

    testWidgets('leaving the tree gives every attach back', (tester) async {
      final leaf = _doc(0);
      snapshots.replaceSections([
        _section([leaf]),
      ]);
      await pumpViewport(tester);
      final spec = requestOf(leaf).spec;
      expect(scope.isAttached(leaf.key, spec), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(scope.isAttached(leaf.key, spec), isFalse);
    });
  });
}
