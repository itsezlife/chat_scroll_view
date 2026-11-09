import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// The content library's sticker and GIF lists as of the host's last
/// [commit], not as of now: what the panel's stickers and GIF pages list.
///
/// The library changes the moment a sticker is sent (it becomes the first
/// recent) or a GIF is sent (it becomes the first saved GIF). A page that
/// lists those lists first would reorder its grid under the finger that is
/// picking from it, so the host shows this view instead and decides when the
/// panel catches up: when it opens and when search ends, as for the emoji
/// recents (`DeferredRecentsStore`).
///
/// ## Which edits show at once
///
/// The host edits the library through the view, by one of two verbs, and the
/// verb is the rule:
///
/// - [record] is the record of a send (a sticker sent becomes the first
///   recent, a GIF sent the first saved GIF). It waits for the next
///   [commit]: the user is picking, and the grid must not move under them.
/// - [apply] is an edit the user asked for (favourite, unfavourite, save or
///   unsave a GIF, forget a recent). It shows at once, as the reference
///   client's panel does: `MediaDataController.addRecentSticker` signals
///   `recentDocumentsDidLoad` for a favourite or a removal, not for a send,
///   and a GIF saved from the preview calls `gifAddedOrDeleted`, while a GIF
///   sent (`addRecentGif` with a date) signals nothing; `EmojiView` reloads
///   its lists on those signals only.
///
/// ## Behaviour
///
/// - Each list answers the snapshot taken at construction and at each
///   [commit]; a [commit] signals each list it changed, once.
/// - A key that leaves the library, by any edit or anyone (removed from the
///   recents, unfavourited, unsaved, pushed out of a full list), leaves the
///   list shown at once, and nothing else in it moves: what the user asked
///   to forget is not shown a moment longer.
/// - A key [apply] adds or moves is shown first in its list at once, and
///   nothing else in it moves: the sends still waiting stay waiting. (The
///   reference reloads the whole list, sends included; showing the one key
///   keeps the rest of the grid where the finger left it.)
/// - Any other key added or moved waits for the next [commit].
///
/// The view does not own the library: [dispose] stops following it and
/// releases the view's own listenables.
final class DeferredLibraryView {
  /// A view of [library], showing what it holds now.
  DeferredLibraryView(ContentLibrary library)
    : _library = library,
      _lists = [
        _List(library.recentStickers),
        _List(library.favouriteStickers),
        _List(library.savedGifs),
      ];

  final ContentLibrary _library;
  final List<_List> _lists;
  var _disposed = false;

  /// The recent stickers, most recent first, as last committed.
  listen.ValueListenable<List<ContentKey>> get recentStickers =>
      _lists[0].shown;

  /// The favourite stickers, most recently marked first, as last committed.
  listen.ValueListenable<List<ContentKey>> get favouriteStickers =>
      _lists[1].shown;

  /// The saved GIFs, most recent first, as last committed.
  listen.ValueListenable<List<ContentKey>> get savedGifs => _lists[2].shown;

  /// Applies [edit], one the user asked for, and shows it at once: the key
  /// it adds comes first in its list, the key it takes out leaves it.
  AppliedEdit apply(LibraryEdit edit) {
    final applied = _library.apply(edit);
    if (_disposed) return applied;
    switch (edit) {
      case LibraryEdit$AddRecentSticker(:final key):
        _lists[0].bringForward(key);
      case LibraryEdit$FavouriteSticker(:final key):
        _lists[1].bringForward(key);
      case LibraryEdit$SaveGif(:final key):
        _lists[2].bringForward(key);
      // A removal leaves at once on its own; a pack is on none of the lists.
      case LibraryEdit$RemoveRecentSticker() ||
          LibraryEdit$UnfavouriteSticker() ||
          LibraryEdit$UnsaveGif() ||
          LibraryPackEdit() ||
          LibraryEdit$ReorderPacks():
        break;
    }
    return applied;
  }

  /// Applies [edit], the record of a send, and shows it at the next
  /// [commit].
  AppliedEdit record(LibraryEdit edit) => _library.apply(edit);

  /// Shows what the library holds now; signals each list that changed.
  void commit() {
    if (_disposed) return;
    for (final list in _lists) {
      list.catchUp();
    }
  }

  /// Stops following the library. Idempotent; the lists keep their last
  /// values.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final list in _lists) {
      list.dispose();
    }
  }
}

// One list of the library and what of it is shown.
final class _List {
  _List(this._source) : shown = listen.ValueNotifier(_source.value) {
    _source.addListener(_dropLeft);
  }

  final listen.ValueListenable<List<ContentKey>> _source;
  final listen.ValueNotifier<List<ContentKey>> shown;

  void catchUp() {
    if (!_same(shown.value, _source.value)) shown.value = _source.value;
  }

  // [key], if the library holds it, first in the shown list; the rest as
  // shown.
  void bringForward(ContentKey key) {
    if (!_source.value.contains(key)) return;
    final next = [
      key,
      for (final listed in shown.value)
        if (listed != key) listed,
    ];
    if (!_same(shown.value, next)) shown.value = List.unmodifiable(next);
  }

  // What left the library leaves the shown list now; the rest waits.
  void _dropLeft() {
    final kept = _source.value.toSet();
    final next = [
      for (final key in shown.value)
        if (kept.contains(key)) key,
    ];
    if (next.length != shown.value.length) {
      shown.value = List.unmodifiable(next);
    }
  }

  void dispose() {
    _source.removeListener(_dropLeft);
    shown.dispose();
  }

  static bool _same(List<ContentKey> a, List<ContentKey> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
