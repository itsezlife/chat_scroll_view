/// The pack strip of the stickers page: which tabs it shows, which one is
/// active, where a tap lands, how the active mark moves and how the covers
/// play.
///
/// **Seam:** [StickerPackStrip] over a fake [CatalogStripHandle] the test
/// steers (the sections, the catalogue's events, the answer to a jump), under
/// the chrome scopes, observed through the semantics of its tabs, the jumps
/// the handle received and the strip's scroll offset; the covers draw through
/// an `AssetCacheScope` over a `FakeAssetProducer` and a manually ticked
/// clock, observed through the paints of the fake paintables.
library;

import 'dart:async';
import 'dart:math' show max;
import 'dart:ui' show Tristate;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart' show FrameAtlas;
import 'package:catalog_assets/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

final class _Handle implements CatalogStripHandle {
  _Handle(List<Collection> collections)
    : entries = listen.ValueNotifier(_entries(collections));

  @override
  final listen.ValueNotifier<List<CatalogStripEntry>> entries;

  final events = StreamController<PanelCatalogScrollEvent>.broadcast(
    sync: true,
  );

  @override
  String? currentSectionId;

  final jumps = <String>[];
  Completer<void>? pending;

  @override
  Stream<PanelCatalogScrollEvent> get scrollEvents => events.stream;

  @override
  Future<void> jumpToSection(String sectionId) {
    jumps.add(sectionId);
    return (pending = Completer<void>()).future;
  }

  void enter(String sectionId, int index) {
    currentSectionId = sectionId;
    events.add(PanelCatalogCurrentSectionChanged(index, sectionId));
  }

  void dispose() {
    entries.dispose();
    unawaited(events.close());
  }
}

List<CatalogStripEntry> _entries(List<Collection> collections) => [
  for (final collection in collections)
    CatalogStripEntry(sectionId: '${collection.id}', collection: collection),
];

Collection _pack(String id, String title) => Collection(
  id: CollectionId.set(id),
  metadata: CollectionMetadata(title: title),
);

const _recent = Collection(id: CollectionId.recent);

// A pack whose first sticker, its cover, is [cover].
Collection _packOf(String id, ContentKey cover) => Collection(
  id: CollectionId.set(id),
  metadata: CollectionMetadata(title: id),
  contents: CollectionContents.loaded([CollectionItem.bare(cover)]),
);

const _frames = [Duration(milliseconds: 40), Duration(milliseconds: 40)];

