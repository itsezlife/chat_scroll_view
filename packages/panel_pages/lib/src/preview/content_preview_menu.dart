import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show ValueChanged, immutable;
import 'package:panel_pages/src/menu/catalog_menu_icons.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/preview/content_preview_item.dart';

/// One item of a content preview's menu, with the icon it leads with: the
/// reference client's (`ContentPreviewViewer` adds each item with its
/// drawable, named below), from [CatalogMenuIcons].
enum ContentPreviewAction {
  /// Send the content (`msg_send`).
  send('send'),

  /// Send it without a notification sound (`input_notify_off`).
  sendWithoutSound('send-without-sound'),

  /// Add the sticker to the favourite stickers (`msg_fave`).
  favourite('favourite'),

  /// Take the sticker out of the favourite stickers (`msg_unfave`).
  unfavourite('unfavourite'),

  /// Show the pack the content belongs to (`msg_media`).
  viewPack('view-pack'),

  /// Take the content out of the recents list it was opened from
  /// (`msg_delete`).
  removeRecent('remove-recent'),

  /// Save the GIF among the saved GIFs (`msg_gif_add`).
  saveGif('save-gif'),

  /// Delete the GIF from the saved GIFs (`msg_delete`).
  unsaveGif('unsave-gif'),

  /// Copy the custom emoji (`msg_copy`).
  copy('copy');

  const ContentPreviewAction(this.id);

  /// The id the action has as a context menu item.
  final String id;

  /// The chrome icon the item leads with.
  ChromeIconId get icon => switch (this) {
    send => CatalogMenuIcons.send,
    sendWithoutSound => CatalogMenuIcons.sendWithoutSound,
    favourite => CatalogMenuIcons.favourite,
    unfavourite => CatalogMenuIcons.unfavourite,
    viewPack => CatalogMenuIcons.viewPack,
    removeRecent || unsaveGif => CatalogMenuIcons.delete,
    saveGif => CatalogMenuIcons.saveGif,
    copy => CatalogMenuIcons.copy,
  };

