import 'package:chat_capabilities/chat_capabilities.dart'
    show ChatProtection, ProtectionFlags;
import 'package:content_model/content_model.dart' show MediaItem, MediaItemKind;

/// A per-item action a host may offer for one media item: an entry of its
/// message menu (built from the `MediaHitPart` the menu request carries) or
/// a button of its viewer.
///
/// Message media builds no menu and runs none of these; it only says which
/// ones an item allows ([allowedItemActions]).
enum MediaItemAction {
  /// Save a photo, video or animation to the device's gallery.
  saveToGallery,

  /// Save a file to the device's downloads.
  saveToDownloads,

  /// Save the item where the user picks.
  saveAs,

  /// Show the saved item in the system's file browser.
  showInFolder,

  /// Copy a photo to the clipboard.
  copyImage,

  /// Copy a file's name to the clipboard.
  copyFileName,

  /// Share the item out of the chat (the viewer's share, a menu's).
  share,

  /// Stop the item's download.
  cancelDownload;

  /// The actions a host may offer for [item], in declaration order: the
  /// ones its kind supports, less those the chat's [protection] denies for
  /// the message (`ChatProtection.forMessage`, with the message's own
  /// [messageProtected] flag from the host's model).
  ///
  /// | Action | Kinds | Denied by |
  /// | --- | --- | --- |
  /// | [saveToGallery] | photo, video, animation | save |
  /// | [saveToDownloads] | file and custom kinds | save |
  /// | [saveAs], [showInFolder] | every kind | save |
  /// | [copyImage] | photo | copy |
  /// | [copyFileName] | file and custom kinds | copy |
  /// | [share] | every kind | save or forward |
  /// | [cancelDownload] | every kind | never |
  ///
  /// Whether an action applies now (a download under way, a file on disk)
  /// is the host's to check: this answers only what the item and the
  /// protection allow.
  static Set<MediaItemAction> allowedItemActions(
    MediaItem item, {
    required ChatProtection protection,
    required bool messageProtected,
  }) {
    final denied = protection.forMessage(messageProtected: messageProtected);
    return {
      for (final action in values)
        if (action._supports(item.kind) && !action._deniedBy(denied)) action,
    };
  }

  bool _supports(MediaItemKind kind) {
    final picture = kind.isPicture;
    return switch (this) {
      saveToGallery => picture,
      saveToDownloads || copyFileName => !picture,
      copyImage => kind == MediaItemKind.photo,
      saveAs || showInFolder || share || cancelDownload => true,
    };
  }

  bool _deniedBy(ProtectionFlags denied) => switch (this) {
    saveToGallery ||
    saveToDownloads ||
    saveAs ||
    showInFolder => denied.contains(ProtectionFlags.save),
    copyImage || copyFileName => denied.contains(ProtectionFlags.copy),
    // Sharing takes the content out of the chat: what forwarding and saving
    // each forbid.
    share =>
      denied.contains(ProtectionFlags.save) ||
          denied.contains(ProtectionFlags.forward),
    cancelDownload => false,
  };
}