void main() {
  late _Handle handle;

  setUp(
    () => handle = _Handle([_recent, _pack('a', 'Cats'), _pack('b', 'Dogs')]),
  );
  tearDown(() => handle.dispose());

  Future<void> pump(
    WidgetTester tester, {
    double width = 360,
    ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
    TextDirection textDirection = TextDirection.ltr,
    AssetCacheScope? assets,
    double devicePixelRatio = 1,
  }) => tester.pumpWidget(
    PanelShellTestScope(
      speed: speed,
      textDirection: textDirection,
      child: PanelArrangementScope(
        arrangement: PanelArrangement.touch,
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: width,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(devicePixelRatio: devicePixelRatio),
                child: StickerPackStrip(handle: handle, assets: assets),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  bool selected(WidgetTester tester, String label) =>
      tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData()
          .flagsCollection
          .isSelected ==
      Tristate.isTrue;

  double stripOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(StickerPackStrip),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  testWidgets('goes away cleanly when it never had a tab', (tester) async {
    handle.dispose();
    handle = _Handle(const []);
    await pump(tester);

    await tester.pumpWidget(const SizedBox());

    expect(tester.takeException(), isNull);
  });

  testWidgets('is 36 tall, the height of the reference strip', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.byType(StickerPackStrip)).height, 36);
  });

  testWidgets('has a tab for the recents and one per pack, named for them', (
    tester,
  ) async {
    await pump(tester);

    expect(find.bySemanticsLabel('Recently used'), findsOneWidget);
    expect(find.bySemanticsLabel('Cats'), findsOneWidget);
    expect(find.bySemanticsLabel('Dogs'), findsOneWidget);
  });

  testWidgets('is one labelled group for assistive technology', (tester) async {
    await pump(tester);

    expect(find.bySemanticsLabel('Sticker packs'), findsOneWidget);
  });

  testWidgets('lays tabs 33 wide from 9.5 in, as the reference strip does', (
    tester,
  ) async {
    await pump(tester);

    final origin = tester.getTopLeft(find.byType(StickerPackStrip));
    // Tab i spans 9.5 + 33 i .. 9.5 + 33 (i + 1).
    expect(
      tester.getRect(find.bySemanticsLabel('Cats')).left - origin.dx,
      closeTo(9.5 + 33, .01),
    );
    expect(
      tester.getRect(find.bySemanticsLabel('Cats')).width,
      closeTo(33, .01),
    );
    expect(
      tester.getRect(find.bySemanticsLabel('Dogs')).left - origin.dx,
      closeTo(9.5 + 66, .01),
    );
  });

  testWidgets('starts on the first tab, or the tab of the section the '
      'catalogue is in', (tester) async {
    await pump(tester);
    expect(selected(tester, 'Recently used'), isTrue);

    handle.currentSectionId = '${const CollectionId.set('b')}';
    handle.entries.value = _entries([
      _recent,
      _pack('a', 'Cats'),
      _pack('b', 'Dogs'),
    ]);
    await tester.pump();

    expect(selected(tester, 'Dogs'), isTrue);
    expect(selected(tester, 'Recently used'), isFalse);
  });

  testWidgets('follows the section the catalogue is in', (tester) async {
    await pump(tester);

    handle.enter('${const CollectionId.set('a')}', 1);
    await tester.pump();

    expect(selected(tester, 'Cats'), isTrue);
    expect(selected(tester, 'Recently used'), isFalse);
  });

  testWidgets('a tap jumps to the pack\'s section and marks it at once', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.bySemanticsLabel('Dogs'));
    await tester.pump();

    expect(handle.jumps, ['${const CollectionId.set('b')}']);
    expect(selected(tester, 'Dogs'), isTrue);
  });

  testWidgets('keeps the tapped tab while the jump runs, whatever sections the '
      'catalogue scrolls through, and ignores a second tap', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Dogs'));
    await tester.pump();

    handle.enter('${const CollectionId.set('a')}', 1);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Cats'));
    await tester.pump();

    expect(selected(tester, 'Dogs'), isTrue);
    expect(handle.jumps, hasLength(1));

    handle.pending!.complete();
    await tester.pump();
    handle.enter('${const CollectionId.set('a')}', 1);
    await tester.pump();
    expect(selected(tester, 'Cats'), isTrue);
  });

  testWidgets('reaches a pack that does not fit, keeping it in view', (
    tester,
  ) async {
    handle.entries.value = _entries([
      for (var i = 0; i < 20; i++) _pack('p$i', 'Pack $i'),
    ]);
    await pump(tester, width: 200);
    expect(stripOffset(tester), 0);

    handle.enter('${const CollectionId.set('p15')}', 15);
    await tester.pumpAndSettle();

    expect(stripOffset(tester), greaterThan(0));
    final tab = tester.getRect(find.bySemanticsLabel('Pack 15'));
    final strip = tester.getRect(find.byType(StickerPackStrip));
    expect(tab.left, greaterThanOrEqualTo(strip.left));
    expect(tab.right, lessThanOrEqualTo(strip.right));
  });

  testWidgets('starts at the right under right-to-left', (tester) async {
    await pump(tester, textDirection: TextDirection.rtl);

    final strip = tester.getRect(find.byType(StickerPackStrip));
    expect(
      strip.right - tester.getRect(find.bySemanticsLabel('Cats')).right,
      closeTo(9.5 + 33, .01),
    );
  });

  group('the mark', () {
    // The reference strip draws the active mark as a 30 px pill that is
    // widest and flattest half way through its slide.
    test('is 30 square at rest', () {
      expect(StickerPackStrip.pillSizeAt(0), const Size(30, 30));
      expect(StickerPackStrip.pillSizeAt(1), const Size(30, 30));
    });

    test('is 37.5 wide and 27 tall half way through its slide', () {
      final size = StickerPackStrip.pillSizeAt(.5);
      expect(size.width, closeTo(37.5, .001));
      expect(size.height, closeTo(27, .001));
    });
  });

  testWidgets('lands the mark, 30 square, on the tab after the slide ends', (
    tester,
  ) async {
    await pump(tester);
    handle.enter('${const CollectionId.set('b')}', 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final strip = tester.getRect(find.byType(StickerPackStrip));
    final mark = tester.getRect(find.byKey(StickerPackStrip.markKey));
    final tab = tester.getRect(find.bySemanticsLabel('Dogs'));
    expect(mark.size, const Size(30, 30));
    expect(mark.center.dx, closeTo(tab.center.dx, .5));
    expect(mark.center.dy, closeTo(strip.center.dy, .5));
  });

  testWidgets('slides the mark through the tabs between, not past them', (
    tester,
  ) async {
    await pump(tester);
    handle.enter('${const CollectionId.set('b')}', 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final mark = tester.getRect(find.byKey(StickerPackStrip.markKey));
    final from = tester
        .getRect(find.bySemanticsLabel('Recently used'))
        .center
        .dx;
    final to = tester.getRect(find.bySemanticsLabel('Dogs')).center.dx;
    expect(mark.center.dx, greaterThan(from));
    expect(mark.center.dx, lessThanOrEqualTo(to));
  });

  group('the covers', () {
    // The reference strip plays a pack's animated cover in its tab, looping,
    // while the tab is on screen, and stops it once the tab scrolls away.
    const cats = ContentKey.document('cats');
    const dogs = ContentKey.document('dogs');
    late FakeAssetProducer producer;
    late ManualPlaybackTickSource ticks;
    late AssetCacheScope scope;

    setUp(() {
      producer = FakeAssetProducer();
      ticks = ManualPlaybackTickSource();
      scope = AssetCacheScope(
        producer: producer,
        clock: PlaybackClock(ticks: ticks),
      );
      addTearDown(scope.dispose);
      handle.entries.value = _entries([
        _recent,
        _packOf('a', cats),
        _packOf('b', dogs),
      ]);
    });

    FakeAssetAttempt attemptOf(ContentKey key) =>
        producer.attempts.lastWhere((attempt) => attempt.request.key == key);

    Future<void> tick(WidgetTester tester, int ms) async {
      ticks.tick(Duration(milliseconds: ms));
      await tester.pump();
    }

    testWidgets('plays an animated cover, looping, on the clock', (
      tester,
    ) async {
      await pump(tester, assets: scope);
      final cover = attemptOf(cats).advance(AssetStage.full, frames: _frames);
      await tester.pump();
      final before = cover.paints.length;

      await tick(tester, 100);
      await tick(tester, 200);

      expect(cover.paints.length, before + 2);
      expect(cover.paints.last.context.animate, isTrue);
      expect(cover.paints.last.context.loop, isTrue);
    });

    testWidgets('leaves a still cover still', (tester) async {
      await pump(tester, assets: scope);
      final cover = attemptOf(cats).advance(AssetStage.full);
      await tester.pump();
      // Past the fade a cover that arrived after the attach rises in.
      await tester.pump(const Duration(milliseconds: 160));
      final before = cover.paints.length;

      await tick(tester, 100);

      expect(cover.paints.length, before);
      expect(ticks.isRunning, isFalse);
    });

    // The frame pool cell a decode of [spec] takes: the smallest class that
    // holds its longer side.
    int sizeClassOf(AssetSpec spec) => FrameAtlas.defaultSizeClasses.firstWhere(
      (edge) => edge >= max(spec.pixelWidth, spec.pixelHeight),
    );

    for (final (density, sizeClass) in [(1.0, 64), (3.0, 128)]) {
      testWidgets('decodes the whole cover at its size on the screen, the '
          '$sizeClass class at a density of $density', (tester) async {
        await pump(tester, assets: scope, devicePixelRatio: density);

        final spec = attemptOf(cats).request.spec;
        expect(spec.variant, AssetVariant.full);
        expect(spec.pixelWidth, (26 * density).ceil());
        expect(spec.pixelHeight, (26 * density).ceil());
        expect(sizeClassOf(spec), sizeClass);
      });
    }

    testWidgets('animates by repainting, never rebuilding the tab', (
      tester,
    ) async {
      await pump(tester, assets: scope);
      attemptOf(cats).advance(AssetStage.full, frames: _frames);
      await tester.pump();
      final view = tester.widget(find.byType(ContentView).first);

      await tick(tester, 100);
      await tick(tester, 200);

      expect(tester.widget(find.byType(ContentView).first), same(view));
    });

    testWidgets('stops while the clock is paused and goes on after', (
      tester,
    ) async {
      await pump(tester, assets: scope);
      final cover = attemptOf(cats).advance(AssetStage.full, frames: _frames);
      await tester.pump();
      // Past the fade a cover that arrived after the attach rises in.
      await tester.pump(const Duration(milliseconds: 160));
      final before = cover.paints.length;

      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: true);
      await tick(tester, 100);
      expect(cover.paints.length, before);

      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: false);
      await tick(tester, 200);
      expect(cover.paints.length, before + 1);
    });

    testWidgets('gives the covers back when the strip goes away', (
      tester,
    ) async {
      await pump(tester, assets: scope);
      attemptOf(cats).advance(AssetStage.full, frames: _frames);
      await tester.pump();
      final spec = attemptOf(cats).request.spec;
      expect(ticks.isRunning, isTrue);

      await tester.pumpWidget(const SizedBox());

      expect(scope.isAttached(cats, spec), isFalse);
      expect(scope.isAttached(dogs, spec), isFalse);
      expect(ticks.isRunning, isFalse);
    });

    testWidgets('plays only the covers of the tabs in view', (tester) async {
      handle.entries.value = _entries([
        for (var i = 0; i < 20; i++) _packOf('p$i', ContentKey.document('p$i')),
      ]);
      await pump(tester, assets: scope, width: 200);
      final first = attemptOf(
        const ContentKey.document('p0'),
      ).advance(AssetStage.full, frames: _frames);
      final far = attemptOf(
        const ContentKey.document('p15'),
      ).advance(AssetStage.full, frames: _frames);
      await tester.pump();
      // Past the fade a cover that arrived after the attach rises in.
      await tester.pump(const Duration(milliseconds: 160));
      final farBefore = far.paints.length;
      final firstBefore = first.paints.length;

      await tick(tester, 100);
      expect(first.paints.length, firstBefore + 1);
      expect(far.paints.length, farBefore);

      handle.enter('${const CollectionId.set('p15')}', 15);
      await tester.pumpAndSettle();
      final farInView = far.paints.length;
      final firstGone = first.paints.length;
      await tick(tester, 200);

      expect(far.paints.length, farInView + 1);
      expect(first.paints.length, firstGone);
    });
  });

  testWidgets('puts the mark on the tab at once when motion is off', (
    tester,
  ) async {
    await pump(tester, speed: ChromeMotionSpeed.instant);
    handle.enter('${const CollectionId.set('b')}', 2);
    await tester.pump();

    final mark = tester.getRect(find.byKey(StickerPackStrip.markKey));
    final tab = tester.getRect(find.bySemanticsLabel('Dogs'));
    expect(mark.center.dx, closeTo(tab.center.dx, .5));
  });
}
