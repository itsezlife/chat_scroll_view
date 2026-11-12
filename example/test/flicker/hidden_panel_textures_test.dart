/// Ticket 201: a hidden panel held a platform texture for every cell, so the
/// texture budget was spent on a panel nobody saw, and the chat played from
/// pages. A hidden panel now gives its cells' textures back keeping their
/// frames; shown again, its cells take them back and composite them from
/// the first frame. A surface held on screen (the panel while it moves, the
/// chat under a popup) keeps its textures.
///
/// **Seam:** a panel as the presentation keeps it: a grid of recents
/// (`PanelCatalogViewport`) under `TickerMode(enabled: shown)`, under an
/// invisible `Visibility` that keeps its state once hidden, with the clock
/// paused (`routeMoving`) while it moves. Over a chat sticker that plays and
/// one held while the popup is up (`ContentView.holdsWhileTickersOff`). The
/// stickers are real `LottieAnimationPaintable`s played by a real
/// `LottieFrameScheduler` on a `FrameTexturePool` of fake textures. What is
/// read is the texture layers each surface composites, and the pool.
library;

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

const _info = LottieInfo(
  width: 512,
  height: 512,
  frameCount: 60,
  frameRate: 60,
  features: LottieFeatures.none,
);

// Fewer cells than the pool keeps frames for (1 MiB each at four buffers,
// 24 MiB): every one comes back on its own texture.
const _recents = 20;

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

const _gridKey = Key('grid');
const _chatKey = Key('chat');

void main() {
  late PlaybackClock clock;
  late FrameTexturePool pool;
  late LottieFrameScheduler scheduler;
  late AssetCacheScope scope;
  late FakeCatalogSnapshotSource recents;
  late PanelCatalogController controller;
  late ValueNotifier<bool> shown;
  late ValueNotifier<bool> hidden;
  late ValueNotifier<bool> popup;
  var elapsed = Duration.zero;

  Future<void> pumpChat(WidgetTester tester) async {
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
    popup = ValueNotifier(true);
    addTearDown(() {
      recents.dispose();
      controller.dispose();
      shown.dispose();
      hidden.dispose();
      popup.dispose();
    });
    const chatPreset = AssetPreset(
      size: Size.square(120),
      spec: AssetSpec(pixelWidth: 512, pixelHeight: 512),
      profile: AssetProfile(animate: true),
    );
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(400, 800),
        child: Column(
          children: [
            RepaintBoundary(
              key: _chatKey,
              child: Row(
                children: [
                  // Plays whatever the panel does: a dock beside the chat.
                  ContentView(
                    content: const ContentKey.document('chat-playing'),
                    scope: scope,
                    preset: chatPreset,
                  ),
                  // Held on screen while the popup is up.
                  ValueListenableBuilder<bool>(
                    valueListenable: popup,
                    builder: (context, isUp, child) =>
                        TickerMode(enabled: !isUp, child: child!),
                    child: ContentView(
                      content: const ContentKey.document('chat-under-popup'),
                      scope: scope,
                      preset: chatPreset,
                      holdsWhileTickersOff: true,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // The panel, as the presentation keeps it: its shell's tickers
            // on only at rest, invisible once hidden.
            ValueListenableBuilder<bool>(
              valueListenable: hidden,
              builder: (context, isHidden, child) => Visibility(
                visible: !isHidden,
                maintainState: true,
                maintainAnimation: true,
                child: child!,
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (context, isShown, child) =>
                    TickerMode(enabled: isShown, child: child!),
                child: SizedBox(
                  height: 400,
                  child: RepaintBoundary(
                    key: _gridKey,
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

  List<int> texturesOf(WidgetTester tester, Key key) => _textures(
    tester.renderObject(find.byKey(key, skipOffstage: false)).debugLayer,
  );

  // The popup is up and plays, the chat under it held; the chat's playing
  // sticker and every cell of the panel on textures.
  Future<void> settle(WidgetTester tester) async {
    await pumpChat(tester);
    // The held sticker plays before the popup comes up, so it holds a frame
    // on a texture.
    popup.value = false;
    await frames(tester, 120);
    popup.value = true;
    await frames(tester, 60);
  }

  // Frames until [ready] holds, at most two seconds of them.
  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 120 && !ready(); i++) {
      await frame(tester);
    }
  }

  Future<void> tearDownScope(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
    scheduler.dispose();
    pool.dispose();
    clock.dispose();
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('hidden, the panel gives its textures back keeping their '
      'frames; shown again, its cells composite them from the first '
      'frame', (tester) async {
    await settle(tester);
    final steady = texturesOf(tester, _gridKey);
    expect(steady, hasLength(_recents), reason: 'every cell on a texture');
    final cellClass = pool.classCounts().entries.firstWhere(
      (entry) => entry.value.leased == _recents,
    );

    // It moves out, on screen and held: it keeps what it composites.
    final seen = <String>[];
    shown.value = false;
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);
    for (var i = 0; i < 15; i++) {
      await frame(tester);
      final now = texturesOf(tester, _gridKey);
      if (!listEquals(now, steady)) seen.add('moving out, frame $i: $now');
    }
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: false);

    // Hidden: no cell holds a texture, each keeps its frame on one.
    hidden.value = true;
    await frames(tester, 60);
    expect(pool.classCounts()[cellClass.key], (
      leased: 0,
      idle: _recents,
      kept: _recents,
    ));

    // It moves in, held, and comes to rest: every frame composites the
    // textures it left on.
    hidden.value = false;
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);
    for (var i = 0; i < 15; i++) {
      await frame(tester);
      final now = texturesOf(tester, _gridKey);
      if (!listEquals(now, steady)) seen.add('moving in, frame $i: $now');
    }
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: false);
    shown.value = true;
    for (var i = 0; i < 30; i++) {
      await frame(tester);
      final now = texturesOf(tester, _gridKey);
      if (!listEquals(now, steady)) seen.add('at rest, frame $i: $now');
    }

    await tearDownScope(tester);
    expect(seen, isEmpty, reason: 'steady: $steady\n${seen.join('\n')}');
  });

  testWidgets('the chat under the popup keeps its textures while the panel '
      'plays, moves and hides', (tester) async {
    await settle(tester);
    final steady = texturesOf(tester, _chatKey);
    expect(steady, hasLength(2), reason: 'both stickers on textures');

    final seen = <String>[];
    Future<void> watch(String phase, int count) async {
      for (var i = 0; i < count; i++) {
        await frame(tester);
        final now = texturesOf(tester, _chatKey);
        if (!listEquals(now, steady)) seen.add('$phase, frame $i: $now');
      }
    }

    await watch('the panel plays', 30);
    shown.value = false;
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);
    await watch('the panel moves out', 15);
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: false);
    hidden.value = true;
    await watch('the panel is hidden', 60);
    popup.value = false;
    await until(tester, () => texturesOf(tester, _chatKey).length == 2);
    await watch('the chat plays again', 30);

    await tearDownScope(tester);
    expect(seen, isEmpty, reason: 'steady: $steady\n${seen.join('\n')}');
  });
}
