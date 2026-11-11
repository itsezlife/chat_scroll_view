/// The content preview on the stickers page, as a finger and a mouse use it.
///
/// **Seam:** [StickersPage] given a [ContentPreviewController] over a
/// [FakeContentLibrary], under an [Overlay] the preview is shown in, observed
/// through the controller, the [ContentView] the preview draws and the
/// requests the [FakePanelPageHost] received. Geometry: a 360 x 480 page in
/// an 800 x 600 window, the 36 px strip above, packs of 10 stickers in 5
/// columns of 72 x 82 under a 27 px header.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

CollectionItem _sticker(String id, {PackId? pack}) => CollectionItem.described(
  ContentDescriptor(
    key: ContentKey.document(id),
    semanticKind: SemanticKind.sticker,
    mediaForm: MediaForm.still,
    size: const ContentSize(512, 512),
    pack: pack,
  ),
);

FakeCollectionSpec _pack(String id, {bool packed = true}) => FakeCollectionSpec(
  CollectionId.set(id),
  metadata: CollectionMetadata(title: id),
  pages: FakePages([
    [
      for (var i = 0; i < 10; i++)
        _sticker('$id-$i', pack: packed ? PackId(id) : null),
    ],
  ]),
);

FakeCollectionSpec _recents() => FakeCollectionSpec(
  CollectionId.recent,
  pages: FakePages([
    [_sticker('a-3', pack: const PackId('a'))],
  ]),
);

Finder _previewOf(String id) => find.byWidgetPredicate(
  (widget) =>
      widget is ContentView && widget.content == ContentKey.document(id),
);

