/// Ticket 203: a page of the panel's pager that is not on screen held a
/// platform texture for every cell while the panel was shown (its tickers
/// off read as a surface held on screen), so the pages switched away from
/// spent the texture budget nobody saw. A page off screen now gives its
/// cells' textures back keeping their frames, as a hidden panel does;
/// brought back, its cells take them back and composite them from the first
/// frame it shows.
///
/// **Seam:** two pages of a `SwipePager`, each a grid of stickers
/// (`PanelCatalogViewport`), switched with the pager's controller. The
/// stickers are real `LottieAnimationPaintable`s played by a real
/// `LottieFrameScheduler` on a `FrameTexturePool` of fake textures. What is
/// read is the texture layers each page composites, and the pool.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:panel_shell/testing.dart';
import 'package:swipe_pager/swipe_pager.dart';

const _info = LottieInfo(
  width: 512,
  height: 512,
  frameCount: 60,
  frameRate: 60,
  features: LottieFeatures.none,
);

// Cells per page. Both pages together are fewer than the pool keeps frames
// for (1 MiB each at four buffers, 24 MiB): every cell of a page left comes
// back on its own texture.
const _cells = 10;

ui.Image _image([int side = 4]) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(side, side);
  picture.dispose();
  return image;
}

Future<ui.Image> _upload(Uint8List pixels, int side) => Future.value(_image());

/// Hands out a playing Lottie paintable for every request at once.
final class _LottieProducer implements AssetProducer {
  _LottieProducer(this.scheduler);

  final LottieFrameScheduler scheduler;
  var _handles = 0;

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    progress.advance(
      AssetStage.full,
      LottieAnimationPaintable(
        key: '${request.key}@${request.spec.pixelWidth}',
        handle: LottieHandle(++_handles),
        info: _info,
        firstFrame: _image(8),
        scheduler: scheduler,
        renderEdge: request.spec.pixelWidth,
      ),
      bytes: 64,
      tier: AssetTier.animated,
    );
    return _Task();
  }
}

final class _Task implements AssetTask {
  @override
  void cancel() {}
}

/// The texture ids composited in [layer]'s subtree, in paint order.
List<int> _textures(Layer? layer) {
  final ids = <int>[];
  void walk(Layer? layer) {
    if (layer == null) return;
    if (layer is TextureLayer) ids.add(layer.textureId);
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk(child);
      }
    }
  }

  walk(layer);
  return ids;
}

Key _pageKey(int page) => Key('page-$page');

void main() {
  late PlaybackClock clock;
  late FrameTexturePool pool;
  late LottieFrameScheduler scheduler;
  late AssetCacheScope scope;
  late List<FakeCatalogSnapshotSource> sources;
  late List<PanelCatalogController> controllers;
  late SwipePagerController pager;
  var elapsed = Duration.zero;

  Future<void> pumpPager(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    elapsed = Duration.zero;
    clock = PlaybackClock();
    pool = FrameTexturePool(
      host: FakeFrameTextureHost(buffersPerTexture: 4),
      now: () => elapsed,
    );
    scheduler = LottieFrameScheduler(
      atlas: FrameAtlas<Object>(
        renderer: FakeFrameRenderer(),
        memory: ListFramePageMemory(),
        upload: _upload,
      ),
      clock: clock,
      textures: pool,
      textureWriter: FakeTextureFrameWriter(),
    );
    scope = AssetCacheScope(producer: _LottieProducer(scheduler), clock: clock);
    sources = [
      for (var page = 0; page < 2; page++)
        FakeCatalogSnapshotSource()..replaceSections([
          CatalogSection(
            id: 'page-$page',
            title: 'page $page',
            leaves: [
              for (var i = 0; i < _cells; i++)
                CatalogLeaf.document(
                  'page-$page-$i',
                  semanticKind: SemanticKind.sticker,
                  mediaForm: MediaForm.vectorAnimation,
                  animated: true,
                ),
            ],
          ),
        ]),
    ];
    controllers = [PanelCatalogController(), PanelCatalogController()];
    pager = SwipePagerController();
    addTearDown(() {
      for (final source in sources) {
        source.dispose();
      }
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(400, 800),
        child: SizedBox(
          height: 400,
          child: SwipePager(
            controller: pager,
            pageCount: 2,
            pageBuilder: (context, page) => RepaintBoundary(
              key: _pageKey(page),
              child: PanelCatalogTheme(
                data: PanelCatalogThemeData.light,
                child: PanelCatalogViewport(
                  snapshots: sources[page],
                  assets: scope,
                  controller: controllers[page],
                  spanCount: 5,
                  cellExtent: 72,
                  headerExtent: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> frame(WidgetTester tester) async {
    elapsed += const Duration(milliseconds: 16);
    await tester.pump(const Duration(milliseconds: 16));
  }

  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await frame(tester);
    }
  }

  List<int> texturesOf(WidgetTester tester, int page) => _textures(
    tester
        .renderObject(find.byKey(_pageKey(page), skipOffstage: false))
        .debugLayer,
  );

  Future<void> tearDownScope(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    pager.dispose();
    scope.dispose();
    scheduler.dispose();
    pool.dispose();
    clock.dispose();
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('a page switched away from gives its textures back keeping '
      'their frames; brought back, its cells composite them from the first '
      'frame it shows', (tester) async {
    await pumpPager(tester);
    await frames(tester, 120);
    final steady = texturesOf(tester, 0);
    expect(steady, hasLength(_cells), reason: 'every cell on a texture');
    final cellClass = pool.classCounts().entries.firstWhere(
      (entry) => entry.value.leased == _cells,
    );

    // On the other page: only its cells hold textures; the first page's
    // keep their frames on textures given back.
    pager.jumpTo(1);
    await frames(tester, 120);
    expect(texturesOf(tester, 1), hasLength(_cells));
    expect(pool.classCounts()[cellClass.key], (
      leased: _cells,
      idle: _cells,
      kept: _cells,
    ));

    // Slid back: from the first frame the page shows, it composites the
    // textures it left on.
    final seen = <String>[];
    unawaited(pager.animateTo(0));
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await frame(tester);
      final now = texturesOf(tester, 0);
      if (!listEquals(now, steady)) seen.add('frame $i: $now');
    }
    expect(pager.position, 0);

    await tearDownScope(tester);
    expect(seen, isEmpty, reason: 'steady: $steady\n${seen.join('\n')}');
  });
}
