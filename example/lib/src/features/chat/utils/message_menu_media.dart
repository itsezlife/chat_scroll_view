import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart' show MediaItem, MediaItemId;
import 'package:flutter/material.dart';
import 'package:message_media/message_media.dart';

/// The per-item rows of a message menu opened on a media item: one row per
/// `MediaItemAction` the item supports and the chat's protection allows,
/// above the message's own rows.
abstract final class MessageMenuMediaRows {
  static const String _prefix = 'media_item_';

  /// The row id of [action].
  static String idOf(MediaItemAction action) => '$_prefix${action.name}';

  /// The action a row id names, or null for a row that is no item's.
  static MediaItemAction? actionOf(String id) {
    if (!id.startsWith(_prefix)) return null;
    final name = id.substring(_prefix.length);
    for (final action in MediaItemAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }

  /// The item a menu request is on: its `MediaHitPart`'s item among
  /// [items], or null when the press was on no media item.
  static MediaItem? itemOf(
    ChatMessageMenuRequest request,
    List<MediaItem> items,
  ) => switch (request.partId) {
    final MediaHitPart part => itemOfPart(part, items),
    _ => null,
  };

  /// The item [part] is on among [items], or null.
  static MediaItem? itemOfPart(MediaHitPart part, List<MediaItem> items) =>
      _find(items, part.itemId);

  static MediaItem? _find(List<MediaItem> items, MediaItemId id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// The rows of [allowed], in the actions' order. Cancel Download is the
  /// status control's, which shows only while the item loads: the menu,
  /// which cannot tell, leaves it out.
  static List<ChatMessageMenuItem> rowsFor(Set<MediaItemAction> allowed) => [
    for (final action in MediaItemAction.values)
      if (allowed.contains(action) && action != MediaItemAction.cancelDownload)
        ChatMessageMenuItem(
          id: idOf(action),
          label: _labelOf(action),
          icon: _iconOf(action),
        ),
  ];

  static String _labelOf(MediaItemAction action) => switch (action) {
    MediaItemAction.saveToGallery => 'Save to Gallery',
    MediaItemAction.saveToDownloads => 'Save to Downloads',
    MediaItemAction.saveAs => 'Save As…',
    MediaItemAction.showInFolder => 'Show in Folder',
    MediaItemAction.copyImage => 'Copy Image',
    MediaItemAction.copyFileName => 'Copy File Name',
    MediaItemAction.share => 'Share',
    MediaItemAction.cancelDownload => 'Cancel Download',
  };

  static IconData _iconOf(MediaItemAction action) => switch (action) {
    MediaItemAction.saveToGallery => Icons.photo_library_outlined,
    MediaItemAction.saveToDownloads => Icons.download_outlined,
    MediaItemAction.saveAs => Icons.save_alt_outlined,
    MediaItemAction.showInFolder => Icons.folder_open_outlined,
    MediaItemAction.copyImage => Icons.image_outlined,
    MediaItemAction.copyFileName => Icons.content_copy_outlined,
    MediaItemAction.share => Icons.share_outlined,
    MediaItemAction.cancelDownload => Icons.close,
  };
}
