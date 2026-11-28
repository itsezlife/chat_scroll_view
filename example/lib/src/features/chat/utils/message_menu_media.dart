import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_entries.dart';
import 'package:content_model/content_model.dart' show MediaItem, MediaItemId;
import 'package:flutter/material.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_library/mpx_library.dart'
    show
        SaveDestination$Ask,
        SaveDestination$Downloads,
        SaveDestination$Gallery;

/// Which media a message menu opened beside a message's media (on its
/// caption, its padding, beside the bubble) reaches; a press on an item
/// always reaches that item.
enum MediaMenuReach {
  /// The whole message: one item alone, or every item of an album, each
  /// row acting on all of them (Android).
  wholeMessage,

  /// The first item (iOS).
  firstItem,

  /// None: media rows only over an item (desktop).
  pressedItemOnly,
}

/// The per-item rows of a message menu opened on a media item: the save
/// entry of the item's kind and platform (`ChatSaveEntries`), then one row
/// per other `MediaItemAction` the item supports and the chat's protection
/// allows, above the message's own rows.
abstract final class MessageMenuMediaRows {
  static const String _prefix = 'media_item_';

  /// The row id of the save entry.
  static const String saveId = 'media_save';

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

  /// The items a menu request reaches: the item its `MediaHitPart` is on,
  /// among [items] and the link preview [card]'s; else, beside the media,
  /// what [reach] says of the message's [items] (never the card's).
  static List<MediaItem> targetsOf(
    ChatMessageMenuRequest request,
    List<MediaItem> items, {
    required MediaMenuReach reach,
    MediaItem? card,
  }) {
    if (request.partId case final MediaHitPart part) {
      return [
        ?itemOfPart(part, [...items, ?card]),
      ];
    }
    return switch ((reach, items)) {
      (_, []) || (MediaMenuReach.pressedItemOnly, _) => const [],
      (MediaMenuReach.firstItem, [final first, ...]) => [first],
      (MediaMenuReach.wholeMessage, _) => items,
    };
  }

  /// The rows of [targets]: the [saveEntry] row first when there is one
  /// (the entry of the items' kind, null while protection denies the save
  /// or for a host without saves), then for one item its other rows
  /// ([rowsFor] its allowed actions); several items (an album) have the
  /// save entry alone, which acts on all of them.
  static List<ChatMessageMenuItem> rowsForTargets(
    List<MediaItem> targets,
    Set<MediaItemAction> Function(MediaItem item) allowedOf, {
    ChatSaveEntry? saveEntry,
  }) => [
    if (targets.isNotEmpty && saveEntry != null) saveRowOf(saveEntry),
    ...switch (targets) {
      [final item] => rowsFor(allowedOf(item).difference(_savedByEntry)),
      _ => const <ChatMessageMenuItem>[],
    },
  ];

  // The actions the save entry stands for: the table's destination decides
  // which one a kind has on a platform.
  static const Set<MediaItemAction> _savedByEntry = {
    MediaItemAction.saveToGallery,
    MediaItemAction.saveToDownloads,
    MediaItemAction.saveAs,
  };

  /// The row of [entry]: its label, the icon of its destination.
  static ChatMessageMenuItem saveRowOf(ChatSaveEntry entry) =>
      ChatMessageMenuItem(
        id: saveId,
        label: entry.label,
        icon: switch (entry.destination) {
          SaveDestination$Gallery() => Icons.photo_library_outlined,
          SaveDestination$Downloads() => Icons.download_outlined,
          SaveDestination$Ask() => Icons.save_alt_outlined,
        },
      );

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
