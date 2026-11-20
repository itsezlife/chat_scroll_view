/// The bottom pack sheet's drag owner as its grid sees it: the overscroll
/// sink contract the grid relies on.
///
/// **Seams:** the sink that [PackSheetDragScope] hands a sheet shown with
/// [PackSheet.show], run through `CatalogOverscrollSinkContract`.
library;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/testing.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_drag.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_view.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

void main() {
  group('the sheet’s sink', () {
    CatalogOverscrollSinkContract.run((tester) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final packs = FakePackSource([
        Pack(
          id: const PackId('cats'),
          kind: PackKind.stickers,
          title: 'Cats',
          items: [
            for (var i = 0; i < 4; i++)
              ContentDescriptor(
                key: ContentKey.document('cats-$i'),
                semanticKind: SemanticKind.sticker,
                mediaForm: MediaForm.still,
                pack: const PackId('cats'),
              ),
          ],
        ),
      ]);
      final library = FakeContentLibrary(
        limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
      );
      final assets = ContentAssetScope.withMedia();
      addTearDown(() {
        packs.dispose();
        library.dispose();
        assets.dispose();
      });
      late BuildContext home;
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
        builder: (_) => StickerPackSheet(
          pack: const PackId('cats'),
          packs: packs,
          library: library,
          assets: assets,
          onEditsRequested: (_) {},
        ),
      ).ignore();
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await settle();
      return CatalogOverscrollSinkHarness(
        sink: PackSheetDragScope.maybeOf(
          tester.element(find.byType(PackSheetView)),
        )!,
        settle: settle,
      );
    });
  });
}
