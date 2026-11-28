/// The message menu on media: the per-item rows of a `MediaHitPart` under
/// the chat's protection, the media rows of a press beside the media (the
/// whole album, the first item or none, per platform), and Copy link on a
/// link preview card.
library;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/app_platform_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_photos.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu_media.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

ChatMessageMenuRequest _onPart(Object part) => ChatMessageMenuRequest(
  messageId: 3,
  slotGlobal: const Rect.fromLTWH(0, 0, 300, 200),
  tapGlobal: const Offset(20, 20),
  inlineHit: ChatInlineHit.bodyPart(
    messageId: 3,
    partId: part,
    role: ChatBodyPartRole.menu,
    rect: const Rect.fromLTWH(0, 0, 300, 200),
  ),
);

void main() {
  final photo = MediaItem(
    id: const MediaItemId('3.0'),
    descriptor: DemoPhotos.harbour.descriptor,
  );
  final file = MediaItem(
    id: const MediaItemId('3.1'),
    descriptor: DemoPhotos.meadow.descriptor,
    kind: MediaItemKind.file,
  );

  List<String> idsOf(List<ChatMessageMenuItem> rows) => [
    for (final row in rows)
      if (row case ChatMessageMenuAction(:final id)) id,
  ];

  test('the item a request is on is its part\'s', () {
    final items = [photo, file];

    expect(
      MessageMenuMediaRows.itemOf(
        _onPart(MediaHitPart(file.id, part: MediaPart.options)),
        items,
      ),
      file,
    );
    expect(
      MessageMenuMediaRows.itemOf(
        _onPart(const LinkPreviewHitPart(3, zone: LinkPreviewZone.body)),
        items,
      ),
      isNull,
    );
  });

  group('a press beside the media', () {
    const beside = ChatMessageMenuRequest(
      messageId: 3,
      slotGlobal: Rect.fromLTWH(0, 0, 300, 200),
      tapGlobal: Offset(20, 190),
    );
    final second = MediaItem(
      id: const MediaItemId('3.2'),
      descriptor: DemoPhotos.meadow.descriptor,
    );

    test('on Android it reaches the whole album, with the save rows its '
        'items share', () {
      final targets = MessageMenuMediaRows.targetsOf(beside, [
        photo,
        second,
      ], reach: const AppPlatformPolicy.android().mediaMenuReach);
      expect(targets, [photo, second]);
      final rows = MessageMenuMediaRows.rowsForTargets(
        targets,
        (item) => MediaItemAction.allowedItemActions(
          item,
          protection: const ChatProtection(),
          messageProtected: false,
        ),
      );
      expect(idsOf(rows), [
        MessageMenuMediaRows.idOf(MediaItemAction.saveToGallery),
      ]);
    });

    test('on iOS it reaches the first item, with its own rows', () {
      final targets = MessageMenuMediaRows.targetsOf(beside, [
        photo,
        second,
      ], reach: const AppPlatformPolicy.iOS().mediaMenuReach);
      expect(targets, [photo]);
    });

    test('a single item is reached on a phone; on desktop only a press on '
        'the item reaches it', () {
      for (final platform in [
        const AppPlatformPolicy.android(),
        const AppPlatformPolicy.iOS(),
      ]) {
        expect(
          MessageMenuMediaRows.targetsOf(beside, [
            photo,
          ], reach: platform.mediaMenuReach),
          [photo],
        );
      }
      expect(
        MessageMenuMediaRows.targetsOf(beside, [
          photo,
        ], reach: const AppPlatformPolicy.desktop().mediaMenuReach),
        isEmpty,
      );
      expect(
        MessageMenuMediaRows.targetsOf(
          _onPart(MediaHitPart(second.id, part: MediaPart.content)),
          [photo, second],
          reach: const AppPlatformPolicy.desktop().mediaMenuReach,
        ),
        [second],
      );
    });

    test('protection takes the album rows away', () {
      final rows = MessageMenuMediaRows.rowsForTargets(
        [photo, second],
        (item) => MediaItemAction.allowedItemActions(
          item,
          protection: const ChatProtection(),
          messageProtected: true,
        ),
      );
      expect(rows, isEmpty);
    });
  });

  test('rows follow the kind and what protection allows', () {
    final open = MessageMenuMediaRows.rowsFor(
      MediaItemAction.allowedItemActions(
        photo,
        protection: const ChatProtection(),
        messageProtected: false,
      ),
    );
    expect(idsOf(open), [
      for (final action in [
        MediaItemAction.saveToGallery,
        MediaItemAction.saveAs,
        MediaItemAction.showInFolder,
        MediaItemAction.copyImage,
        MediaItemAction.share,
      ])
        MessageMenuMediaRows.idOf(action),
    ]);

    final protectedRows = MessageMenuMediaRows.rowsFor(
      MediaItemAction.allowedItemActions(
        file,
        protection: const ChatProtection(),
        messageProtected: true,
      ),
    );
    expect(protectedRows, isEmpty);

    for (final action in MediaItemAction.values) {
      expect(
        MessageMenuMediaRows.actionOf(MessageMenuMediaRows.idOf(action)),
        action,
      );
    }
    expect(MessageMenuMediaRows.actionOf(MessageMenuActionId.copy), isNull);
  });

  test('a menu on a link preview card offers Copy link, which protection '
      'takes away with the other copy rows', () {
    final items = MessageMenuCatalog.itemsFor(
      _onPart(const LinkPreviewHitPart(3, zone: LinkPreviewZone.body)),
      const ChatSelectionPolicy.mobile(),
    );
    expect(idsOf(items), contains(MessageMenuActionId.copyLink));
    expect(
      MessageMenuCatalog.protectedActionIds(ProtectionFlags.copy),
      contains(MessageMenuActionId.copyLink),
    );

    final onMedia = MessageMenuCatalog.itemsFor(
      _onPart(MediaHitPart(photo.id, part: MediaPart.options)),
      const ChatSelectionPolicy.mobile(),
    );
    expect(idsOf(onMedia), isNot(contains(MessageMenuActionId.copyLink)));
  });
}
