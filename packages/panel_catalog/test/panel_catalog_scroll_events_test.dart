/// What the viewport tells its controller: scroll activity (drag, fling,
/// jump, wheel), the quiet-frame settle with the visible keys, and how the
/// controller carries commands across a viewport that is not there yet.
///
/// **Seam:** [PanelCatalogViewport] driven with a
/// [FakeCatalogSnapshotSource]; observed only through the controller's
/// public `events` Observable, `offset` and flags, and the futures its
/// commands return.
library;

import 'package:catalog_assets/legacy_shim.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

// Geometry: 4 columns of 40 px cells under a 24 px header in a 480 px
// viewport. At offset 0 that shows 12 rows, 48 leaves.
const _span = 4;
const _visibleLeaves = 48;

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

ContentKey _key(int i) => ContentKey.unicode(_glyph(i));

CatalogSection _section(String id, int count, {int from = 0}) => CatalogSection(
  id: id,
  title: id,
  leaves: [
    for (var i = from; i < from + count; i++) CatalogLeaf.unicode(_glyph(i)),
  ],
);

/// Index of the first leaf row whose bottom edge is at or below [offset].
int _firstVisibleLeaf(double offset) =>
    (((offset - 24) / 40).ceil() - 1).clamp(0, 1 << 20) * _span;

