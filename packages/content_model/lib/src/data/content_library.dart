import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/pack/pack.dart';
import 'package:content_model/src/value_equality.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';

/// How many keys each most-recently-used list of a [ContentLibrary] keeps.
@immutable
final class LibraryLimits {
  /// Creates limits; each is at least 1.
  ///
  /// [favouriteStickers] and [savedGifs] are the host's to choose (the
  /// platform allows 5 and 200 without a subscription). [recentStickers]
  /// defaults to 30; a page may show fewer.
  const LibraryLimits({
    required this.favouriteStickers,
    required this.savedGifs,
    this.recentStickers = defaultRecentStickers,
  }) : assert(
         favouriteStickers > 0 && savedGifs > 0 && recentStickers > 0,
         'every list of a library holds at least one key',
       );

  /// The recent stickers kept unless told otherwise.
  static const int defaultRecentStickers = 30;

  /// The most favourite stickers.
  final int favouriteStickers;

  /// The most saved GIFs.
  final int savedGifs;

  /// The most recent stickers.
  final int recentStickers;

  @override
  bool operator ==(Object other) =>
      other is LibraryLimits &&
      other.favouriteStickers == favouriteStickers &&
      other.savedGifs == savedGifs &&
      other.recentStickers == recentStickers;

  @override
  int get hashCode => Object.hash(favouriteStickers, savedGifs, recentStickers);

  @override
  String toString() =>
      'LibraryLimits($favouriteStickers favourite, $savedGifs saved, '
      '$recentStickers recent)';
}

/// Whether a pack is in the user's library.
enum PackInstallState {
  /// Not in the library: offered, not owned.
  notInstalled,

  /// Installed: listed on the pack strip of its kind.
  installed,

  /// Archived: kept aside, off the strip, installable again in one step.
  archived,
}

/// One change to a [ContentLibrary], as a value.
///
/// Data rather than a method per change, so a panel or a sheet can ask the
/// host for one in an event, a backend adapter can send one as it is, and the
/// library can replay the edits still inside their undo window. Each rule is
/// stated below:
///
/// - The most-recently-used lists (recent stickers, favourite stickers, saved
///   GIFs): adding puts the key first, never twice; a key new to a full list
///   pushes out the last one. Removing a key not listed changes nothing.
/// - Installing puts a pack first among the installed packs of its kind and
///   out of the archive. Archiving moves an installed pack to the front of
///   the archive (a pack not installed is not archived). Removing takes a
///   pack out of both.
/// - Reordering lists the named installed packs in the given order, then the
///   other installed packs in theirs; names of packs not installed are
///   ignored.
@immutable
sealed class LibraryEdit {
  /// Records [key] as the latest sticker used.
  const factory LibraryEdit.addRecentSticker(ContentKey key) =
      LibraryEdit$AddRecentSticker;

  /// Forgets [key] among the recent stickers.
  const factory LibraryEdit.removeRecentSticker(ContentKey key) =
      LibraryEdit$RemoveRecentSticker;

  /// Marks [key] as a favourite sticker.
  const factory LibraryEdit.favouriteSticker(ContentKey key) =
      LibraryEdit$FavouriteSticker;

  /// Takes [key] out of the favourite stickers.
  const factory LibraryEdit.unfavouriteSticker(ContentKey key) =
      LibraryEdit$UnfavouriteSticker;

  /// Saves the GIF [key], first in the saved GIFs. Sending a GIF saves it.
  const factory LibraryEdit.saveGif(ContentKey key) = LibraryEdit$SaveGif;

  /// Takes the GIF [key] out of the saved GIFs.
  const factory LibraryEdit.unsaveGif(ContentKey key) = LibraryEdit$UnsaveGif;

  /// Installs the pack [id] of [kind].
  const factory LibraryEdit.installPack(PackId id, PackKind kind) =
      LibraryEdit$InstallPack;

  /// Archives the installed pack [id] of [kind].
  const factory LibraryEdit.archivePack(PackId id, PackKind kind) =
      LibraryEdit$ArchivePack;

  /// Removes the pack [id] of [kind], installed or archived.
  const factory LibraryEdit.removePack(PackId id, PackKind kind) =
      LibraryEdit$RemovePack;

  /// Puts the installed packs of [kind] in [order].
  factory LibraryEdit.reorderPacks(PackKind kind, List<PackId> order) =
      LibraryEdit$ReorderPacks;

  const LibraryEdit._();
}

/// A [LibraryEdit] of one content key in one most-recently-used list.
sealed class LibraryKeyEdit extends LibraryEdit {
  const LibraryKeyEdit._(this.key, this._label) : super._();

  final String _label;

  /// The content the edit is about.
  final ContentKey key;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is LibraryKeyEdit &&
      other.key == key;

  @override
  int get hashCode => Object.hash(runtimeType, key);

