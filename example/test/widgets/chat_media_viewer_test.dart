/// The chat's media viewer: it hides the item it shows in the chat through
/// the chat's media state, plays videos on the host's players, and draws the
/// host's chrome (title, date, caption, strip, actions) with the chat's
/// actions as protection allows them.
///
/// **Seam:** `ChatMediaViewer` (its origin bridge, its actions, and the
/// viewer it pushes), over a `ContentAssetScope` with a `FakeAssetProducer`
/// and a `PlayerPool` over a `FakePlayerBackend`.
library;

import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/data/demo_photos.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_media_host.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart' show AssetCacheProvider;
import 'package:mpx_core/testing.dart';
import 'package:mpx_player/mpx_player.dart' show PlayerPool;
import 'package:mpx_player/testing.dart';
import 'package:mpx_ui/mpx_ui.dart';

void main() {
  final photo = MediaItem(
    id: const MediaItemId('7.0'),
    descriptor: DemoPhotos.harbour.descriptor,
  );
  final second = MediaItem(
    id: const MediaItemId('7.1'),
    descriptor: DemoPhotos.meadow.descriptor,
  );
  final file = MediaItem(
    id: const MediaItemId('7.2'),
    descriptor: DemoPhotos.cliff.descriptor,
    kind: MediaItemKind.file,
  );

  MediaViewerRequest requestOf(List<MediaItem> items, int index) =>
      MediaViewerRequest(
        messageId: 7,
        items: [for (final item in items) item.id],
        index: index,
        originRect: const Rect.fromLTWH(10, 10, 100, 100),
        rectOf: (_) => null,
      );

  group('source hide', () {
    late MessageMediaState state;

    setUp(() {
      state = MessageMediaState();
      addTearDown(state.dispose);
    });

    test('the bridge hides and covers the item the viewer shows, by its id, '
        'and the hidden one follows the page', () {
      final bridge = ChatMediaViewer.bridgeOf(
        requestOf([photo, file, second], 0),
        [photo, file, second],
        state: state,
      )..setHidden(0, hidden: true);
      expect(state.isViewerHidden(photo.id), isTrue);

      // The viewer pages to the second picture (the file is not a page).
      bridge
        ..setHidden(0, hidden: false)
        ..setHidden(1, hidden: true)
        ..setCovered(1, covered: true);
      expect(state.isViewerHidden(photo.id), isFalse);
      expect(state.isViewerHidden(second.id), isTrue);
      expect(state.of(second.id).value.viewerCovered, isTrue);
      expect(state.isViewerHidden(file.id), isFalse);

      bridge
        ..setHidden(1, hidden: false)
        ..setCovered(1, covered: false);
      expect(state.of(second.id).value.overlaysShown, isTrue);
    });
  });

  group('actions', () {
    List<String> labelsOf(List<ViewerAction> actions) => [
      for (final action in actions) action.label,
    ];

    test('save says its entry\'s label where it has one, share follows what '
        'protection allows, forward and delete what the chat allows; each '
        'reaches the host with its item', () {
      final chosen = <(MediaItem, ChatViewerAction)>[];
      final open = ChatMediaViewer.actionsFor(
        photo,
        allowed: const {MediaItemAction.saveToGallery, MediaItemAction.share},
        saveLabel: 'Save Image As…',
        canForward: true,
        canDelete: true,
        onAction: (item, action) => chosen.add((item, action)),
      );
      expect(labelsOf(open), ['Forward', 'Delete', 'Save Image As…', 'Share']);
      expect([for (final a in open) a.inBar], [true, true, false, false]);

      open.first.onSelected(
        ViewerActionRequest(
          index: 0,
          item: GalleryItem(photo.descriptor.key.mediaKey),
          openFile: () async => null,
          captureFrame: () async => null,
        ),
      );
      expect(chosen, [(photo, ChatViewerAction.forward)]);
      open[2].onSelected(
        ViewerActionRequest(
          index: 0,
          item: GalleryItem(photo.descriptor.key.mediaKey),
          openFile: () async => null,
          captureFrame: () async => null,
        ),
      );
      expect(chosen.last, (photo, ChatViewerAction.save));

      final protectedActions = ChatMediaViewer.actionsFor(
        photo,
        allowed: const {},
        canForward: false,
        canDelete: true,
        onAction: (_, _) {},
      );
      expect(labelsOf(protectedActions), ['Delete']);
    });
  });

  group('viewer', () {
    late ContentAssetScope scope;
    late PlayerPool players;

    setUp(() {
      scope = ContentAssetScope.withMedia(producer: FakeAssetProducer());
      players = PlayerPool(backend: FakePlayerBackend());
      addTearDown(scope.dispose);
      addTearDown(players.dispose);
    });

    testWidgets('it plays on the host\'s players and draws the host\'s '
        'chrome: title, date, caption, the strip for an album, and the '
        'actions of the item shown', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ChromeThemeScope(
            palette: const ChromePalette.dark(),
            child: child!,
          ),
          home: AssetCacheProvider(
            scope: scope.media,
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final items = [photo, second];
      unawaited(
        ChatMediaViewer.open(
          context,
          requestOf(items, 1),
          items,
          players: players,
          details: ChatViewerDetails(
            title: 'Ada',
            subtitle: 'today at 12:00',
            caption: 'Two of them',
            actionsOf: (item) => ChatMediaViewer.actionsFor(
              item,
              allowed: const {MediaItemAction.saveToGallery},
              saveLabel: 'Save to Gallery',
              canForward: true,
              canDelete: false,
              onAction: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final viewer = tester.widget<MediaViewer>(find.byType(MediaViewer));
      expect(viewer.players, same(players));
      expect(viewer.initialIndex, 1);
      final chrome = viewer.chrome!;
      expect(chrome.thumbnails, isTrue);
      final gallery = GalleryItem(second.descriptor.key.mediaKey);
      final at = tester.element(find.byType(MediaViewer));
      expect((chrome.title!(at, 1, gallery)! as Text).data, 'Ada');
      expect(
        (chrome.subtitle!(at, 1, gallery)! as Text).data,
        'today at 12:00',
      );
      expect((chrome.caption!(at, 1, gallery)! as Text).data, 'Two of them');
      expect(
        [for (final a in chrome.actions!(1, gallery)) a.label],
        ['Forward', 'Save to Gallery'],
      );
    });

    testWidgets('the open viewer reads its actions again when the host says '
        'they changed: a save protection takes away leaves its menu live', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ChromeThemeScope(
            palette: const ChromePalette.dark(),
            child: child!,
          ),
          home: AssetCacheProvider(
            scope: scope.media,
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final changes = listen.ValueNotifier(0);
      addTearDown(changes.dispose);
      var saveAllowed = true;
      final items = [photo];
      unawaited(
        ChatMediaViewer.open(
          context,
          requestOf(items, 0),
          items,
          players: players,
          changes: changes,
          details: ChatViewerDetails(
            title: 'Ada',
            actionsOf: (item) => ChatMediaViewer.actionsFor(
              item,
              allowed: const {},
              saveLabel: saveAllowed ? 'Save to Gallery' : null,
              canForward: false,
              canDelete: false,
              onAction: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final viewer = tester.widget<MediaViewer>(find.byType(MediaViewer));
      final source = viewer.source;
      final bridge = viewer.bridge;

      await tester.tap(find.byKey(const ValueKey('mpx-viewer-more')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Save to Gallery'), findsOneWidget);

      saveAllowed = false;
      changes.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Save to Gallery'), findsNothing);

      // The same gallery and bridge: the viewer kept its page and its hold
      // on the chat's cell.
      final rebuilt = tester.widget<MediaViewer>(find.byType(MediaViewer));
      expect(rebuilt.source, same(source));
      expect(rebuilt.bridge, same(bridge));
    });
  });
}
