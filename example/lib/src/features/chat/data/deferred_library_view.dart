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
/// ## Behaviour
///
/// - Each list answers the snapshot taken at construction and at each
///   [commit]; a [commit] signals each list it changed, once.
/// - A key that leaves the library (removed from the recents, unfavourited,
///   unsaved, pushed out of a full list) leaves the list shown at once, and
///   nothing else in it moves: what the user asked to forget is not shown a
///   moment longer. A key added or moved waits for the next [commit].
///
/// The view does not own the library: [dispose] stops following it and
/// releases the view's own listenables.
final class DeferredLibraryView {
  /// A view of [library], showing what it holds now.
  DeferredLibraryView(ContentLibrary library)
    : _lists = [
        _List(library.recentStickers),
        _List(library.favouriteStickers),
        _List(library.savedGifs),
      ];

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