Widget _app({
  required ValueObservable<CatalogSnapshot> snapshots,
  required PanelCatalogController controller,
  CatalogAssetCache? assetCache,
  void Function(CatalogLeafHit)? onLeafTap,
}) => MaterialApp(
  home: PanelCatalogTheme(
    data: PanelCatalogThemeData.light,
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: 480,
          child: PanelCatalogViewport(
            snapshots: snapshots,
            assetCache: assetCache ?? FakeCatalogAssetCache(),
            controller: controller,
            spanCount: _span,
            cellExtent: 40,
            headerExtent: 24,
            onLeafTap: onLeafTap,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late List<PanelCatalogScrollEvent> events;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    events = [];
    controller.events.addListener(events.add);
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
  });

  Future<void> pumpViewport(WidgetTester tester) =>
      tester.pumpWidget(_app(snapshots: snapshots, controller: controller));

  Offset center(WidgetTester tester) =>
      tester.getCenter(find.byType(PanelCatalogViewport));

  /// The activity facts in order: `true` / `false` for scrolling, `keys` for
  /// a settle.
  List<Object> activity() => [
    for (final event in events)
      if (event is PanelCatalogScrollingChanged)
        event.scrolling
      else if (event is PanelCatalogScrollSettled)
        event.visibleKeys,
  ];

  List<ContentKey> lastSettledKeys() =>
      events.whereType<PanelCatalogScrollSettled>().last.visibleKeys;

  group('settling', () {
    testWidgets('a mounted catalogue settles once with the band in view', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);

      await pumpViewport(tester);

      final settled = events.whereType<PanelCatalogScrollSettled>().single;
      expect(settled.visibleKeys, [
        for (var i = 0; i < _visibleLeaves; i++) _key(i),
      ]);
      expect(events.whereType<PanelCatalogScrollingChanged>(), isEmpty);
    });

    testWidgets('a new snapshot at rest settles again on the new band', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      events.clear();

      snapshots.replaceSections([_section('b', 100, from: 50)]);
      await tester.pump();

      expect(activity(), [
        [for (var i = 50; i < 50 + _visibleLeaves; i++) _key(i)],
      ]);
    });

    testWidgets('an empty catalogue settles with no keys', (tester) async {
      await pumpViewport(tester);

      expect(lastSettledKeys(), isEmpty);
    });

    testWidgets('a tap that never became a drag reports no scrolling', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await tester.pumpWidget(
        _app(snapshots: snapshots, controller: controller, onLeafTap: (_) {}),
      );
      events.clear();

      await tester.tapAt(center(tester));
      await tester.pumpAndSettle();

      expect(events.whereType<PanelCatalogScrollingChanged>(), isEmpty);
      expect(events.whereType<PanelCatalogUserDragCancel>(), isEmpty);
    });
  });

  group('a drag', () {
    testWidgets('reports scrolling at once and settles on the band it left', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      events.clear();

      final gesture = await tester.startGesture(center(tester));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();

      expect(events.first, isA<PanelCatalogUserDragStart>());
      expect(activity(), [true]);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(activity().take(2), [true, false]);
      expect(activity(), hasLength(3));
      final first = _firstVisibleLeaf(controller.offset);
      expect(lastSettledKeys().first, _key(first));
      expect(
        lastSettledKeys(),
        hasLength(greaterThanOrEqualTo(_visibleLeaves)),
      );
    });

    testWidgets('a finger that holds still is not at rest', (tester) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      final gesture = await tester.startGesture(center(tester));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      events.clear();

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(activity(), isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(activity().first, isFalse);
    });

    testWidgets('a viewport that leaves the tree mid-drag reports rest', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      final gesture = await tester.startGesture(center(tester));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      events.clear();

      await tester.pumpWidget(const SizedBox());
      await gesture.cancel();

      expect(activity(), [false]);
    });
  });

  group('other ways to move', () {
    testWidgets('a fling is one stretch of scrolling and one settle', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      events.clear();

      await tester.fling(
        find.byType(PanelCatalogViewport),
        const Offset(0, -300),
        3000,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(activity(), [true]);
      expect(events.whereType<PanelCatalogFlingStart>(), hasLength(1));

      await tester.pumpAndSettle();

      expect(events.whereType<PanelCatalogFlingEnd>(), hasLength(1));
      final facts = activity();
      expect(facts.sublist(0, 2), [true, false]);
      expect(facts, hasLength(3));
      expect(
        lastSettledKeys().first,
        _key(_firstVisibleLeaf(controller.offset)),
      );
    });

    testWidgets('a jump publishes itself, then scrolling, then the settle', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      events.clear();

      controller.jumpTo(24.0 + 40 * 40 + 20);
      await tester.pump();

      // The activity fact is published from inside the jump event's dispatch,
      // so it sits between the two motion events.
      final motion = events.where((e) => e is! PanelCatalogScrollingChanged);
      expect(motion.first, isA<PanelCatalogProgrammaticJump>());
      expect(motion.last, isA<PanelCatalogOffsetChanged>());
      expect(activity(), [true]);

      await tester.pumpAndSettle();

      expect(activity().sublist(0, 2), [true, false]);
      expect(lastSettledKeys().first, _key(40 * _span));
    });

    testWidgets('the wheel moves the catalogue and counts as scrolling', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      events.clear();

      final pointer = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(center(tester));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(controller.offset, 120);
      expect(
        events.whereType<PanelCatalogViewportScrolled>().single.delta,
        120,
      );
      expect(activity(), [true]);

      await tester.pumpAndSettle();
      expect(activity().sublist(0, 2), [true, false]);
    });

    testWidgets('animateTo and a section jump keep scrolling until they end', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 40), _section('b', 200)]);
      await pumpViewport(tester);
      events.clear();

      final animated = controller.animateTo(300);
      await tester.pump(const Duration(milliseconds: 50));
      expect(activity(), [true]);
      expect(events.whereType<PanelCatalogAnimateStart>(), hasLength(1));
      await tester.pumpAndSettle();
      await animated;
      expect(events.whereType<PanelCatalogAnimateEnd>(), hasLength(1));
      expect(activity().sublist(0, 2), [true, false]);

      events.clear();
      final jumped = controller.jumpToSection(1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.isSectionJumpActive, isTrue);
      expect(activity(), [true]);
      await tester.pumpAndSettle();
      await jumped;
      expect(controller.isSectionJumpActive, isFalse);
      expect(activity().sublist(0, 2), [true, false]);
    });
  });

  group('commands given before a viewport is mounted', () {
    testWidgets('jumpTo is where the first frame starts', (tester) async {
      snapshots.replaceSections([_section('a', 300)]);
      controller.jumpTo(24.0 + 40 * 20 + 20);

      await pumpViewport(tester);

      expect(controller.offset, 24.0 + 40 * 20 + 20);
      expect(lastSettledKeys().first, _key(20 * _span));
    });

    testWidgets('animateTo commits its target', (tester) async {
      snapshots.replaceSections([_section('a', 300)]);
      await controller.animateTo(500);

      await pumpViewport(tester);

      expect(controller.offset, 500);
    });

    testWidgets('jumpToSection lands once the first layout is done', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 40), _section('b', 200)]);
      var landed = false;
      controller.jumpToSection(1).then((_) => landed = true);

      await pumpViewport(tester);
      await tester.pumpAndSettle();

      expect(landed, isTrue);
      // Section b's header sits below section a's 10 rows: 24 + 10 * 40.
      expect(controller.offset, 24.0 + 40 * 10);
    });

    testWidgets('a remounted viewport keeps the offset it left at', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      controller.jumpTo(700);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      expect(controller.offset, 700);
      expect(controller.hasPosition, isFalse);

      await pumpViewport(tester);
      expect(controller.offset, 700);
      expect(controller.hasPosition, isTrue);
    });

    testWidgets('the controller reports the viewport geometry while mounted', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 80)]);
      await pumpViewport(tester);

      expect(controller.viewportExtent, 480);
      expect(controller.contentExtent, 824);
      expect(controller.maxScrollExtent, 824 - 480);
    });
  });

  group('a viewport and its controller', () {
    testWidgets('swapping controllers adopts the new one offset', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      final other = PanelCatalogController()..jumpTo(400);
      addTearDown(other.dispose);
      await pumpViewport(tester);
      controller.jumpTo(100);
      await tester.pump();

      await tester.pumpWidget(_app(snapshots: snapshots, controller: other));

      expect(other.offset, 400);
      expect(other.hasPosition, isTrue);
      expect(controller.hasPosition, isFalse);
      expect(controller.offset, 100);
    });

    testWidgets('a disposed controller leaves the viewport usable', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);

      controller.dispose();
      controller.jumpTo(300);
      final gesture = await tester.startGesture(center(tester));
      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());

      expect(tester.takeException(), isNull);
    });

    testWidgets('a batch of snapshots relayouts to the last one', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      events.clear();

      snapshots.batch(() {
        snapshots
          ..replaceSections([_section('b', 8)])
          ..replaceSections([_section('c', 8)])
          ..replaceSections([_section('d', 100, from: 10)]);
      });
      await tester.pump();

      expect(lastSettledKeys().first, _key(10));
      expect(events.whereType<PanelCatalogScrollSettled>(), hasLength(1));
    });

    testWidgets('a listener removed while events dispatch is not called', (
      tester,
    ) async {
      snapshots.replaceSections([_section('a', 300)]);
      await pumpViewport(tester);
      var late = 0;
      void lateListener(PanelCatalogScrollEvent _) => late++;
      void remover(PanelCatalogScrollEvent _) =>
          controller.events.removeListener(lateListener);
      controller.events
        ..addListener(remover)
        ..addListener(lateListener);

      controller.jumpTo(50);

      expect(late, 0);
    });
  });
}
