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
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show TextTheme, Theme, ThemeData;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
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

const hostFont = 'HostFont';

// `MaterialApp`'s style for text outside any `Material`.
const debugStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 48,
  fontWeight: FontWeight.w900,
);

// The style [text] is drawn in, inherited parts resolved.
TextStyle drawnStyle(WidgetTester tester, Finder text) => tester
    .widget<RichText>(
      find.descendant(of: text, matching: find.byType(RichText)),
    )
    .text
    .style!;

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
    // As a Material app has it: the host's body face in its theme, and over
    // the navigator the framework's debug style, which is all a page outside
    // a `Material` inherits.
    return tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(400, 800),
        child: Theme(
          data: ThemeData(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(fontFamily: hostFont),
            ),
          ),
          child: DefaultTextStyle(
            style: debugStyle,
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
    PackSheetLayerBuilder? layer,
  }) async {
    await pumpHome(tester, touchSlop: touchSlop);
    PackSheet.show(
      home,
      arrangement: arrangement,
      layer: layer,
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

  group('typography', () {
    testWidgets('the title is the chrome face, 20 medium (`bold()`)', (
      tester,
    ) async {
      await open(tester, 'cats');

      final style = drawnStyle(tester, find.text('Pack cats'));
      expect(style.fontFamily, hostFont);
      expect(style.fontSize, 20);
      expect(style.fontWeight, FontWeight.w500);
    });

    testWidgets('the bottom button is the chrome face, 14 medium', (
      tester,
    ) async {
      await open(tester, 'cats');

      final style = drawnStyle(tester, find.text('Add 20 stickers'));
      expect(style.fontFamily, hostFont);
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w500);
    });

    testWidgets('the bottom button and the preview menu '
        'items answer a press with the chrome ink', (tester) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(tester, 'cats', canSend: true, previews: previews);

      Finder inkOf(Finder target) =>
          find.ancestor(of: target, matching: find.byType(ChromeInk));
      expect(inkOf(find.text('Add 20 stickers')), findsOneWidget);

      await tester.tapAt(firstCell(tester));
      await settle(tester);
      for (final label in ['Send Sticker', 'Add to Favorites']) {
        expect(inkOf(find.text(label)), findsOneWidget, reason: label);
      }
    });

    testWidgets('the preview menu is the chrome face, 16 regular, each item '
        'with its icon', (tester) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(tester, 'cats', canSend: true, previews: previews);

      await tester.tapAt(firstCell(tester));
      await settle(tester);

      for (final label in ['Send Sticker', 'Add to Favorites']) {
        final style = drawnStyle(tester, find.text(label));
        expect(style.fontFamily, hostFont, reason: label);
        expect(style.fontSize, 16, reason: label);
        expect(style.fontWeight, FontWeight.w400, reason: label);
      }
      ChromeIcon iconOf(String label) => tester.widget<ChromeIcon>(
        find.descendant(
          of: find
              .ancestor(of: find.text(label), matching: find.byType(Semantics))
              .first,
          matching: find.byType(ChromeIcon),
        ),
      );
      expect(iconOf('Send Sticker').id, ContentPreviewAction.send.icon);
      expect(iconOf('Send Sticker').size, 24);
      expect(
        tester.getTopLeft(find.text('Send Sticker')).dx -
            tester.getTopLeft(find.byWidget(iconOf('Send Sticker'))).dx,
        43,
      );
      expect(
        iconOf('Add to Favorites').id,
        ContentPreviewAction.favourite.icon,
      );
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

    testWidgets('one tap on a sticker is one haptic and one preview opening', (
      tester,
    ) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      var opened = 0;
      previews.isOpen.addListener(() {
        if (previews.isOpen.value) opened++;
      });
      await open(tester, 'cats', canSend: true, previews: previews);

      await tester.tapAt(firstCell(tester));
      await settle(tester);

      expect(find.text('Send Sticker'), findsOneWidget);
      expect(opened, 1);
      expect(haptics, hasLength(1));
    });

    testWidgets('a held sticker is drawn smaller under its preview, the mark '
        'follows the finger, and goes with the preview', (tester) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(tester, 'cats', canSend: true, previews: previews);
      CatalogLeafPreview? mark() => tester
          .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
          .leafPreview;
      expect(mark(), isNull);

      final finger = await tester.startGesture(firstCell(tester));
      await tester.pump(const Duration(milliseconds: 300));
      expect(previews.isOpen.value, isTrue);
      expect(mark()?.shrunk?.index, 0);

      await finger.moveBy(const Offset(76, 0));
      await tester.pump();
      expect(mark()?.shrunk?.index, 1);

      await finger.up();
      await settle(tester);
      expect(previews.isOpen.value, isFalse);
      expect(mark(), isNull);
    });

    testWidgets('a tapped sticker is drawn smaller under its preview', (
      tester,
    ) async {
      final previews = ContentPreviewController(library: library);
      addTearDown(previews.dispose);
      await open(tester, 'cats', canSend: true, previews: previews);

      await tester.tapAt(firstCell(tester));
      await settle(tester);

      expect(
        tester
            .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
            .leafPreview
            ?.shrunk
            ?.index,
        0,
      );
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

  // One owner moves the sheet: a pull past the grid's top, a drag on the
  // header, the release that closes it or springs it back. At the default
  // slop and at a phone's.
  for (final slop in [null, 8.0]) {
    group('dragging the sheet (slop ${slop ?? 'default'})', () {
      // The sheet's translation: its box starts at the top of the screen
      // (tall) or 350 down (short).
      double sheetTop(WidgetTester tester) =>
          tester.getRect(find.byType(PackSheetView)).top;

      double titleCentre(WidgetTester tester) =>
          tester.getCenter(find.text('Pack big')).dy;

      // A finger down at [from] that moves [by] in steps of [step], [gap]
      // apart in event time, and lifts held still unless [lift] is false.
      Future<TestGesture> pull(
        WidgetTester tester,
        Offset from,
        double by, {
        double step = 10,
        Duration gap = const Duration(milliseconds: 16),
        bool lift = true,
      }) async {
        var time = Duration.zero;
        final finger = await tester.startGesture(from);
        for (var moved = 0.0; moved < by.abs(); moved += step) {
          time += gap;
          await finger.moveBy(Offset(0, step * by.sign), timeStamp: time);
          await tester.pump(gap);
        }
        if (lift) {
          // Held still before it lifts: no fling.
          await tester.pump(const Duration(milliseconds: 200));
          await finger.up();
          await settle(tester);
        }
        return finger;
      }

      // The tall sheet's card opens at 320: its header's empty band is
      // right of the title, its grid's first row at 370.
      const header = Offset(300, 345);
      const grid = Offset(200, 600);

      testWidgets('a pull down on the grid at its top lowers the sheet, and '
          'closes it past 0.8 cm', (tester) async {
        await open(tester, 'big', touchSlop: slop);

        final finger = await pull(tester, grid, 120, lift: false);
        expect(sheetTop(tester), greaterThan(60));
        expect(titleCentre(tester), greaterThan(320 + 25 + 60));

        await finger.up();
        await settle(tester);
        expect(sheetUp(), isFalse);
      });

      testWidgets('a pull down on the empty header closes it', (tester) async {
        await open(tester, 'big', touchSlop: slop);

        final finger = await pull(tester, header, 120, lift: false);
        expect(sheetTop(tester), greaterThan(60));

        await finger.up();
        await settle(tester);
        expect(sheetUp(), isFalse);
      });

      testWidgets('a short slow pull springs back', (tester) async {
        await open(tester, 'big', touchSlop: slop);

        await pull(
          tester,
          grid,
          40,
          step: 5,
          gap: const Duration(milliseconds: 50),
        );

        expect(sheetUp(), isTrue);
        expect(sheetTop(tester), 0);
        expect(titleCentre(tester), 320 + 25);
      });

      testWidgets('a fast flick down closes it whatever the distance', (
        tester,
      ) async {
        await open(tester, 'big', touchSlop: slop);

        // 40 down in 8 ms: a pull short of 0.8 cm, at 5000 px/s.
        final finger = await tester.startGesture(grid);
        for (var i = 1; i <= 8; i++) {
          await finger.moveBy(
            const Offset(0, 5),
            timeStamp: Duration(milliseconds: i),
          );
        }
        await finger.up();
        await settle(tester);

        expect(sheetUp(), isFalse);
      });

      testWidgets('a drag up on the empty header raises the card', (
        tester,
      ) async {
        await open(tester, 'big', touchSlop: slop);

        await pull(tester, header, -150);

        expect(sheetUp(), isTrue);
        expect(sheetTop(tester), 0);
        expect(titleCentre(tester), lessThan(320 + 25 - 100));
      });

      for (final (name, from) in [('header', header), ('grid', grid)]) {
        testWidgets('a drag up on the $name first undoes the pull, then '
            'raises the card', (tester) async {
          await open(tester, 'big', touchSlop: slop);

          final finger = await pull(tester, from, 40, lift: false);
          expect(sheetTop(tester), greaterThan(0));
          for (var i = 0; i < 12; i++) {
            await finger.moveBy(const Offset(0, -10));
            await tester.pump();
          }

          expect(sheetTop(tester), 0);
          expect(titleCentre(tester), lessThan(320 + 25 - 40));
          await finger.up();
          await settle(tester);
          expect(sheetUp(), isTrue);
        });
      }

      testWidgets('risen to the top, a pull brings the card back part-way and '
          'moves the sheet on the tick it gets there', (tester) async {
        await open(tester, 'big', touchSlop: slop);
        await pull(tester, grid, -700);
        expect(titleCentre(tester), 25);

        // Ticks that end with the card back part-way and the sheet unmoved:
        // at most the one that lands on the top exactly.
        var unmovedAtTop = 0;
        var time = Duration.zero;
        final finger = await tester.startGesture(grid);
        for (var i = 0; i < 80; i++) {
          time += const Duration(milliseconds: 16);
          await finger.moveBy(const Offset(0, 10), timeStamp: time);
          await tester.pump(const Duration(milliseconds: 16));
          final top = sheetTop(tester);
          if (top == 0 && titleCentre(tester) == 320 + 25) unmovedAtTop++;
        }
        expect(unmovedAtTop, lessThanOrEqualTo(1));
        expect(titleCentre(tester) - sheetTop(tester), 320 + 25);
        expect(sheetTop(tester), greaterThan(60));

        await finger.up();
        await settle(tester);
        expect(sheetUp(), isFalse);
      });

      testWidgets('a fast scroll that runs a little past the top, slowing, '
          'springs back', (tester) async {
        await open(tester, 'big', touchSlop: slop);
        await pull(tester, grid, -200);
        // The grid scrolled about 180 (the slop takes the rest).
        expect(titleCentre(tester), closeTo(320 + 25 - 200, 20));

        // Past the slop slowly, then two ticks 8 ms apart bring the grid to
        // its top and 20 past it, short of 0.8 cm; then the finger slows to
        // 2 px in 16 ms and lifts.
        var time = Duration.zero;
        final finger = await tester.startGesture(grid);
        for (var i = 0; i < 2; i++) {
          time += const Duration(milliseconds: 16);
          await finger.moveBy(const Offset(0, 10), timeStamp: time);
          await tester.pump(const Duration(milliseconds: 16));
        }
        final offset = 320 + 25 - titleCentre(tester);
        for (var i = 0; i < 2; i++) {
          time += const Duration(milliseconds: 8);
          await finger.moveBy(Offset(0, (offset + 20) / 2), timeStamp: time);
        }
        time += const Duration(milliseconds: 16);
        await finger.moveBy(const Offset(0, 2), timeStamp: time);
        await tester.pump();
        expect(
          sheetTop(tester),
          inExclusiveRange(0, PackSheet.dismissDistance),
        );
        await finger.up(timeStamp: time);
        await settle(tester);

        expect(sheetUp(), isTrue);
        expect(sheetTop(tester), 0);
        expect(titleCentre(tester), 320 + 25);
      });

      testWidgets('a short sheet closes under a pull on its grid', (
        tester,
      ) async {
        await open(tester, 'cats', touchSlop: slop);
        expect(sheetTop(tester), 350);

        await pull(tester, const Offset(200, 550), 120);

        expect(sheetUp(), isFalse);
      });
    });
  }

  // A phone's touch slop (8 logical pixels) reaches the widgets through the
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
    testWidgets('its items are the chrome face, each with the preview '
        "menu's icon", (tester) async {
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

      expect(
        drawnStyle(tester, find.text('Send Sticker')).fontFamily,
        hostFont,
      );
      final icons = tester
          .widgetList<ChromeIcon>(
            find.descendant(
              of: find.byType(CatalogContextMenuPanel),
              matching: find.byType(ChromeIcon),
            ),
          )
          .map((icon) => icon.id);
      expect(icons, [
        ContentPreviewAction.send.icon,
        ContentPreviewAction.favourite.icon,
      ]);
    });

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

    testWidgets('under a pointer the box lays five 64 px cells from 19 in, '
        'its grid at most 320 tall, its button 42 tall with the count in a '
        'badge', (tester) async {
      await open(
        tester,
        'big',
        arrangement: PanelArrangement.pointer,
        canSend: true,
      );

      final box = tester.getRect(find.byType(PackSheetView));
      // The header, the grid at its most, the button and its 12 above and
      // below.
      expect(box.height, PackSheetView.headerExtent + 320 + 12 + 42 + 12);
      expect(find.text('Add Stickers'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ChromeBadgeButton.countKey),
          matching: find.text('60'),
        ),
        findsOneWidget,
      );

      // A cell is 64 square from 19 in and 13 under the header: the sixth
      // sticker starts the second row, at the first column's edge.
      await tester.tapAt(box.topLeft + const Offset(19 + 2, 50 + 13 + 64 + 2));
      await settle(tester);
      expect(
        [for (final pick in picks) pick.item.key],
        [const ContentKey.document('big-5')],
      );
    });

    testWidgets('under a pointer a drag neither moves nor closes the box', (
      tester,
    ) async {
      await open(tester, 'cats', arrangement: PanelArrangement.pointer);
      final before = tester.getRect(find.byType(PackSheetView));

      await tester.dragFrom(before.center, const Offset(0, 150));
      await settle(tester);
      await tester.dragFrom(
        before.topCenter + const Offset(0, 25),
        const Offset(0, 150),
      );
      await settle(tester);

      expect(sheetUp(), isTrue);
      expect(tester.getRect(find.byType(PackSheetView)), before);
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

  group('a host layer', () {
    const over = Key('over');
    late ValueListenable<double> bar;
    Widget layer(
      BuildContext context,
      ValueListenable<double> bottom,
      Widget child,
    ) {
      bar = bottom;
      return Stack(
        children: [
          child,
          const Positioned.fill(
            child: IgnorePointer(child: SizedBox(key: over)),
          ),
        ],
      );
    }

    testWidgets('lies over the whole screen above the bottom sheet, which is '
        'still pressed through it, and learns its button bar', (tester) async {
      await open(tester, 'cats', layer: layer);

      expect(
        tester.getRect(find.byKey(over)),
        Offset.zero & const Size(400, 800),
      );
      // The button bar: 48 tall, 8 from every edge of a 64 bar.
      expect(
        bar.value,
        PackSheetView.buttonMetrics.barExtentOf(destructive: false),
      );

      await tester.tap(find.text('Add 20 stickers'));
      await settle(tester);
      expect(edits, hasLength(1));
    });

    testWidgets('does not move with the sheet as it closes', (tester) async {
      await open(tester, 'cats', layer: layer);
      final before = tester.getRect(find.byKey(over));

      Navigator.maybePop(
        tester.element(find.byType(StickerPackSheet)),
      ).ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.getRect(find.byKey(over)), before);
    });

    testWidgets('lies over the whole screen above the box, with no bar', (
      tester,
    ) async {
      await open(
        tester,
        'cats',
        arrangement: PanelArrangement.pointer,
        layer: layer,
      );

      expect(
        tester.getRect(find.byKey(over)),
        Offset.zero & const Size(400, 800),
      );
      expect(bar.value, 0);
    });
  });
}
