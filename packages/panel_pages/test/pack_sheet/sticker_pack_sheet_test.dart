/// The sticker pack sheet as a user and the host see it.
///
/// **Seam:** [StickerPackSheet] shown with [PackSheet.show] over a navigator
/// under the chrome scopes, with a fake pack source, a fake content library
/// and a real asset scope; observed through what is on screen, the edits
/// and picks the host was asked for, and whether the sheet's route is still
/// up. Geometry: a 400 x 800 screen; under touch the sheet is the full
/// width at the bottom, its 50 px header above five columns of 76 x 82
/// (`(400 - 20) / 5`) inset 10.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_view.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

Pack _pack(
  String id, {
  int count = 20,
  bool official = false,
  PackKind kind = PackKind.stickers,
}) => Pack(
  id: PackId(id),
  kind: kind,
  title: 'Pack $id',
  official: official,
  items: [
    for (var i = 0; i < count; i++)
      ContentDescriptor(
        key: ContentKey.document('$id-$i'),
        semanticKind: kind.itemKind,
        mediaForm: MediaForm.still,
        size: const ContentSize(512, 512),
        spokenName: 'sticker $id $i',
        pack: PackId(id),
      ),
  ],
);

// The stand-ins of stickers nobody decodes shimmer for good, so the sheet
// never settles: run the clock for a while instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakePackSource packs;
  late FakeContentLibrary library;
  late AssetCacheScope assets;
  late List<List<PackEditRequest>> edits;
  late List<PackSheetItem> picks;
  late List<PackLookup> unavailable;
  late List<LibraryEdit> libraryEdits;
  late BuildContext home;

  setUp(() {
    packs = FakePackSource([
      _pack('cats'),
      _pack('official', official: true),
      _pack('big', count: 60),
    ]);
    library = FakeContentLibrary(
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
    );
    assets = PageAssets.createScope();
    edits = [];
    picks = [];
    unavailable = [];
    libraryEdits = [];
    addTearDown(() {
      packs.dispose();
      library.dispose();
      assets.dispose();
    });
  });

  // [touchSlop] is the phone's, as `MediaQuery.fromView` hands it down.
  Future<void> pumpHome(WidgetTester tester, {double? touchSlop}) {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(400, 800),
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            gestureSettings: DeviceGestureSettings(touchSlop: touchSlop),
          ),
          child: Navigator(
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (context, _, _) {
                home = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester,
    String id, {
    bool canSend = false,
    PanelArrangement arrangement = PanelArrangement.touch,
    ContentPreviewController? previews,
    PackSheetLinks? links,
    double? touchSlop,
  }) async {
    await pumpHome(tester, touchSlop: touchSlop);
    PackSheet.show(
      home,
      arrangement: arrangement,
      builder: (_) => StickerPackSheet(
        pack: PackId(id),
        packs: packs,
        library: library,
        assets: assets,
        onEditsRequested: edits.add,
        onPick: canSend ? picks.add : null,
        onUnavailable: unavailable.add,
        previews: previews,
        onLibraryEditRequested: libraryEdits.add,
        links: links,
      ),
    ).ignore();
    await settle(tester);
  }

  bool sheetUp() => find.byType(StickerPackSheet).evaluate().isNotEmpty;

  Offset firstCell(WidgetTester tester) {
    final sheet = tester.getRect(find.byType(PackSheetView));
    return sheet.topLeft + const Offset(10 + 38, 50 + 41);
  }

  group('loading', () {
    testWidgets('shows the pack once it is found', (tester) async {
      packs.gate.pause();
      await open(tester, 'cats');

      expect(find.text('Pack cats'), findsNothing);
      expect(find.text('Add 20 stickers'), findsNothing);

      packs.gate.resume();
      await settle(tester);

      expect(find.text('Pack cats'), findsOneWidget);
      expect(find.text('Add 20 stickers'), findsOneWidget);
    });

    testWidgets('a pack that does not exist closes the sheet and is told', (
      tester,
    ) async {
      await open(tester, 'nope');
      await settle(tester);

      expect(sheetUp(), isFalse);
      expect(unavailable, [PackLookup.notFound]);
    });
  });

  group('the button', () {
    testWidgets('adds a pack not installed and closes the sheet', (
      tester,
    ) async {
      await open(tester, 'cats');

      await tester.tap(find.text('Add 20 stickers'));
      await settle(tester);

      expect(edits.single.single.edit, isA<LibraryEdit$InstallPack>());
      expect(edits.single.single.pack.id, const PackId('cats'));
      expect(sheetUp(), isFalse);
    });

    testWidgets('removes an installed pack', (tester) async {
      library.apply(
        const LibraryEdit.installPack(PackId('cats'), PackKind.stickers),
      );
      await open(tester, 'cats');

      await tester.tap(find.text('Remove 20 stickers'));
      await settle(tester);

      expect(
        edits.single.single.edit,
        const LibraryEdit.removePack(PackId('cats'), PackKind.stickers),
      );
    });

    testWidgets('follows the library while it is up', (tester) async {
      await open(tester, 'cats');

      library.apply(
        const LibraryEdit.installPack(PackId('cats'), PackKind.stickers),
      );
      await settle(tester);

      expect(find.text('Remove 20 stickers'), findsOneWidget);
    });

    testWidgets('archives an installed official pack', (tester) async {
      library.apply(
        const LibraryEdit.installPack(PackId('official'), PackKind.stickers),
      );
      await open(tester, 'official');

      await tester.tap(find.text('Remove 20 stickers'));
      await settle(tester);

      expect(edits.single.single.edit, isA<LibraryEdit$ArchivePack>());
    });
  });

  group('picking', () {
    testWidgets('a tap sends from a sheet opened for a composer', (
      tester,
    ) async {
      await open(tester, 'cats', canSend: true);

      await tester.tapAt(firstCell(tester));
      await settle(tester);

      expect(picks.single.item.key, const ContentKey.document('cats-0'));
      expect(picks.single.pack.id, const PackId('cats'));
      expect(sheetUp(), isFalse);
    });

    testWidgets('without a composer a tap does nothing', (tester) async {
      await open(tester, 'cats');

      await tester.tapAt(firstCell(tester));
      await settle(tester);

      expect(picks, isEmpty);
      expect(sheetUp(), isTrue);
    });

    testWidgets('a held sticker opens its preview', (tester) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(tester, 'cats', canSend: true, previews: previews);

      final gesture = await tester.startGesture(firstCell(tester));
      await tester.pump(const Duration(milliseconds: 300));

      expect(previews.isOpen.value, isTrue);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(picks, isEmpty);
    });

    testWidgets('a tap opens the preview with its menu: Send, favourites, '
        'no View Pack; Send sends and closes the sheet', (tester) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(tester, 'cats', canSend: true, previews: previews);

      await tester.tapAt(firstCell(tester));
      await settle(tester);

      expect(previews.isOpen.value, isTrue);
      expect(find.text('Send Sticker'), findsOneWidget);
      expect(find.text('Add to Favorites'), findsOneWidget);
      expect(find.text('View Pack'), findsNothing);

      await tester.tap(find.text('Send Sticker'));
      await settle(tester);

      expect(picks.single.item.key, const ContentKey.document('cats-0'));
      expect(sheetUp(), isFalse);
    });

    testWidgets('without a composer the preview has no Send', (tester) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(tester, 'cats', previews: previews);

      await tester.tapAt(firstCell(tester));
      await settle(tester);

      expect(find.text('Send Sticker'), findsNothing);
      await tester.tap(find.text('Add to Favorites'));
      await settle(tester);

      expect(libraryEdits, [
        const LibraryEdit.favouriteSticker(ContentKey.document('cats-0')),
      ]);
    });
  });

  group('a tall pack', () {
    // Sixty stickers are twelve rows: the sheet is taller than the screen,
    // so it opens two fifths down (320) and its grid leads by 320.
    double titleCentre(WidgetTester tester) =>
        tester.getCenter(find.text('Pack big')).dy;

    // A finger that moves past the slop first, then [by] up the grid.
    Future<void> scrollGrid(WidgetTester tester, double by) async {
      final finger = await tester.startGesture(const Offset(200, 700));
      await finger.moveBy(const Offset(0, -20));
      await tester.pump();
      for (var moved = 0.0; moved < by; moved += 20) {
        await finger.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      await finger.up();
      await settle(tester);
    }

    testWidgets('opens part-way, its card two fifths down the screen', (
      tester,
    ) async {
      await open(tester, 'big');

      expect(tester.getRect(find.byType(PackSheetView)).top, 0);
      expect(titleCentre(tester), 320 + 25);
    });

    testWidgets('a tap above the card closes the sheet', (tester) async {
      await open(tester, 'big', canSend: true);

      await tester.tapAt(const Offset(200, 100));
      await settle(tester);

      expect(sheetUp(), isFalse);
      expect(picks, isEmpty);
    });

    testWidgets('scrolling the grid raises the card to the top, then the '
        'grid scrolls under the header', (tester) async {
      await open(tester, 'big', canSend: true);

      await scrollGrid(tester, 200);
      expect(titleCentre(tester), closeTo(120 + 25, 1));

      await scrollGrid(tester, 400);
      expect(titleCentre(tester), 25);
      expect(sheetUp(), isTrue);

      // The header stays where it is and nothing under it is a sticker.
      await tester.tapAt(const Offset(10 + 38, 25));
      await settle(tester);
      expect(picks, isEmpty);
    });
  });

  // A phone's touch slop (Android's 8 dp) reaches the widgets through the
  // media query's gesture settings; the grid's own recognizers do not read
  // them.
  group('a finger on a sticker, at a phone slop', () {
    double titleCentre(WidgetTester tester) =>
        tester.getCenter(find.text('Pack big')).dy;

    Future<ContentPreviewController> openBig(WidgetTester tester) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(
        tester,
        'big',
        canSend: true,
        previews: previews,
        touchSlop: 8,
      );
      return previews;
    }

    testWidgets('a drag up raises the sheet, opening no preview', (
      tester,
    ) async {
      final previews = await openBig(tester);
      final top = titleCentre(tester);

      // Down on the first sticker, then up in small steps.
      final finger = await tester.startGesture(Offset(10 + 38, top + 25 + 41));
      for (var i = 0; i < 10; i++) {
        await finger.moveBy(const Offset(0, -4));
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 10; i++) {
        await finger.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.up();
      await settle(tester);

      expect(titleCentre(tester), lessThan(top - 100));
      expect(previews.isOpen.value, isFalse);
      expect(picks, isEmpty);
      expect(sheetUp(), isTrue);
    });

    testWidgets('a hold without moving opens the preview', (tester) async {
      final previews = await openBig(tester);
      final top = titleCentre(tester);

      final finger = await tester.startGesture(Offset(10 + 38, top + 25 + 41));
      await tester.pump(const Duration(milliseconds: 300));

      expect(previews.isOpen.value, isTrue);
      await finger.up();
      await settle(tester);
      expect(picks, isEmpty);
    });
  });

  group('right-click', () {
    testWidgets('on a sticker opens the preview menu, as the panel grid does', (
      tester,
    ) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(
        tester,
        'cats',
        canSend: true,
        previews: previews,
        arrangement: PanelArrangement.pointer,
      );

      await tester.tapAt(
        firstCell(tester),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);

      expect(previews.isOpen.value, isFalse);
      expect(find.text('Send Sticker'), findsOneWidget);
      await tester.tap(find.text('Add to Favorites'));
      await settle(tester);

      expect(libraryEdits, [
        const LibraryEdit.favouriteSticker(ContentKey.document('cats-0')),
      ]);
      expect(sheetUp(), isTrue);
    });

    testWidgets('Send in it sends and closes the sheet', (tester) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(
        tester,
        'cats',
        canSend: true,
        previews: previews,
        arrangement: PanelArrangement.pointer,
      );

      await tester.tapAt(
        firstCell(tester),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);
      await tester.tap(find.text('Send Sticker'));
      await settle(tester);

      expect(picks.single.item.key, const ContentKey.document('cats-0'));
      expect(sheetUp(), isFalse);
    });

    testWidgets('does nothing without previews', (tester) async {
      await open(tester, 'cats', arrangement: PanelArrangement.pointer);

      await tester.tapAt(
        firstCell(tester),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);

      expect(find.text('Add to Favorites'), findsNothing);
    });
  });

  group('the menu', () {
    testWidgets('is there only with a link', (tester) async {
      final shared = <Uri>[];
      await open(
        tester,
        'cats',
        links: PackSheetLinks(
          linkOf: (id) => Uri.parse('https://example.org/${id.value}'),
          onShare: shared.add,
          onCopy: (_) {},
        ),
      );

      await tester.tap(find.bySemanticsLabel('More options'));
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();

      expect(shared, [Uri.parse('https://example.org/cats')]);
    });

    testWidgets('is not there without links', (tester) async {
      await open(tester, 'cats');

      expect(find.bySemanticsLabel('More options'), findsNothing);
    });
  });

  group('arrangement', () {
    testWidgets('on touch the sheet sits at the bottom, full width', (
      tester,
    ) async {
      await open(tester, 'cats');

      final sheet = tester.getRect(find.byType(PackSheetView));
      expect(sheet.width, 400);
      expect(sheet.bottom, 800);
      // Header, four rows of stickers and the filled button's bar.
      expect(sheet.height, 50 + 4 * 82 + 8 + 64);
    });

    testWidgets('a drag down on the header past 0.8 cm dismisses it', (
      tester,
    ) async {
      await open(tester, 'cats');

      final top = tester.getRect(find.byType(PackSheetView)).topCenter;
      await tester.dragFrom(top + const Offset(0, 20), const Offset(0, 80));
      await settle(tester);

      expect(sheetUp(), isFalse);
    });

    testWidgets('a short drag springs back', (tester) async {
      await open(tester, 'cats');

      final before = tester.getRect(find.byType(PackSheetView));
      await tester.timedDragFrom(
        before.topCenter + const Offset(0, 20),
        const Offset(0, 20),
        const Duration(seconds: 1),
      );
      await settle(tester);

      expect(sheetUp(), isTrue);
      expect(tester.getRect(find.byType(PackSheetView)), before);
    });

    testWidgets('under a pointer it is a centred box with a close button', (
      tester,
    ) async {
      await open(tester, 'cats', arrangement: PanelArrangement.pointer);

      final sheet = tester.getRect(find.byType(PackSheetView));
      expect(sheet.width, PackSheet.boxWidth);
      expect(sheet.center, const Offset(200, 400));

      await tester.tap(find.bySemanticsLabel('Close'));
      await settle(tester);

      expect(sheetUp(), isFalse);
    });

    // A host that pauses its animations under modal routes tells the sheet
    // apart by it: the sheet plays its own stickers (ticket 128).
    for (final arrangement in PanelArrangement.values) {
      testWidgets('the ${arrangement.name} route is named for the sheet', (
        tester,
      ) async {
        await open(tester, 'cats', arrangement: arrangement);

        final route = ModalRoute.of(
          tester.element(find.byType(StickerPackSheet)),
        )!;
        expect(route.settings.name, PackSheet.routeName);
      });
    }
  });
}
