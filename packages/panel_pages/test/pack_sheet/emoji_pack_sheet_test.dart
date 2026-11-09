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
    packs = FakePackSource([_pack('a'), _pack('b', count: 20)]);
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
  }) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(400, 800),
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

      // The sheet's own title is empty: each pack has its header.
      expect(find.text('Pack a'), findsNothing);
      expect(find.text('Add 2 emoji packs'), findsOneWidget);
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
}