void main() {
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  late FakeContentLibrary library;
  late ContentPreviewController previews;

  setUp(() {
    host = FakePanelPageHost(pageId: 'stickers');
    assets = PageAssets.createScope();
    library = FakeContentLibrary(
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
    );
    previews = ContentPreviewController(library: library);
    addTearDown(() {
      previews.dispose();
      library.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Future<FakeCollectionSource> pumpPage(
    WidgetTester tester, {
    List<FakeCollectionSpec>? specs,
    PanelArrangement arrangement = PanelArrangement.touch,
  }) async {
    final source = FakeCollectionSource(specs ?? [_pack('a'), _pack('b')]);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(800, 600),
        child: PanelArrangementScope(
          arrangement: arrangement,
          child: BackdropSnapshotSource(
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Center(
                    child: SizedBox(
                      width: 360,
                      height: 480,
                      child: StickersPage(
                        host: host,
                        source: source,
                        assets: assets,
                        previews: previews,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return source;
  }

  // The centre of cell [index] of the first section.
  Offset cell(WidgetTester tester, int index) {
    final origin = tester.getTopLeft(find.byType(StickersPage));
    return origin +
        Offset(72 * (index % 5 + .5), 36 + 27 + 82 * (index ~/ 5) + 41);
  }

  // The way out takes the menu's hide, which outlasts the preview's fade,
  // then a frame to leave the overlay.
  Future<void> settleClose(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(AppearMotion$Unfold.hide);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
  }

  Future<TestGesture> hold(WidgetTester tester, int index) async {
    final gesture = await tester.startGesture(cell(tester, index));
    await tester.pump(ContentPreviewSession.touchHoldDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    await tester.pump(const Duration(milliseconds: 16));
    return gesture;
  }

  testWidgets('a press held 200 ms opens the preview of the sticker', (
    tester,
  ) async {
    await pumpPage(tester);
    final gesture = await tester.startGesture(cell(tester, 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(previews.isOpen.value, isFalse);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(ContentPreviewSession.showDuration);

    expect(previews.isOpen.value, isTrue);
    expect(_previewOf('a-1'), findsOneWidget);
    // The square is M / 1.8 of the window: 600 / 1.8.
    expect(tester.getSize(_previewOf('a-1')).width, closeTo(600 / 1.8, 0.01));
    expect(host.activeHolds, 1);
    await gesture.up();
  });

  testWidgets('lifting before the menu closes it without a pick', (
    tester,
  ) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 1);

    await gesture.up();
    await settleClose(tester);

    expect(previews.isOpen.value, isFalse);
    expect(_previewOf('a-1'), findsNothing);
    expect(host.picks, isEmpty);
    expect(host.activeHolds, 0);
  });

  testWidgets('the menu comes after 1300 ms and stays after the lift; an '
      'item asks the host and closes the preview', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 2);
    expect(find.text('Send Sticker'), findsNothing);

    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    expect(find.text('Send Sticker'), findsOneWidget);
    expect(find.text('Add to Favorites'), findsOneWidget);
    expect(find.text('View Pack'), findsOneWidget);
    expect(find.text('Delete from Recent'), findsNothing);

    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);
    expect(previews.isOpen.value, isTrue);

    await tester.tap(find.text('Add to Favorites'));
    await settleClose(tester);

    expect(host.libraryEditRequests, [
      const LibraryEdit.favouriteSticker(ContentKey.document('a-2')),
    ]);
    expect(previews.isOpen.value, isFalse);
  });

  testWidgets('View Pack asks for the pack; Send picks the sticker', (
    tester,
  ) async {
    await pumpPage(tester);
    var gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);
    await tester.tap(find.text('View Pack'));
    await settleClose(tester);
    expect(host.packRequests, [const PackId('a')]);

    gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);
    await tester.tap(find.text('Send Sticker'));
    await settleClose(tester);
    expect(host.picks.single.key, const ContentKey.document('a-0'));
    expect(host.picks.single.kind, SemanticKind.sticker);
  });

  testWidgets('a favourite offers to come out of the favourites', (
    tester,
  ) async {
    library.apply(
      const LibraryEdit.favouriteSticker(ContentKey.document('a-0')),
    );
    await pumpPage(tester);
    final gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);

    expect(find.text('Delete from Favorites'), findsOneWidget);
    await gesture.up();
  });

  testWidgets('in the recents the menu offers to delete it from there', (
    tester,
  ) async {
    await pumpPage(tester, specs: [_recents(), _pack('a')]);
    final gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);

    await tester.tap(find.text('Delete from Recent'));
    await settleClose(tester);
    expect(host.libraryEditRequests, [
      const LibraryEdit.removeRecentSticker(ContentKey.document('a-3')),
    ]);
  });

  testWidgets('sliding onto another sticker shows that one', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 1);

    await gesture.moveTo(cell(tester, 3));
    await tester.pump();

    expect(_previewOf('a-3'), findsOneWidget);
    expect(_previewOf('a-1'), findsNothing);
    await gesture.up();
  });

  testWidgets('the grid marks no cell pressed under the preview and draws '
      'the previewed one smaller, following the finger', (tester) async {
    await pumpPage(tester);
    CatalogLeafPreview? mark() => tester
        .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport).last)
        .leafPreview;
    final gesture = await hold(tester, 1);
    expect(mark()?.shrunk?.index, 1);

    await gesture.moveTo(cell(tester, 3));
    await tester.pump();
    expect(mark()?.shrunk?.index, 3);

    await gesture.up();
    await settleClose(tester);
    expect(mark(), isNull);
  });

  testWidgets('while it is open everything else the scope draws is held, '
      'and plays again from the close; the preview is in the foreground', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(assets.isBackgroundHeld, isFalse);
    final gesture = await hold(tester, 1);

    expect(assets.isBackgroundHeld, isTrue);
    final preview = tester.widget<ContentView>(_previewOf('a-1'));
    expect(preview.preset.profile.foreground, isTrue);

    await gesture.moveTo(cell(tester, 3));
    await tester.pump();
    expect(assets.isBackgroundHeld, isTrue, reason: 'one hold per preview');

    await gesture.up();
    await tester.pump();
    expect(assets.isBackgroundHeld, isFalse, reason: 'as the close starts');
    await settleClose(tester);
    expect(assets.isBackgroundHeld, isFalse);
  });

  testWidgets('a sticker of no pack has no menu while the finger is down', (
    tester,
  ) async {
    await pumpPage(tester, specs: [_pack('a', packed: false)]);
    final gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);

    expect(find.text('Send Sticker'), findsNothing);
    await gesture.up();
  });

  testWidgets('the host closes it on back, menu and all', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);

    expect(previews.dismiss(), isTrue);
    await settleClose(tester);
    expect(previews.isOpen.value, isFalse);
    expect(find.text('Send Sticker'), findsNothing);
    expect(previews.dismiss(), isFalse);
  });

  testWidgets('the menu goes with the preview: its hide starts on the same '
      'frame, and the preview stays until it is over', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    AppearFrame menuFrame() => tester
        .widget<AppearFrameView>(
          find.ancestor(
            of: find.text('Send Sticker'),
            matching: find.byType(AppearFrameView),
          ),
        )
        .frame;
    expect(menuFrame(), AppearFrame.rest);

    const motion = AppearMotion.unfold();
    final hide = motion.hideDuration(ChromeMotionData.standard);
    expect(previews.dismiss(), isTrue);
    await tester.pump();
    await tester.pump(hide ~/ 2);
    expect(menuFrame(), motion.hideAt(0.5));

    // Past the preview's own fade, the menu is still going.
    await tester.pump(hide ~/ 2 - const Duration(milliseconds: 10));
    expect(find.text('Send Sticker'), findsOneWidget);
    expect(menuFrame().opacity, lessThan(0.05));

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.text('Send Sticker'), findsNothing);
    expect(previews.isOpen.value, isFalse);
  });

  testWidgets('a press elsewhere closes it after the menu', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);

    await tester.tapAt(const Offset(10, 10));
    await settleClose(tester);
    expect(previews.isOpen.value, isFalse);
    expect(host.picks, isEmpty);
  });

  testWidgets('a mouse held 500 ms previews with no menu; lifting closes '
      'it', (tester) async {
    await pumpPage(tester);
    final mouse = await tester.startGesture(
      cell(tester, 1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(previews.isOpen.value, isFalse);
    await tester.pump(const Duration(milliseconds: 250));
    expect(previews.isOpen.value, isTrue);

    await tester.pump(ContentPreviewSession.gifMenuDelay);
    expect(find.text('Send Sticker'), findsNothing);

    await mouse.up();
    await settleClose(tester);
    expect(previews.isOpen.value, isFalse);
  });

  testWidgets('a mouse preview is a square of 224 in the middle of the '
      'window, fading in over 150 ms without a scale', (tester) async {
    await pumpPage(tester);
    final mouse = await tester.startGesture(
      cell(tester, 1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(ContentPreviewSession.pointerHoldDelay);
    await tester.pump(const Duration(milliseconds: 75));

    final preview = _previewOf('a-1');
    expect(
      tester.getRect(preview),
      Rect.fromCenter(center: const Offset(400, 300), width: 224, height: 224),
    );
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: preview, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, closeTo(0.5, 0.05));

    await mouse.up();
    await settleClose(tester);
  });

  // --- The blur under the menu ---------------------------------------------

  Finder backdrop() => find.byType(BackdropSnapshotView);
  BackdropSnapshot snapshotShown(WidgetTester tester) =>
      tester.widget<BackdropSnapshotView>(backdrop()).snapshot;

  testWidgets('the blur under the menu is one still, taken as the preview '
      'opens, faded in and out by its opacity alone, and let go on close', (
    tester,
  ) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 2);
    // Taken already, not shown until the menu.
    expect(backdrop(), findsNothing);

    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration ~/ 2);
    final snapshot = snapshotShown(tester);
    final half = tester.widget<RawImage>(
      find.descendant(of: backdrop(), matching: find.byType(RawImage)),
    );
    expect(half.opacity!.value, closeTo(0.5, 0.1));
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pump(ContentPreviewSession.showDuration);
    expect(
      tester
          .widget<RawImage>(
            find.descendant(of: backdrop(), matching: find.byType(RawImage)),
          )
          .opacity!
          .value,
      1,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    // 1/15 of the 800 x 600 window at a device pixel ratio of 3.
    expect(snapshot.image.width, 160);

    await gesture.up();
    await tester.pump(ContentPreviewSession.showDuration);
    expect(previews.dismiss(), isTrue);
    await tester.pump();
    await tester.pump(ContentPreviewSession.showDuration ~/ 2);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(snapshot.isDisposed, isFalse);

    await settleClose(tester);
    expect(previews.isOpen.value, isFalse);
    expect(snapshot.isDisposed, isTrue);
  });

  testWidgets('a menu that goes and comes back as the finger slides shows '
      'the same still', (tester) async {
    await pumpPage(tester);
    final gesture = await hold(tester, 0);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    final first = snapshotShown(tester);

    await gesture.moveTo(cell(tester, 1));
    await tester.pump();
    await tester.pump(ContentPreviewSession.showDuration);
    expect(backdrop(), findsNothing);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    expect(snapshotShown(tester), same(first));
    expect(first.isDisposed, isFalse);

    await gesture.up();
    expect(previews.dismiss(), isTrue);
    await settleClose(tester);
    expect(first.isDisposed, isTrue);
  });

  testWidgets('with the blur off the menu is over the dim alone', (
    tester,
  ) async {
    previews.blursBackground = false;
    await pumpPage(tester);
    final gesture = await hold(tester, 2);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    expect(find.text('Send Sticker'), findsOneWidget);
    expect(backdrop(), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    await gesture.up();
    expect(previews.dismiss(), isTrue);
    await settleClose(tester);
  });

  testWidgets('a host with no snapshot source gets the dim alone', (
    tester,
  ) async {
    final source = FakeCollectionSource([_pack('a')]);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(800, 600),
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => Center(
                child: SizedBox(
                  width: 360,
                  height: 480,
                  child: StickersPage(
                    host: host,
                    source: source,
                    assets: assets,
                    previews: previews,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final gesture = await hold(tester, 2);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    expect(find.text('Send Sticker'), findsOneWidget);
    expect(backdrop(), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    await gesture.up();
    expect(previews.dismiss(), isTrue);
    await settleClose(tester);
  });

  testWidgets('without a controller a long press does nothing', (tester) async {
    final policy = StickersPagePolicy(assets: assets, host: host);
    final hit = CatalogLeafHit(
      sectionId: const CollectionId.set('a').toString(),
      index: 0,
      leaf: const CatalogLeaf(
        key: ContentKey.document('a-0'),
        semanticKind: SemanticKind.sticker,
      ),
    );
    final source = FakeCollectionSource([_pack('a')]);
    addTearDown(source.dispose);
    final collection = source.collections.value.first;
    expect(policy.hasLongPress(hit, collection), isFalse);
  });

  group('the right click under the pointer arrangement', () {
    test('lists the preview\'s items, which ask the host', () {
      final policy = StickersPagePolicy(
        assets: assets,
        host: host,
        previews: previews,
      );
      final source = FakeCollectionSource([_pack('a')]);
      addTearDown(source.dispose);
      final collection = source.collections.value.first;
      final hit = CatalogLeafHit(
        sectionId: policy.sectionIdOf(collection),
        index: 0,
        leaf: policy.leafOf(
          _sticker('a-0', pack: const PackId('a')),
          collection,
        ),
      );

      final entries = policy.menuOf(
        hit,
        collection,
        ChromeStringsPresets.english.panel,
        arrangement: PanelArrangement.pointer,
      );
      expect(
        [for (final entry in entries.cast<CatalogMenuItem>()) entry.label],
        ['Send Sticker', 'Add to Favorites', 'View Pack'],
      );

      policy.onMenuAction(hit, collection, 'view-pack', host);
      expect(host.packRequests, [const PackId('a')]);
    });
  });
}
