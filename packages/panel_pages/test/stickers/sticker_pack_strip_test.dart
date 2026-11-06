/// The pack strip of the stickers page: which tabs it shows, which one is
/// active, where a tap lands and how the active mark moves.
///
/// **Seam:** [StickerPackStrip] over a fake [CatalogStripHandle] the test
/// steers (the sections, the catalogue's events, the answer to a jump), under
/// the chrome scopes, observed through the semantics of its tabs, the jumps
/// the handle received and the strip's scroll offset.
library;

import 'dart:async';
import 'dart:ui' show Tristate;

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
            child: StickerPackStrip(handle: handle),
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
