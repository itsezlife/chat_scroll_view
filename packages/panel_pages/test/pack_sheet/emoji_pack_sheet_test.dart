/// The emoji pack sheet, of one pack and of several, as a user and the host
/// see it.
///
/// **Seam:** [EmojiPackSheet] shown with [PackSheet.show] over a navigator
/// under the chrome scopes, with a fake pack source, a fake content library
/// and a real asset scope; observed through what is on screen and the edits
/// and picks the host was asked for. Geometry: a 400 x 800 screen; the grid
/// is inset 10 under a 50 px header, so a sheet of several packs has eight
/// 47.5 px columns under 56 px pack headers.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_view.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

Pack _pack(String id, {int count = 32}) => Pack(
  id: PackId(id),
  kind: PackKind.emoji,
  title: 'Pack $id',
  items: [
    for (var i = 0; i < count; i++)
      ContentDescriptor(
        key: ContentKey.document('$id-$i'),
        semanticKind: SemanticKind.customEmoji,
        mediaForm: MediaForm.still,
        size: const ContentSize(100, 100),
        pack: PackId(id),
      ),
  ],
);

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
  late BuildContext home;

  setUp(() {
    packs = FakePackSource([
      _pack('a'),
      _pack('b', count: 20),
      _pack('big', count: 400),
    ]);
    library = FakeContentLibrary(
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
    );
    assets = PageAssets.createScope();
    edits = [];
    picks = [];
    addTearDown(() {
      packs.dispose();
      library.dispose();
      assets.dispose();
    });
  });

  Future<void> open(
    WidgetTester tester,
    List<String> ids, {
    bool canInsert = false,
    ContentKey? previewEmoji,
    Size screen = const Size(400, 800),
  }) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PanelShellTestScope(
        size: screen,
        child: Navigator(
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (context, _, _) {
              home = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    PackSheet.show(
      home,
      arrangement: PanelArrangement.touch,
      builder: (_) => EmojiPackSheet(
        packIds: [for (final id in ids) PackId(id)],
        packs: packs,
        library: library,
        assets: assets,
        onEditsRequested: edits.add,
        onPick: canInsert ? picks.add : null,
        previewEmoji: previewEmoji,
      ),
    ).ignore();
    await settle(tester);
  }

  bool sheetUp() => find.byType(EmojiPackSheet).evaluate().isNotEmpty;

  Rect sheet(WidgetTester tester) => tester.getRect(find.byType(PackSheetView));

  group('one pack', () {
    testWidgets('shows its title and offers to add its emoji', (tester) async {
      await open(tester, ['a']);

      expect(find.text('Pack a'), findsOneWidget);
      expect(find.text('Add 32 emoji'), findsOneWidget);
    });

    testWidgets('a tap inserts the emoji when opened for a composer', (
      tester,
    ) async {
      await open(tester, ['a'], canInsert: true);

      // Eight columns of 47.5 fit the 380 px row at least 45 wide.
      await tester.tapAt(
        sheet(tester).topLeft + const Offset(10 + 23, 50 + 23),
      );
      await settle(tester);

      expect(picks.single.item.key, const ContentKey.document('a-0'));
      expect(sheetUp(), isFalse);
    });
  });

  group('several packs', () {
    testWidgets('each pack has its title and its own button', (tester) async {
      await open(tester, ['a', 'b']);

      // The sheet's own title is empty: each pack has its header, with its
      // count under its title and an Add pill.
      expect(find.text('Pack a'), findsOneWidget);
      expect(find.text('32 emoji'), findsOneWidget);
      expect(find.text('Pack b'), findsOneWidget);
      expect(find.text('20 emoji'), findsOneWidget);
      expect(find.text('Add'), findsNWidgets(2));
      expect(find.text('Add 2 emoji packs'), findsOneWidget);
    });

    testWidgets('a pack header sits over its rows: 56 tall, the first row '
        'under it', (tester) async {
      await open(tester, ['a', 'b']);

      final top = sheet(tester).top + 50;
      // Title 17 at 10 down, the count 13 at 31.66 down.
      expect(tester.getTopLeft(find.text('Pack a')).dy, closeTo(top + 10, 1));
      expect(
        tester.getTopLeft(find.text('32 emoji')).dy,
        closeTo(top + 31.66, 1),
      );
      // The second pack's header is under the first pack's two rows.
      expect(
        tester.getTopLeft(find.text('Pack b')).dy,
        closeTo(top + 56 + 2 * 47.5 + 10, 1),
      );
    });

    testWidgets("a header's button turns to Remove once its pack is added", (
      tester,
    ) async {
      await open(tester, ['a', 'b']);

      library.apply(const LibraryEdit.installPack(PackId('a'), PackKind.emoji));
      await settle(tester);

      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await settle(tester);

      expect(
        edits.single.single.edit,
        const LibraryEdit.removePack(PackId('a'), PackKind.emoji),
      );
      expect(sheetUp(), isTrue);
    });

    testWidgets('a pack header button adds that pack and leaves the sheet up', (
      tester,
    ) async {
      await open(tester, ['a', 'b']);

      await tester.tapAt(
        sheet(tester).topRight + const Offset(-10 - 20, 50 + 28),
      );
      await settle(tester);

      expect(
        edits.single.single.edit,
        const LibraryEdit.installPack(PackId('a'), PackKind.emoji),
      );
      expect(sheetUp(), isTrue);
    });

    testWidgets('once one is installed the button adds the other', (
      tester,
    ) async {
      library.apply(const LibraryEdit.installPack(PackId('a'), PackKind.emoji));
      await open(tester, ['a', 'b']);

      expect(find.text('Add 20 emoji'), findsOneWidget);
    });

    testWidgets('with all installed the button removes them all', (
      tester,
    ) async {
      for (final id in ['a', 'b']) {
        library.apply(LibraryEdit.installPack(PackId(id), PackKind.emoji));
      }
      await open(tester, ['a', 'b']);

      await tester.tap(find.text('Remove 2 emoji packs'));
      await settle(tester);

      expect(edits.single.map((r) => r.pack.id), [
        const PackId('a'),
        const PackId('b'),
      ]);
      expect(sheetUp(), isFalse);
    });

    testWidgets('a tap on an emoji shows its pack alone', (tester) async {
      await open(tester, ['a', 'b'], canInsert: true);

      await tester.tapAt(
        sheet(tester).topLeft + const Offset(10 + 23, 50 + 56 + 23),
      );
      await settle(tester);

      expect(picks, isEmpty);
      expect(find.text('Pack a'), findsOneWidget);
      expect(find.text('Add 32 emoji'), findsOneWidget);
    });
  });

  // The emoji sheets keep their swipe to close: the same owner as the
  // sticker sheet's.
  group('dragging the sheet', () {
    // A finger down at [from] that moves [by] in steps of 10, 16 ms apart,
    // and lifts held still.
    Future<void> pull(WidgetTester tester, Offset from, double by) async {
      var time = Duration.zero;
      final finger = await tester.startGesture(from);
      for (var moved = 0.0; moved < by.abs(); moved += 10) {
        time += const Duration(milliseconds: 16);
        await finger.moveBy(Offset(0, 10 * by.sign), timeStamp: time);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 200));
      await finger.up();
      await settle(tester);
    }

    // Four hundred emoji: the card opens 0.56 down (448), its header's
    // empty band right of the title.
    testWidgets('a pull down on the grid at its top closes a tall sheet', (
      tester,
    ) async {
      await open(tester, ['big']);

      await pull(tester, const Offset(200, 650), 120);

      expect(sheetUp(), isFalse);
    });

    testWidgets('a pull down on the empty header closes it', (tester) async {
      await open(tester, ['big']);

      await pull(tester, const Offset(300, 448 + 25), 120);

      expect(sheetUp(), isFalse);
    });

    testWidgets('a drag up on the empty header raises the card', (
      tester,
    ) async {
      await open(tester, ['big']);

      await pull(tester, const Offset(300, 448 + 25), -150);

      expect(sheetUp(), isTrue);
      expect(sheet(tester).top, 0);
      expect(
        tester.getCenter(find.text('Pack big')).dy,
        lessThan(448 + 25 - 100),
      );
    });

    testWidgets('a short sheet closes under a pull on its grid', (
      tester,
    ) async {
      await open(tester, ['a']);
      final grid = sheet(tester).center;

      await pull(tester, grid, 120);

      expect(sheetUp(), isFalse);
    });
  });

  group('the preview emoji', () {
    // The emoji tapped in a message, drawn 140 large 20 above the card.
    Finder preview() => find.byWidgetPredicate(
      (widget) =>
          widget is ContentView &&
          widget.content == const ContentKey.document('a-3'),
    );

    testWidgets('is drawn 140 large, 20 above the card, centred', (
      tester,
    ) async {
      await open(tester, ['a'], previewEmoji: const ContentKey.document('a-3'));

      final card = sheet(tester).top;
      final rect = tester.getRect(preview());
      expect(rect.size, const Size(140, 140));
      expect(rect.bottom, card - 20);
      expect(rect.center.dx, 200);
    });

    testWidgets('fades out once the user scrolls the grid', (tester) async {
      await open(tester, [
        'big',
      ], previewEmoji: const ContentKey.document('a-3'));
      expect(preview(), findsOneWidget);

      final finger = await tester.startGesture(const Offset(200, 700));
      for (var i = 0; i < 4; i++) {
        await finger.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      await finger.up();
      await settle(tester);

      expect(preview(), findsNothing);
    });

    testWidgets('is not drawn without 160 of room above the card', (
      tester,
    ) async {
      // Landscape: the card opens 0.3 of 300 down.
      await open(
        tester,
        ['a'],
        previewEmoji: const ContentKey.document('a-3'),
        screen: const Size(400, 300),
      );

      expect(preview(), findsNothing);
    });
  });
}