  @override
  String toString() => 'LibraryEdit.$_label($key)';
}

/// See [LibraryEdit.addRecentSticker].
final class LibraryEdit$AddRecentSticker extends LibraryKeyEdit {
  /// Records [key] as the latest sticker used.
  const LibraryEdit$AddRecentSticker(ContentKey key)
    : super._(key, 'addRecentSticker');
}

/// See [LibraryEdit.removeRecentSticker].
final class LibraryEdit$RemoveRecentSticker extends LibraryKeyEdit {
  /// Forgets [key] among the recent stickers.
  const LibraryEdit$RemoveRecentSticker(ContentKey key)
    : super._(key, 'removeRecentSticker');
}

/// See [LibraryEdit.favouriteSticker].
final class LibraryEdit$FavouriteSticker extends LibraryKeyEdit {
  /// Marks [key] as a favourite sticker.
  const LibraryEdit$FavouriteSticker(ContentKey key)
    : super._(key, 'favouriteSticker');
}

/// See [LibraryEdit.unfavouriteSticker].
final class LibraryEdit$UnfavouriteSticker extends LibraryKeyEdit {
  /// Takes [key] out of the favourite stickers.
  const LibraryEdit$UnfavouriteSticker(ContentKey key)
    : super._(key, 'unfavouriteSticker');
}

/// See [LibraryEdit.saveGif].
final class LibraryEdit$SaveGif extends LibraryKeyEdit {
  /// Saves the GIF [key].
  const LibraryEdit$SaveGif(ContentKey key) : super._(key, 'saveGif');
}

/// See [LibraryEdit.unsaveGif].
final class LibraryEdit$UnsaveGif extends LibraryKeyEdit {
  /// Takes the GIF [key] out of the saved GIFs.
  const LibraryEdit$UnsaveGif(ContentKey key) : super._(key, 'unsaveGif');
}

/// A [LibraryEdit] of one pack.
sealed class LibraryPackEdit extends LibraryEdit {
  const LibraryPackEdit._(this.id, this.kind, this._label) : super._();

  final String _label;

  /// The pack the edit is about.
  final PackId id;

  /// The kind of that pack, which names the lists it is in.
  final PackKind kind;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is LibraryPackEdit &&
      other.id == id &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(runtimeType, id, kind);

  @override
  String toString() => 'LibraryEdit.$_label(${id.value}, ${kind.value})';
}

/// See [LibraryEdit.installPack].
final class LibraryEdit$InstallPack extends LibraryPackEdit {
  /// Installs the pack [id] of [kind].
  const LibraryEdit$InstallPack(PackId id, PackKind kind)
    : super._(id, kind, 'installPack');
}

/// See [LibraryEdit.archivePack].
final class LibraryEdit$ArchivePack extends LibraryPackEdit {
  /// Archives the installed pack [id] of [kind].
  const LibraryEdit$ArchivePack(PackId id, PackKind kind)
    : super._(id, kind, 'archivePack');
}

/// See [LibraryEdit.removePack].
final class LibraryEdit$RemovePack extends LibraryPackEdit {
  /// Removes the pack [id] of [kind].
  const LibraryEdit$RemovePack(PackId id, PackKind kind)
    : super._(id, kind, 'removePack');
}

/// See [LibraryEdit.reorderPacks].
final class LibraryEdit$ReorderPacks extends LibraryEdit {
  /// Puts the installed packs of [kind] in [order], copied.
  LibraryEdit$ReorderPacks(this.kind, List<PackId> order)
    : order = List.unmodifiable(order),
      super._();

  /// The kind whose installed packs are reordered.
  final PackKind kind;

  /// The wanted order. Unmodifiable.
  final List<PackId> order;

  @override
  bool operator ==(Object other) =>
      other is LibraryEdit$ReorderPacks &&
      other.kind == kind &&
      ValueEquality.lists(other.order, order);

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(order));

  @override
  String toString() => 'LibraryEdit.reorderPacks(${kind.value}, $order)';
}

/// How an [AppliedEdit] ended.
@immutable
sealed class EditOutcome {
  /// Committing failed with [error]; the change stays in the library's lists.
  /// [stackTrace] is ignored by equality.
  const factory EditOutcome.failed(Object error, [StackTrace? stackTrace]) =
      EditOutcome$Failed;

  const EditOutcome._();

  /// Handed to storage, which stored it.
  static const EditOutcome committed = EditOutcome$Committed();

  /// Taken back inside its undo window; storage never saw it.
  static const EditOutcome undone = EditOutcome$Undone();

  /// Changed nothing, so nothing was shown, signalled or stored.
  static const EditOutcome unchanged = EditOutcome$Unchanged();
}

