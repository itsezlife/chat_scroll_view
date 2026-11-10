/// The content preview on the GIF page.
///
/// **Seam:** [GifPage] given a [ContentPreviewController] over a
/// [FakeContentLibrary], under an [Overlay], observed through the controller,
/// the menu's texts and the requests the [FakePanelPageHost] received.
/// Geometry: a 400 x 480 page at the window's top left; square clips four to
/// a row of 100 px under a 2 px gap, the first cell's centre at (49, 52).
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/testing.dart';

CollectionItem _gif(String id) => CollectionItem.described(
  ContentDescriptor(
    key: ContentKey.document(id),
    semanticKind: SemanticKind.gif,
    mediaForm: MediaForm.video,
    animated: true,
    size: const ContentSize(128, 128),
  ),
);

const _first = Offset(49, 52);
const _second = Offset(150, 52);

void main() {
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  late FakeContentLibrary library;
  late ContentPreviewController previews;

  setUp(() {
    host = FakePanelPageHost(pageId: 'gif');
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

  Future<void> pumpPage(WidgetTester tester) async {
    final source = FakeCollectionSource([
      FakeCollectionSpec(
        const CollectionId.set('a'),
        pages: FakePages([
          [for (var i = 0; i < 8; i++) _gif('a-$i')],
        ]),
      ),
    ]);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(800, 600),
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  height: 480,
                  child: GifPage(
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
  }

  Future<TestGesture> hold(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(at);
    await tester.pump(ContentPreviewSession.touchHoldDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    await tester.pump(const Duration(milliseconds: 16));
    return gesture;
  }

  // The way out takes the menu's hide, which outlasts the preview's fade,
  // then a frame to leave the overlay.
  Future<void> settleClose(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(AppearMotion$Unfold.hide);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
  }

  testWidgets('a held clip opens the preview; lifting closes it unsent', (
    tester,
  ) async {
    await pumpPage(tester);
    final gesture = await hold(tester, _first);
    expect(previews.isOpen.value, isTrue);

    await gesture.up();
    await settleClose(tester);
    expect(previews.isOpen.value, isFalse);
    expect(host.picks, isEmpty);
  });

  testWidgets('the menu comes after 2 s: send and save, which ask the host', (
    tester,
  ) async {
    await pumpPage(tester);
    final gesture = await hold(tester, _first);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    expect(find.text('Send GIF'), findsNothing);
    await tester.pump(
      ContentPreviewSession.gifMenuDelay -
          ContentPreviewSession.stickerMenuDelay,
    );
    await tester.pump(ContentPreviewSession.showDuration);
    expect(find.text('Send GIF'), findsOneWidget);
    expect(find.text('Save to GIFs'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    await tester.tap(find.text('Save to GIFs'));
    await settleClose(tester);
    expect(host.libraryEditRequests, [
      const LibraryEdit.saveGif(ContentKey.document('a-0')),
    ]);
  });

  testWidgets('a saved clip offers delete', (tester) async {
    library.apply(const LibraryEdit.saveGif(ContentKey.document('a-1')));
    await pumpPage(tester);
    final gesture = await hold(tester, _second);
    await tester.pump(ContentPreviewSession.gifMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);

    expect(find.text('Delete'), findsOneWidget);
    await gesture.up();
  });

  testWidgets('a drag up opens the menu at once; a clip does not switch', (
    tester,
  ) async {
    await pumpPage(tester);
    final gesture = await hold(tester, _first);

    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    expect(find.text('Send GIF'), findsNothing);
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await tester.pump(ContentPreviewSession.showDuration);
    expect(find.text('Send GIF'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(previews.isOpen.value, isTrue);
    await tester.tap(find.text('Send GIF'));
    await settleClose(tester);
    expect(host.picks.single.key, const ContentKey.document('a-0'));
    expect(host.picks.single.kind, SemanticKind.gif);
  });

  testWidgets('once the menu is up, a dragged clip settles back over 350 ms', (
    tester,
  ) async {
    await pumpPage(tester);
    final gesture = await hold(tester, _first);
    final clip = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_PreviewContent',
    );
    final rest = tester.getRect(clip).top;

    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    final dragged = tester.getRect(clip).top;
    expect(dragged, lessThan(rest));

    await tester.pump(ContentPreviewSession.gifSwipeSettle ~/ 2);
    final halfway = tester.getRect(clip).top;
    expect(halfway, greaterThan(dragged));
    expect(halfway, lessThan(rest));

    await tester.pump(ContentPreviewSession.gifSwipeSettle ~/ 2);
    expect(tester.getRect(clip).top, moreOrLessEquals(rest));
    expect(find.text('Send GIF'), findsOneWidget);
    expect(previews.isOpen.value, isTrue);
    await gesture.up();
    await tester.pump();
    expect(previews.isOpen.value, isTrue);
  });

  testWidgets('a drag up past the menu mark plays the clip on, never from '
      'its first frame again', (tester) async {
    final producer = FakeAssetProducer()
      ..onProduce = (attempt) => attempt.advance(
        AssetStage.full,
        frames: List.filled(400, const Duration(milliseconds: 50)),
      );
    assets.dispose();
    assets = PageAssets.createScope(producer: producer);
    // A phone's window, of fractional logical size: the preview's box is
    // computed afresh at each step of the drag.
    tester.view
      ..physicalSize = const Size(1080, 2337)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await pumpPage(tester);
    final gesture = await hold(tester, _first);
    await tester.pump(const Duration(milliseconds: 16));
    final clip = producer.attempts.last.paintables.single;
    expect(clip.rewinds, 1, reason: 'the opening plays from the first frame');

    var frame = clip.frameShown;
    Future<void> playsOn() async {
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(clip.frameShown, greaterThan(frame));
        frame = clip.frameShown;
      }
    }

    await playsOn();
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -7));
      await tester.pump();
      await playsOn();
    }
    expect(find.text('Send GIF'), findsOneWidget);
    await tester.pump(ContentPreviewSession.gifSwipeSettle);
    await playsOn();
    expect(clip.rewinds, 1);

    await gesture.up();
    await tester.pump();
    await playsOn();
    expect(clip.rewinds, 1);
  });

  testWidgets('a right click opens the same items as a context menu', (
    tester,
  ) async {
    await pumpPage(tester);
    final mouse = await tester.startGesture(
      _first,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pump();

    expect(find.text('Send GIF'), findsOneWidget);
    await tester.tap(find.text('Save to GIFs'));
    await tester.pump();
    expect(host.libraryEditRequests, [
      const LibraryEdit.saveGif(ContentKey.document('a-0')),
    ]);
  });
}
