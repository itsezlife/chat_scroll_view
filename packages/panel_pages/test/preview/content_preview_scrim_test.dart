/// The content preview's backdrop: the chrome scrim of the content preview
/// preset, its phases reported as `overlay` events, and the picture the
/// preview shows from its first frame.
///
/// **Seam:** [StickersPage] given a [ContentPreviewController], under an
/// [Overlay] the preview is shown in, observed through the events a
/// [RecordingDiagnostics] receives, the [ChromeScrim] the preview draws and
/// the paints of the [FakeAssetProducer]'s paintables. Geometry: a 360 x 480
/// page in an 800 x 600 window, the 36 px strip above, packs of 10 stickers
/// in 5 columns of 72 x 82 under a 27 px header.
library;

import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/testing.dart';

CollectionItem _sticker(String id) => CollectionItem.described(
  ContentDescriptor(
    key: ContentKey.document(id),
    semanticKind: SemanticKind.sticker,
    mediaForm: MediaForm.vectorAnimation,
    animated: true,
    size: const ContentSize(512, 512),
    pack: const PackId('a'),
  ),
);

FakeCollectionSpec _pack() => FakeCollectionSpec(
  const CollectionId.set('a'),
  metadata: const CollectionMetadata(title: 'a'),
  pages: FakePages([
    [for (var i = 0; i < 10; i++) _sticker('a-$i')],
  ]),
);

