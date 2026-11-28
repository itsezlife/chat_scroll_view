import 'package:chat_scroll_view_example/src/app/app_platform_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:content_model/content_model.dart' show MediaItemKind;
import 'package:flutter/foundation.dart';
import 'package:mpx_library/mpx_library.dart' show SaveDestination;

/// One save entry of a menu: what it says and where it saves.
@immutable
final class ChatSaveEntry {
  /// An entry saying [label] that saves to [destination].
  const ChatSaveEntry(this.label, this.destination);

  /// The row's text.
  final String label;

  /// Where the save goes.
  final SaveDestination destination;

  @override
  bool operator ==(Object other) =>
      other is ChatSaveEntry &&
      other.label == label &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(label, destination);

  @override
  String toString() => 'ChatSaveEntry($label, ${destination.name})';
}

/// Which save entries the example's menus offer on a platform: one per
/// media kind, and the entry of a message selection where the platform has
/// one.
///
/// The defaults of the media-save spec's per-item table, held here because
/// menus are the host's: the message media package says only which actions
/// protection allows and cannot name a save destination. A host changes an
/// entry by building its own value.
///
/// | Kind | Android | iOS | Desktop, web |
/// | --- | --- | --- | --- |
/// | Photo | Save to Gallery (gallery) | Save Image (gallery) | Save Image As… (ask) |
/// | Video | Save to Gallery (gallery) | Save Video (gallery) | Save As (ask) |
/// | Animation | Save to Downloads (downloads) | Save GIF (gallery) | Save GIF (ask) |
/// | File | Save to Downloads (downloads) | Save to Files (downloads) | Save As (ask) |
///
/// The Android gallery files into the example's sub-folder
/// (`Pictures/<subfolder>`), which needs nothing more there; the Apple
/// gallery takes no album, which would need read and write access to the
/// library.
@immutable
final class ChatSaveEntries {
  /// Entries per kind; [selection] is the entry of a message selection of
  /// files, null where a selection offers none.
  const ChatSaveEntries({
    required this.platform,
    required this.photo,
    required this.video,
    required this.animation,
    required this.file,
    this.selection,
  });

  /// The entries of [policy]'s platform family.
  factory ChatSaveEntries.forPlatform(AppPlatformPolicy policy) =>
      switch (policy) {
        AppPlatformPolicy$Mobile(android: true) => android,
        AppPlatformPolicy$Mobile() => iOS,
        AppPlatformPolicy$Desktop(web: false) => desktop,
        AppPlatformPolicy$Desktop() => web,
      };

  /// The entries of the running app.
  factory ChatSaveEntries.current() =>
      ChatSaveEntries.forPlatform(AppPlatformPolicy.current());

  static const _androidGallery = ChatSaveEntry(
    'Save to Gallery',
    SaveDestination.gallery(album: ChatSaveWiring.subfolder),
  );
  static const _androidDownloads = ChatSaveEntry(
    'Save to Downloads',
    ChatSaveWiring.downloads,
  );

  /// An Android phone's. A selection of files saves to Downloads.
  static const android = ChatSaveEntries(
    platform: 'android',
    photo: _androidGallery,
    video: _androidGallery,
    animation: _androidDownloads,
    file: _androidDownloads,
    selection: _androidDownloads,
  );

  /// An iPhone's. A selection saves through its share sheet, which is not a
  /// save entry.
  static const iOS = ChatSaveEntries(
    platform: 'iOS',
    photo: ChatSaveEntry('Save Image', SaveDestination.gallery()),
    video: ChatSaveEntry('Save Video', SaveDestination.gallery()),
    animation: ChatSaveEntry('Save GIF', SaveDestination.gallery()),
    file: ChatSaveEntry('Save to Files', ChatSaveWiring.downloads),
  );

  /// A desktop app's: every save asks where.
  static const desktop = ChatSaveEntries(
    platform: 'desktop',
    photo: ChatSaveEntry('Save Image As…', SaveDestination.ask()),
    video: ChatSaveEntry('Save As', SaveDestination.ask()),
    animation: ChatSaveEntry('Save GIF', SaveDestination.ask()),
    file: ChatSaveEntry('Save As', SaveDestination.ask()),
  );

  /// A browser's: the desktop's, where the save dialog is the browser's
  /// picker or a download.
  static const web = ChatSaveEntries(
    platform: 'web',
    photo: ChatSaveEntry('Save Image As…', SaveDestination.ask()),
    video: ChatSaveEntry('Save As', SaveDestination.ask()),
    animation: ChatSaveEntry('Save GIF', SaveDestination.ask()),
    file: ChatSaveEntry('Save As', SaveDestination.ask()),
  );

  /// The platform's name in diagnostics.
  final String platform;

  /// The entry of a photo.
  final ChatSaveEntry photo;

  /// The entry of a video.
  final ChatSaveEntry video;

  /// The entry of an animation (a GIF).
  final ChatSaveEntry animation;

  /// The entry of a file, and of a kind the example does not name.
  final ChatSaveEntry file;

  /// The entry of a message selection whose every item is a file; null
  /// offers none.
  final ChatSaveEntry? selection;

  /// The entry of an item of [kind].
  ChatSaveEntry entryOf(MediaItemKind kind) => switch (kind) {
    MediaItemKind.photo => photo,
    MediaItemKind.video => video,
    MediaItemKind.animation => animation,
    _ => file,
  };

  /// The entry every one of [kinds] has, which saves them as one batch (an
  /// album); null when they differ or there are none.
  ChatSaveEntry? sharedEntryOf(Iterable<MediaItemKind> kinds) {
    final entries = kinds.map(entryOf).toSet();
    return entries.length == 1 ? entries.single : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatSaveEntries &&
      other.platform == platform &&
      other.photo == photo &&
      other.video == video &&
      other.animation == animation &&
      other.file == file &&
      other.selection == selection;

  @override
  int get hashCode =>
      Object.hash(platform, photo, video, animation, file, selection);
}
