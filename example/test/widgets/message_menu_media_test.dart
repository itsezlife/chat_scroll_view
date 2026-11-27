/// The message menu on media: the per-item rows of a `MediaHitPart` under
/// the chat's protection, and Copy link on a link preview card.
library;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
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