void main() {
  late FakePanelPageHost host;
  late FakeAssetProducer producer;
  late ContentAssetScope assets;
  late ContentPreviewController previews;
  late RecordingDiagnostics diagnostics;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    host = FakePanelPageHost(pageId: 'stickers');
    // An animated sticker's decode: its first frame as it starts, then the
    // animation from that frame, after the view attached.
    producer = FakeAssetProducer()
      ..onProduce = (attempt) {
        attempt.advance(AssetStage.firstFrame);
        scheduleMicrotask(
          () => attempt.advance(
            AssetStage.full,
            tier: AssetTier.animated,
            frames: List.filled(4, const Duration(milliseconds: 33)),
          ),
        );
      };
    assets = ContentAssetScope.withMedia(producer: producer);
    previews = ContentPreviewController();
    addTearDown(() {
      previews.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Future<void> pumpPage(WidgetTester tester, {bool source = true}) async {
    final collections = FakeCollectionSource([_pack()]);
    addTearDown(collections.dispose);
    Widget page = Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => Center(
            child: SizedBox(
              width: 360,
              height: 480,
              child: StickersPage(
                host: host,
                source: collections,
                assets: assets,
                previews: previews,
              ),
            ),
          ),
        ),
      ],
    );
    if (source) page = BackdropSnapshotSource(child: page);
    await tester.pumpWidget(
      PanelShellTestScope(size: const Size(800, 600), child: page),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Offset cell(WidgetTester tester, int index) =>
      tester.getTopLeft(find.byType(StickersPage)) +
      Offset(72 * (index + .5), 36 + 27 + 41);

  Future<TestGesture> hold(
    WidgetTester tester,
    int index, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final gesture = await tester.startGesture(cell(tester, index), kind: kind);
    await tester.pump(
      kind == PointerDeviceKind.mouse
          ? ContentPreviewSession.pointerHoldDelay
          : ContentPreviewSession.touchHoldDelay,
    );
    await tester.pump(ContentPreviewSession.pointerShowDuration);
    await tester.pump(const Duration(milliseconds: 16));
    return gesture;
  }

  Future<void> settleClose(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(AppearMotion$Unfold.hide);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
  }

  List<ChatEvent> scrimEvents() => [
    for (final event in diagnostics.whereCategory(ChatEventCategory.overlay))
      if (event.op.name.startsWith('scrim')) event,
  ];

  List<String> scrimOps() => [for (final event in scrimEvents()) event.op.name];

  ChatEvent scrimEvent(ContentPreviewOp op) =>
      scrimEvents().singleWhere((event) => event.op == op);

  testWidgets('the preview draws its backdrop through one chrome scrim of '
      'the content preview preset', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 1);

    final scrim = tester.widget<ChromeScrim>(find.byType(ChromeScrim));
    expect(scrim.controller.preset, ChromeScrimPreset.contentPreview);
    expect(scrim.controller.isStillShown, isFalse, reason: 'until the menu');

    await gesture.up();
    await settleClose(tester);
    expect(find.byType(ChromeScrim), findsNothing);
  });

  testWidgets('a mouse preview fades its dim over 150 ms and takes no still', (
    tester,
  ) async {
    await pumpPage(tester);
    final mouse = await hold(tester, 1, kind: PointerDeviceKind.mouse);

    final scrim = tester.widget<ChromeScrim>(find.byType(ChromeScrim));
    expect(scrim.controller.preset.dimFade, ScrimMotion.contentPreviewPointer);
    expect(scrim.controller.preset.stillFade, ScrimMotion.contentPreview);
    expect(scrim.controller.still, isNull);

    await mouse.up();
    await settleClose(tester);
  });

  testWidgets('the preview shows its picture from its first frame, with no '
      'fade of its own', (tester) async {
    await pumpPage(tester);
    final cells = producer.attempts.length;
    final gesture = await tester.startGesture(cell(tester, 1));
    await tester.pump(ContentPreviewSession.touchHoldDelay);
    // The show's first frame past 0 attaches the preview's view.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));

    // The cells were decoded before the press: what came since is the
    // preview's own, larger picture.
    final previewed = producer.attempts.skip(cells).toList();
    expect(previewed, isNotEmpty, reason: 'the preview asked for its picture');
    final paints = [
      for (final attempt in previewed)
        for (final paintable in attempt.paintables) ...[
          ...paintable.paints,
          ...?paintable.firstFrame?.paints,
        ],
    ];
    expect(paints, isNotEmpty, reason: 'the first frame painted the picture');
    expect(
      [
        for (final attempt in previewed)
          for (final paintable in attempt.paintables)
            if (paintable.isAnimated && paintable.paints.isNotEmpty) paintable,
      ],
      isNotEmpty,
      reason: 'the animation took over from its first frame',
    );
    expect([
      for (final paint in paints) paint.context.opacity,
    ], everyElement(1));

    await gesture.up();
    await settleClose(tester);
  });

  testWidgets('a press outside reports the capture, the dismissal and the '
      'disposal as overlay events of the content preview', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 1);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);

    await tester.tapAt(const Offset(10, 10));
    await settleClose(tester);

    expect(previews.isOpen.value, isFalse);
    expect(scrimOps(), ['scrimCaptured', 'scrimDismissed', 'scrimDisposed']);
    final captured = scrimEvent(ContentPreviewOp.scrimCaptured);
    expect(captured.level, ChatEventLevel.trace);
    expect(captured.fields['owner'], 'contentPreview');
    expect(captured.fields['preset'], 'contentPreview');
    expect(captured.fields['captureUs'], isA<int>());
    // 1/15 of the 800 x 600 window at a device pixel ratio of 3.
    expect(captured.fields['stillWidth'], 160);
    expect(captured.fields['stillHeight'], 120);

    final dismissed = scrimEvent(ContentPreviewOp.scrimDismissed);
    expect(dismissed.level, ChatEventLevel.debug);
    expect(dismissed.fields, {
      'owner': 'contentPreview',
      'by': ChromeScrimDismissal.outside,
      'closeOn': ChromeScrimCloseOn.down,
    });
    final disposed = scrimEvent(ContentPreviewOp.scrimDisposed);
    expect(disposed.level, ChatEventLevel.trace);
    expect(disposed.fields, {'owner': 'contentPreview', 'stills': 1});
  });

  testWidgets('the made still is reported with its time', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 1);
    final still = tester
        .widget<ChromeScrim>(find.byType(ChromeScrim))
        .controller
        .still!;
    var done = false;
    unawaited(still.ready.then((_) => done = true));
    for (var turn = 0; !done && turn < 200; turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    final ready = scrimEvent(ContentPreviewOp.scrimStillReady);
    expect(ready.level, ChatEventLevel.trace);
    expect(ready.fields['owner'], 'contentPreview');
    expect(ready.fields['preset'], 'contentPreview');
    expect(ready.fields['cpuMs'], isA<int>());
    expect(ready.fields['glassSource'], isFalse);

    await gesture.up();
    await settleClose(tester);
  });

  testWidgets('back closes it and is reported as a dismissal by back', (
    tester,
  ) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 1);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await settleClose(tester);

    expect(previews.isOpen.value, isFalse);
    expect(
      scrimEvent(ContentPreviewOp.scrimDismissed).fields['by'],
      ChromeScrimDismissal.back,
    );
  });

  testWidgets('the host closing it reports no dismissal', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 1);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);

    expect(previews.dismiss(), isTrue);
    await settleClose(tester);

    expect(scrimOps(), ['scrimCaptured', 'scrimDisposed']);
  });

  testWidgets('cancelled, it reports the cancel then the disposal', (
    tester,
  ) async {
    await pumpPage(tester);
    await hold(tester, 1);

    previews.dispose();
    await tester.pump();

    expect(find.byType(ChromeScrim), findsNothing);
    expect(scrimOps(), ['scrimCaptured', 'scrimCancelled', 'scrimDisposed']);
    expect(scrimEvent(ContentPreviewOp.scrimCancelled).fields, {
      'owner': 'contentPreview',
    });
    expect(scrimEvent(ContentPreviewOp.scrimDisposed).fields['stills'], 1);
  });

  testWidgets('a mouse preview reports its still skipped, as a dim alone', (
    tester,
  ) async {
    await pumpPage(tester);
    final mouse = await hold(tester, 1, kind: PointerDeviceKind.mouse);
    await mouse.up();
    await settleClose(tester);

    expect(scrimOps(), ['scrimStillSkipped', 'scrimDisposed']);
    final skipped = scrimEvent(ContentPreviewOp.scrimStillSkipped);
    expect(skipped.level, ChatEventLevel.debug);
    expect(skipped.fields, {
      'owner': 'contentPreview',
      'why': ChromeScrimStillSkip.presetNoBlur,
    });
    expect(scrimEvent(ContentPreviewOp.scrimDisposed).fields['stills'], 0);
  });

  testWidgets('a host with no snapshot source reports no source', (
    tester,
  ) async {
    await pumpPage(tester, source: false);
    final gesture = await hold(tester, 1);

    expect(
      scrimEvent(ContentPreviewOp.scrimStillSkipped).fields['why'],
      ChromeScrimStillSkip.noSource,
    );
    await gesture.up();
    await settleClose(tester);
  });

  test('the documented values are the content preview preset\'s', () {
    const preset = ChromeScrimPreset.contentPreview;
    expect(preset.dimDark, ContentPreviewSession.dimDark);
    expect(preset.dimLight, ContentPreviewSession.dimLight);
    expect(preset.dimOpacity, ContentPreviewSession.dimAlpha / 255);
    expect(preset.dimFade.duration, ContentPreviewSession.showDuration);
    expect(preset.stillFade.duration, ContentPreviewSession.showDuration);
    expect(preset.still!.downscale, ContentPreviewSession.backdropDownscale);
    expect(preset.still!.blurRadius, ContentPreviewSession.backdropBlurRadius);
    expect(
      preset.still!.toneDark,
      ChromeScrimTone(
        saturation: ContentPreviewSession.backdropToneDark.saturation,
        brightness: ContentPreviewSession.backdropToneDark.brightness,
      ),
    );
    expect(
      preset.still!.toneLight,
      ChromeScrimTone(
        saturation: ContentPreviewSession.backdropToneLight.saturation,
        brightness: ContentPreviewSession.backdropToneLight.brightness,
      ),
    );
    expect(preset.closeOn, ChromeScrimCloseOn.down);
  });
}
