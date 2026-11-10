/// Ticket 152: with the texture budget busy (stickers playing in the chat,
/// rows of recents in the panel), the covers of the panel's pack strip lose
/// their frames on every close and open of the panel and load again.
///
/// **Seam:** the chat's stickers (`ContentView`s that always play), and a
/// panel kept mounted while hidden, as the presentation keeps it: a grid of
/// recents (`PanelCatalogViewport`) under a strip of covers
/// (`PanelStripCover`), the whole under `TickerMode(enabled: shown)` and
/// offstage once hidden, with the clock paused (`routeMoving`) while it
/// moves; the chat's stickers it covers leave the screen as it opens. The
/// stickers are real `LottieAnimationPaintable`s played by a real
/// `LottieFrameScheduler` on a `FrameTexturePool` of fake textures, whose
/// bound on kept frames those stickers fill. Read after the panel is back: each
/// cover composites the texture it showed before the close, from the first
/// frame (no still, no new texture).
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';
import 'package:panel_pages/src/strip/panel_strip.dart';
import 'package:panel_shell/testing.dart';

const _info = LottieInfo(
  width: 512,
  height: 512,
  frameCount: 60,
  frameRate: 60,
  features: LottieFeatures.none,
);

const _covers = 6;
const _recents = 30;
const _chat = 3;

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

const _stripKey = Key('strip');

void main() {
  late PlaybackClock clock;
  late FrameTexturePool pool;
  late LottieFrameScheduler scheduler;
  late AssetCacheScope scope;
  late FakeCatalogSnapshotSource recents;
  late PanelCatalogController controller;
  late ValueNotifier<bool> shown;
  late ValueNotifier<bool> hidden;
  var elapsed = Duration.zero;

  Future<void> pumpChat(
    WidgetTester tester, {
    required int chatStickers,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    elapsed = Duration.zero;
    clock = PlaybackClock();
    // The frames kept for surfaces that left the screen are bounded: the
    // chat's stickers the panel covers (4 MiB each, at 4 buffers) leave as
    // it opens, after a cover released as it closed, and fill the bound.
    // On a device the bound is larger and more has left before them.
    pool = FrameTexturePool(
      host: FakeFrameTextureHost(buffersPerTexture: 4),
      keptFrameBytes: 8 * 1024 * 1024,
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
    recents = FakeCatalogSnapshotSource()
      ..replaceSections([
        CatalogSection(
          id: 'recents',
          title: 'recents',
          leaves: [
            for (var i = 0; i < _recents; i++)
              CatalogLeaf.document(
                'recent-$i',
                semanticKind: SemanticKind.sticker,
                mediaForm: MediaForm.vectorAnimation,
                animated: true,
              ),
          ],
        ),
      ]);
    controller = PanelCatalogController();
    shown = ValueNotifier(true);
    hidden = ValueNotifier(false);
    addTearDown(() {
      recents.dispose();
      controller.dispose();
      shown.dispose();
      hidden.dispose();
    });
    final tokens = PanelTokens.fromPalette(const ChromePalette.light());
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(400, 800),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < chatStickers; i++)
                  ContentView(
                    content: ContentKey.document('chat-$i'),
                    scope: scope,
                    preset: const AssetPreset(
                      size: Size.square(120),
                      spec: AssetSpec(pixelWidth: 512, pixelHeight: 512),
                      profile: AssetProfile(animate: true),
                    ),
                  ),
              ],
            ),
            // The chat's stickers the panel covers: on screen while it is
            // hidden, off it while it is up.
            ValueListenableBuilder<bool>(
              valueListenable: hidden,
              builder: (context, isHidden, child) =>
                  TickerMode(enabled: isHidden, child: child!),
              child: Row(
                children: [
                  for (var i = 0; i < chatStickers; i++)
                    ContentView(
                      content: ContentKey.document('chat-under-$i'),
                      scope: scope,
                      preset: const AssetPreset(
                        size: Size.square(120),
                        spec: AssetSpec(pixelWidth: 512, pixelHeight: 512),
                        profile: AssetProfile(animate: true),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            // The panel, as the presentation keeps it: its shell's tickers
            // on only at rest, offstage once hidden.
            ValueListenableBuilder<bool>(
              valueListenable: hidden,
              builder: (context, isHidden, child) =>
                  Offstage(offstage: isHidden, child: child),
              child: ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (context, isShown, child) =>
                    TickerMode(enabled: isShown, child: child!),
                child: SizedBox(
                  height: 400,
                  child: Column(
                    children: [
                      RepaintBoundary(
                        key: _stripKey,
                        child: Row(
                          children: [
                            for (var i = 0; i < _covers; i++)
                              PanelStripCover(
                                content: ContentKey.document('cover-$i'),
                                scope: scope,
                                size: 30,
                                plays: true,
                                tokens: tokens,
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: PanelCatalogTheme(
                          data: PanelCatalogThemeData.light,
                          child: PanelCatalogViewport(
                            snapshots: recents,
                            assets: scope,
                            controller: controller,
                            spanCount: 5,
                            cellExtent: 72,
                            headerExtent: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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

  List<int> stripTextures(WidgetTester tester) =>
      _textures(tester.renderObject(find.byKey(_stripKey)).debugLayer);

  // The panel moves out (the shell's tickers off, the clock held), rests
  // hidden, then moves in again and rests shown.
  Future<void> closeAndOpen(WidgetTester tester) async {
    shown.value = false;
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);
    await frames(tester, 15);
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: false);
    hidden.value = true;
    await frames(tester, 60);
    hidden.value = false;
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);
    await frames(tester, 15);
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: false);
    shown.value = true;
  }

  Future<void> tearDownScope(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
    scheduler.dispose();
    pool.dispose();
    clock.dispose();
    await tester.pump(const Duration(seconds: 3));
  }

  for (final chatStickers in [0, _chat]) {
    testWidgets('with $chatStickers stickers playing in the chat, the strip '
        "keeps its covers' textures through a close and an open of the "
        'panel', (tester) async {
      await pumpChat(tester, chatStickers: chatStickers);
      await frames(tester, 120);
      final steady = stripTextures(tester);
      expect(steady, hasLength(_covers), reason: 'every cover on a texture');

      final seen = <String>[];
      for (var round = 0; round < 3; round++) {
        await closeAndOpen(tester);
        for (var i = 0; i < 10; i++) {
          await frame(tester);
          final now = stripTextures(tester);
          if (!listEquals(now, steady)) seen.add('round $round frame $i: $now');
        }
        await frames(tester, 60);
      }

      await tearDownScope(tester);
      expect(seen, isEmpty, reason: 'steady: $steady\n${seen.join('\n')}');
    });
  }
}