  /// The action of [id], or null for an id that is none.
  static ContentPreviewAction? byId(String id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// What the place a content preview was opened from can do with what it
/// shows: each one given is an item the menu may hold, each one left null is
/// an item it never holds.
///
/// The preview performs nothing itself, as the panel performs nothing: every
/// item is a request to the opener, who sends, copies or edits the library
/// and shows the feedback. A panel page answers through its `PanelPageHost`
/// (a send is a pick, a library action a `LibraryEditRequested`, "View pack"
/// a `PackRequested`); a pack sheet gives [send] only when the composer it
/// was opened for can send.
@immutable
final class ContentPreviewActions {
  /// The actions given; none by default.
  const ContentPreviewActions({
    this.send,
    this.sendWithoutSound,
    this.copy,
    this.removeRecent,
    this.editLibrary,
    this.viewPack,
  });

  /// Sends the item.
  final ValueChanged<ContentPreviewItem>? send;

  /// Sends the item without a notification sound; a host that cannot gives
  /// none, and the menu has no such item.
  final ValueChanged<ContentPreviewItem>? sendWithoutSound;

  /// Copies the item (a custom emoji).
  final ValueChanged<ContentPreviewItem>? copy;

  /// Forgets a custom emoji in the emoji recents it was opened from. A
  /// sticker leaves its recents through [editLibrary].
  final ValueChanged<ContentPreviewItem>? removeRecent;

  /// Asks for an edit of the content library: a favourite, a saved GIF, a
  /// recent sticker.
  final ValueChanged<LibraryEdit>? editLibrary;

  /// Shows the pack of the item.
  final ValueChanged<PackId>? viewPack;
}

/// The rules of a content preview's menu: which items, in which order, under
/// which labels, and what choosing one asks of the opener.
///
/// The reference client's (`ContentPreviewViewer`), per kind:
///
/// - **Sticker:** Send, Send without sound, Add to / Delete from Favorites
///   (never for a mask; for a favourite, or a sticker of a pack), View Pack
///   (a sticker of a pack), Delete from Recent (opened from the recents).
/// - **Custom emoji:** Send Emoji, Copy Emoji, Remove from Recent (opened
///   from the recents, in the attention style).
/// - **GIF:** Send, Send without sound, then Delete (attention) for a saved
///   one or Save to GIFs.
///
/// An item is offered only when the opener gives its action, and an item
/// that depends on the library (favourite, saved) only when there is a
/// library to read. Not ported: schedule, captions, emoji status, editing or
/// deleting one's own sticker.
abstract final class ContentPreviewMenu {
  /// The items of the menu for [item], in order; empty for no menu.
  ///
  /// [library] is read now: a menu is built as it opens, and an edit made
  /// while it is up does not change it.
  static List<ContentPreviewAction> of(
    ContentPreviewItem item,
    ContentPreviewActions actions, {
    ContentLibrary? library,
  }) {
    final edits = actions.editLibrary != null ? library : null;
    return switch (item.kind) {
      ContentPreviewKind.sticker => [
        if (actions.send != null) ContentPreviewAction.send,
        if (actions.sendWithoutSound != null)
          ContentPreviewAction.sendWithoutSound,
        if (edits != null && item.semanticKind != SemanticKind.mask)
          if (edits.favouriteStickers.value.contains(item.key))
            ContentPreviewAction.unfavourite
          else if (item.pack != null)
            ContentPreviewAction.favourite,
        if (actions.viewPack != null && item.pack != null)
          ContentPreviewAction.viewPack,
        if (item.inRecents && actions.editLibrary != null)
          ContentPreviewAction.removeRecent,
      ],
      ContentPreviewKind.customEmoji => [
        if (actions.send != null) ContentPreviewAction.send,
        if (actions.copy != null) ContentPreviewAction.copy,
        if (item.inRecents && actions.removeRecent != null)
          ContentPreviewAction.removeRecent,
      ],
      ContentPreviewKind.gif => [
        if (actions.send != null) ContentPreviewAction.send,
        if (actions.sendWithoutSound != null)
          ContentPreviewAction.sendWithoutSound,
        if (edits != null)
          edits.savedGifs.value.contains(item.key)
              ? ContentPreviewAction.unsaveGif
              : ContentPreviewAction.saveGif,
      ],
    };
  }

  /// The label of [action] for [item], in the language of [strings].
  static String labelOf(
    ContentPreviewAction action,
    ContentPreviewItem item,
    PanelStrings strings,
  ) => switch (action) {
    ContentPreviewAction.send => switch (item.kind) {
      ContentPreviewKind.sticker => strings.sendStickerAction,
      ContentPreviewKind.gif => strings.sendGifAction,
      ContentPreviewKind.customEmoji => strings.sendEmojiAction,
    },
    ContentPreviewAction.sendWithoutSound => strings.sendWithoutSoundAction,
    ContentPreviewAction.favourite => strings.addToFavouritesAction,
    ContentPreviewAction.unfavourite => strings.removeFromFavouritesAction,
    ContentPreviewAction.viewPack => strings.viewPackAction,
    ContentPreviewAction.removeRecent =>
      item.kind == ContentPreviewKind.customEmoji
          ? strings.removeRecentAction
          : strings.deleteFromRecentAction,
    ContentPreviewAction.saveGif => strings.saveGifAction,
    ContentPreviewAction.unsaveGif => strings.deleteGifAction,
    ContentPreviewAction.copy => strings.copyEmojiAction,
  };

  /// Whether [action] is drawn in the attention colour: one that throws
  /// something away where the reference draws it red.
  static bool isAttention(
    ContentPreviewAction action,
    ContentPreviewItem item,
  ) => switch (action) {
    ContentPreviewAction.unsaveGif => true,
    ContentPreviewAction.removeRecent =>
      item.kind == ContentPreviewKind.customEmoji,
    _ => false,
  };

  /// The same items as a context menu's entries, for a secondary click: the
  /// pointer's way to the preview's actions.
  static List<CatalogMenuEntry> entriesOf(
    ContentPreviewItem item,
    ContentPreviewActions actions,
    PanelStrings strings, {
    ContentLibrary? library,
  }) => [
    for (final action in of(item, actions, library: library))
      CatalogMenuEntry.item(
        id: action.id,
        label: labelOf(action, item, strings),
        attention: isAttention(action, item),
        icon: action.icon,
      ),
  ];

  /// Asks the opener for what [action] does to [item].
  static void perform(
    ContentPreviewAction action,
    ContentPreviewItem item,
    ContentPreviewActions actions,
  ) {
    final key = item.key;
    switch (action) {
      case ContentPreviewAction.send:
        actions.send?.call(item);
      case ContentPreviewAction.sendWithoutSound:
        actions.sendWithoutSound?.call(item);
      case ContentPreviewAction.favourite:
        actions.editLibrary?.call(LibraryEdit.favouriteSticker(key));
      case ContentPreviewAction.unfavourite:
        actions.editLibrary?.call(LibraryEdit.unfavouriteSticker(key));
      case ContentPreviewAction.viewPack:
        if (item.pack case final pack?) actions.viewPack?.call(pack);
      case ContentPreviewAction.removeRecent:
        if (item.kind == ContentPreviewKind.customEmoji) {
          actions.removeRecent?.call(item);
        } else {
          actions.editLibrary?.call(LibraryEdit.removeRecentSticker(key));
        }
      case ContentPreviewAction.saveGif:
        actions.editLibrary?.call(LibraryEdit.saveGif(key));
      case ContentPreviewAction.unsaveGif:
        actions.editLibrary?.call(LibraryEdit.unsaveGif(key));
      case ContentPreviewAction.copy:
        actions.copy?.call(item);
    }
  }
}
