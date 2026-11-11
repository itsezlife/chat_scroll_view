/// A catalogue whose tickers are off holds what it shows: a hidden panel kept
/// mounted, a page of the pager off screen, a panel moving in or out.
///
/// **Seam:** [PanelCatalogViewport] under [TickerMode], over a real
/// [AssetCacheScope] and a [FakeAssetProducer]. What is observed is the
/// cache's side: the attempts made (a reload is a new attempt), whether a
/// paintable was disposed, whether it is asked to keep its frame (a held
/// binding), and whether the clock plays it.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

// 4 columns of 40 px cells under a 24 px header: 640 px shows every one of 40
// leaves; 80 px shows the first row or two.
const _span = 4;
const _leaves = 40;

CatalogLeaf _sticker(int i) => CatalogLeaf.document(
  'sticker-$i',
  semanticKind: SemanticKind.sticker,
  mediaForm: MediaForm.still,
  animated: true,
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late FakeAssetProducer producer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late AssetCacheScope scope;
  late List<FakeAssetPaintable> made;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource()
      ..replaceSections([
        CatalogSection(
          id: 'a',
          title: 'A',
          leaves: [for (var i = 0; i < _leaves; i++) _sticker(i)],
        ),
      ]);
    controller = PanelCatalogController();
    producer = FakeAssetProducer();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    scope = AssetCacheScope(producer: producer, clock: clock);
    made = [];
    producer.onProduce = (attempt) => made.add(
      attempt.advance(
        AssetStage.full,
        tier: AssetTier.animated,
        frames: const [Duration(milliseconds: 40), Duration(milliseconds: 40)],
      ),
    );
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
    scope.dispose();
    clock.dispose();
  });

  final viewportKey = GlobalKey();

  Widget viewport() => PanelCatalogViewport(
    key: viewportKey,
    snapshots: snapshots,
    assets: scope,
    controller: controller,
    spanCount: _span,
    cellExtent: 40,
    headerExtent: 24,
  );

  Future<void> pump(
    WidgetTester tester, {
    bool tickers = true,
    bool offstage = false,
    bool visible = true,
    double height = 640,
  }) => tester.pumpWidget(
    MaterialApp(
      home: PanelCatalogTheme(
        data: PanelCatalogThemeData.light,
        child: Align(
          alignment: Alignment.topLeft,
          child: Visibility(
            visible: visible,
            maintainState: true,
            maintainAnimation: true,
            child: Offstage(
              offstage: offstage,
              child: TickerMode(
                enabled: tickers,
                child: SizedBox(width: 160, height: height, child: viewport()),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  RenderPanelCatalog render(WidgetTester tester) =>
      tester.renderObject(find.byKey(viewportKey, skipOffstage: false));

  testWidgets('hidden and shown again, it keeps every binding and its frame', (
    tester,
  ) async {
    await pump(tester);
    expect(made, hasLength(_leaves));
    expect(made.map((p) => p.keepsFrame), everyElement(isFalse));

    await pump(tester, tickers: false, offstage: true);

    expect(render(tester).attachedLeafCount, _leaves);
    expect(made.map((p) => p.keepsFrame), everyElement(isTrue));
    expect(made.map((p) => p.isDisposed), everyElement(isFalse));
    expect(ticks.isRunning, isFalse, reason: 'nothing plays while hidden');

    await pump(tester);

    expect(producer.attempts, hasLength(_leaves), reason: 'nothing reloaded');
    expect(made.map((p) => p.isDisposed), everyElement(isFalse));
    expect(made.map((p) => p.keepsFrame), everyElement(isFalse));
    expect(ticks.isRunning, isTrue, reason: 'playing again');
  });

  testWidgets('hidden from view (a Visibility), every leaf leaves the screen '
      'and keeps its frame; shown, they are on screen again', (tester) async {
    await pump(tester);

    await pump(tester, tickers: false, visible: false);

    expect(render(tester).attachedLeafCount, _leaves);
    expect(made.map((p) => p.keepsFrame), everyElement(isTrue));
    expect(made.map((p) => p.departures), everyElement(1));
    expect(made.map((p) => p.isDisposed), everyElement(isFalse));

    // Shown, still held while it moves in: on screen, nothing reloaded.
    await pump(tester, tickers: false);
    expect(producer.attempts, hasLength(_leaves));
    expect(made.map((p) => p.keepsFrame), everyElement(isTrue));

    // They are on screen again: hidden once more, they leave again.
    await pump(tester, tickers: false, visible: false);
    expect(made.map((p) => p.departures), everyElement(2));
  });

  testWidgets('held on screen, no leaf leaves it', (tester) async {
    await pump(tester);

    await pump(tester, tickers: false);

    expect(made.map((p) => p.keepsFrame), everyElement(isTrue));
    expect(made.map((p) => p.departures), everyElement(0));
  });

  testWidgets('held, a smaller layout detaches nothing; let go, it does', (
    tester,
  ) async {
    await pump(tester);

    await pump(tester, tickers: false, height: 80);
    expect(render(tester).attachedLeafCount, _leaves);

    await pump(tester, height: 80);
    expect(render(tester).attachedLeafCount, lessThan(_leaves));
  });

  testWidgets('a leaf that comes into view while held attaches held', (
    tester,
  ) async {
    await pump(tester, tickers: false, height: 80);
    final first = made.length;

    await pump(tester, tickers: false);

    expect(made.length, greaterThan(first));
    expect(made.map((p) => p.keepsFrame), everyElement(isTrue));
  });

  testWidgets('moved within one frame (a keep-alive bucket), it keeps its '
      'bindings', (tester) async {
    Widget host({required bool left}) => MaterialApp(
      home: PanelCatalogTheme(
        data: PanelCatalogThemeData.light,
        child: TickerMode(
          enabled: false,
          child: Row(
            children: [
              SizedBox(
                width: 160,
                height: 640,
                child: left ? viewport() : null,
              ),
              SizedBox(
                width: 160,
                height: 640,
                child: left ? null : viewport(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(left: true));

    await tester.pumpWidget(host(left: false));
    await tester.pump();

    expect(producer.attempts, hasLength(_leaves));
    expect(made.map((p) => p.keepsFrame), everyElement(isTrue));
  });
}