/// The [EditOutcome.committed] outcome.
final class EditOutcome$Committed extends EditOutcome {
  /// Creates the committed outcome.
  const EditOutcome$Committed() : super._();

  @override
  bool operator ==(Object other) => other is EditOutcome$Committed;

  @override
  int get hashCode => (EditOutcome$Committed).hashCode;

  @override
  String toString() => 'EditOutcome.committed';
}

/// The [EditOutcome.undone] outcome.
final class EditOutcome$Undone extends EditOutcome {
  /// Creates the undone outcome.
  const EditOutcome$Undone() : super._();

  @override
  bool operator ==(Object other) => other is EditOutcome$Undone;

  @override
  int get hashCode => (EditOutcome$Undone).hashCode;

  @override
  String toString() => 'EditOutcome.undone';
}

/// The [EditOutcome.unchanged] outcome.
final class EditOutcome$Unchanged extends EditOutcome {
  /// Creates the unchanged outcome.
  const EditOutcome$Unchanged() : super._();

  @override
  bool operator ==(Object other) => other is EditOutcome$Unchanged;

  @override
  int get hashCode => (EditOutcome$Unchanged).hashCode;

  @override
  String toString() => 'EditOutcome.unchanged';
}

/// The [EditOutcome.failed] outcome.
final class EditOutcome$Failed extends EditOutcome {
  /// Creates the failed outcome for [error].
  const EditOutcome$Failed(this.error, [this.stackTrace]) : super._();

  /// What committing failed with.
  final Object error;

  /// Where [error] was thrown, when known.
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      other is EditOutcome$Failed && other.error == error;

  @override
  int get hashCode => Object.hash(EditOutcome$Failed, error);

  @override
  String toString() => 'EditOutcome.failed($error)';
}

/// A [LibraryEdit] the library has applied: already shown, committed when its
/// undo window ends.
abstract interface class AppliedEdit {
  /// The edit.
  LibraryEdit get edit;

  /// The key the edit pushed out of a full list when it was applied (the
  /// oldest favourite, the oldest saved GIF), so the host can say the limit
  /// was reached; null when it pushed out nothing.
  ContentKey? get evicted;

  /// Whether the edit can still be taken back: it changed something and is
  /// neither committed nor undone.
  bool get isPending;

  /// Takes the edit back while [isPending]: the lists show what they would
  /// without it, and storage never sees it. Returns whether it did.
  bool undo();

  /// Ends the undo window now. Does nothing once the edit is settled.
  void commit();

  /// How the edit ended. Completes once, and never with an error.
  Future<EditOutcome> get outcome;
}

/// The user's own lists: recent stickers, favourite stickers, saved GIFs, and
/// the installed and archived packs of each kind.
///
/// Changed only through [apply], local first: the lists change and signal
/// before [apply] returns, and storage gets the edit when its undo window
/// ends. Emoji recents are not here: they are a `RecentsStore`'s, ordered by
/// frequency.
///
/// ## Undo window
///
/// An edit applied with an `undoWindow` stays pending that long (or until
/// [AppliedEdit.commit]); [AppliedEdit.undo] takes it back meanwhile. With no
/// window it commits at once, unless an earlier edit is still pending: edits
/// commit in the order they were applied, so storage never holds an order the
/// user did not see. The lists shown are the committed lists with the pending
/// edits replayed over them, so taking an edit back leaves every other edit
/// as it was (a removed pack comes back to its own place).
///
/// ## Signals
///
/// Each list's listenable notifies once per [apply] or undo that changed it,
/// and never for one that did not. An edit that changes nothing is settled
/// as [EditOutcome.unchanged] at once.
///
/// ## Disposal
///
/// [dispose] commits every pending edit at once and releases the listeners;
/// afterwards the lists keep their last values and [apply] changes nothing.
/// Idempotent.
abstract interface class ContentLibrary {
  /// How many keys each most-recently-used list keeps.
  LibraryLimits get limits;

  /// The recent stickers, most recent first.
  ValueListenable<List<ContentKey>> get recentStickers;

  /// The favourite stickers, most recently marked first.
  ValueListenable<List<ContentKey>> get favouriteStickers;

  /// The saved GIFs, most recent first: the GIF recents.
  ValueListenable<List<ContentKey>> get savedGifs;

  /// The installed packs of [kind], in the user's order.
  ValueListenable<List<PackId>> installedPacks(PackKind kind);

  /// The archived packs of [kind], most recently archived first.
  ValueListenable<List<PackId>> archivedPacks(PackKind kind);

  /// Whether the pack [id] is installed, archived or neither, in any kind.
  PackInstallState installStateOf(PackId id);

  /// Applies [edit] now and commits it after [undoWindow].
  AppliedEdit apply(LibraryEdit edit, {Duration undoWindow = Duration.zero});

  /// Commits what is pending and releases the library and its listeners.
  void dispose();
}
