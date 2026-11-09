import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// The user's own lists of the content library as the collections a page
/// lists ahead of its packs or feed, loaded from the start.
///
/// - [LibraryContentSource.stickers]: the favourite stickers
///   (`CollectionId.faved`), then the recent stickers (`CollectionId.recent`),
///   as the reference mobile client lists them (`EmojiView`'s
///   `StickersGridAdapter.updateItems`: favourites, then recents). A
///   favourite is not listed again among the recents, and the recents show
///   the first [shownRecentStickers] of the ones the library keeps
///   (`checkDocuments` and `getRecentStickers(TYPE_IMAGE, true)`).
/// - [LibraryContentSource.gifs]: the saved GIFs, every one, as the GIF
///   page's recents: in the reference the GIF recents are the saved GIFs.
///
/// What is on a list is described by `describe`; a key nothing describes (a
/// pack the host no longer ships, a feed's clip this session never listed)
/// is left out rather than listed as a cell nothing can draw.
///
/// The lists are what the host gives: the library's own, or a
/// `DeferredLibraryView` of it, so the page does not reorder under the
/// finger that is picking from it. Every change of a list publishes again.
///
/// It owns nothing: [dispose] only stops listening.
final class LibraryContentSource implements CollectionSource {
  /// The favourites and the recents of the stickers page.
  LibraryContentSource.stickers({
    required listen.ValueListenable<List<ContentKey>> recentStickers,
    required listen.ValueListenable<List<ContentKey>> favouriteStickers,
    DescribeContent describe = BundledPacks.describe,
  }) : this._([favouriteStickers, recentStickers], describe, (lists) {
         final [favourites, recents] = lists;
         final faved = favourites.toSet();
         return [
           (CollectionId.faved, favourites),
           (
             CollectionId.recent,
             recents
                 .where((key) => !faved.contains(key))
                 .take(shownRecentStickers)
                 .toList(),
           ),
         ];
       });

  /// The saved GIFs, as the recents of the GIF page.
  LibraryContentSource.gifs({
    required listen.ValueListenable<List<ContentKey>> savedGifs,
    DescribeContent describe = BundledPacks.describe,
  }) : this._(
         [savedGifs],
         describe,
         (lists) => [(CollectionId.recent, lists.single)],
       );

  LibraryContentSource._(this._lists, this._describe, this._arrange) {
    _collections = listen.ValueNotifier(_collect());
    for (final list in _lists) {
      list.addListener(_republish);
    }
  }

  /// How many recent stickers the page shows: the reference shows 20 of the
  /// 30 it keeps.
  static const int shownRecentStickers = 20;

  final List<listen.ValueListenable<List<ContentKey>>> _lists;
  final DescribeContent _describe;
  // The collections, by id, from the lists' values in the order given.
  final List<(CollectionId, List<ContentKey>)> Function(
    List<List<ContentKey>> lists,
  )
  _arrange;
  late final listen.ValueNotifier<List<Collection>> _collections;
  var _disposed = false;

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  // Everything is in memory: there is nothing to load, and no page after the
  // first.
  @override
  Future<void> load(CollectionId id) async {}

  @override
  Future<void> loadMore(CollectionId id) async {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final list in _lists) {
      list.removeListener(_republish);
    }
    _collections.dispose();
  }

  void _republish() {
    if (_disposed) return;
    _collections.value = _collect();
  }

  List<Collection> _collect() => List.unmodifiable([
    for (final (id, keys) in _arrange([for (final list in _lists) list.value]))
      Collection(
        id: id,
        metadata: const CollectionMetadata(flags: CollectionFlags.installed),
        contents: CollectionContents.loaded([
          for (final key in keys)
            if (_describe(key) case final descriptor?)
              CollectionItem.described(descriptor),
        ]),
      ),
  ]);
}
