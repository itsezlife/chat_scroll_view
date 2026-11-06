import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_content.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

// One list of Giphy clips that is loaded a page at a time: the part trending
// and search share. It owns no timer and no listener; [onChange] says that
// [contents] changed.
//
// Paging by offset lives here and nowhere else: the page token it publishes
// is the next offset as text, which only this class reads back.
final class _Feed {
  _Feed({
    required Future<GiphyPage> Function(int offset) fetch,
    required GiphyContent content,
    required void Function() onChange,
  }) : _fetch = fetch,
       _content = content,
       _onChange = onChange;

  final Future<GiphyPage> Function(int offset) _fetch;
  final GiphyContent _content;
  final void Function() _onChange;
  final Set<ContentKey> _seen = {};
  var _paging = false;
  var _closed = false;

  CollectionContents contents = CollectionContents.idle;

  // The first page. On a feed that failed it asks again; on one that is
  // loading or loaded it does nothing.
  Future<void> first() async {
    if (_closed ||
        contents is CollectionContents$Loading ||
        contents is CollectionContents$Loaded) {
      return;
    }
    contents = CollectionContents.loading;
    _onChange();
    final GiphyPage page;
    try {
      page = await _fetch(0);
    } on Object catch (error, stack) {
      // A failure is a state of the collection, which the page shows with a
      // retry; the cause is kept in it for the host to log.
      if (_closed) return;
      contents = CollectionContents.failed(error, stack);
      _onChange();
      return;
    }
    if (_closed) return;
    _seen.clear();
    contents = CollectionContents.loaded(
      _described(page),
      nextPageToken: _tokenOf(page),
    );
    _onChange();
  }

  // The page the loaded contents name. A page that fails leaves them as they
  // were, token included, so a later call tries again.
  Future<void> more() async {
    final current = contents;
    if (_closed ||
        _paging ||
        current is! CollectionContents$Loaded ||
        current.nextPageToken == null) {
      return;
    }
    _paging = true;
    try {
      final page = await _fetch(int.parse(current.nextPageToken!.value));
      if (_closed) return;
      contents = CollectionContents.loaded([
        ...current.items,
        ..._described(page),
      ], nextPageToken: _tokenOf(page));
      _onChange();
    } on GiphyFailure {
      // Stays loaded with the same token.
    } finally {
      _paging = false;
    }
  }

  void close() => _closed = true;

  // The page's clips, remembered, minus those the list already holds: Giphy's
  // pages can overlap, and the seam lists no key twice.
  List<CollectionItem> _described(GiphyPage page) {
    _content.remember(page.clips);
    return [
      for (final clip in page.clips)
        if (_seen.add(GiphyContent.keyOf(clip.id)))
          CollectionItem.described(_content.describe(clip)),
    ];
  }

  static PageToken? _tokenOf(GiphyPage page) =>
      page.nextOffset == null ? null : PageToken('${page.nextOffset}');
}

/// The trending GIFs of Giphy as the one collection a page lists, paged by
/// offset as the page asks for more.
///
/// The collection starts idle and loads when the page asks, so a host that
/// never opens the GIF page never makes the request. A first load that fails
/// is a failed collection (the page offers a retry, and [load] on it tries
/// again); a later page that fails leaves the loaded clips as they are.
///
/// Each clip it lists is remembered in [content], which the asset pipeline's
/// fetcher and resolver read.
final class GiphyGifSource implements CollectionSource {
  /// Lists the trending clips of [client], remembering them in [content].
  GiphyGifSource({required GiphyClient client, required GiphyContent content})
    : _collections = listen.ValueNotifier(const []) {
    _feed = _Feed(
      fetch: (offset) => client.trending(offset: offset),
      content: content,
      onChange: _publish,
    );
    _publish();
  }

  /// The collection the trending clips are listed as.
  static const CollectionId id = CollectionId.set('giphy_trending');

  /// The collection's title.
  static const String title = 'Trending';

  final listen.ValueNotifier<List<Collection>> _collections;
  late final _Feed _feed;
  var _disposed = false;

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  @override
  Future<void> load(CollectionId id) =>
      id == GiphyGifSource.id ? _feed.first() : Future.value();

  @override
  Future<void> loadMore(CollectionId id) =>
      id == GiphyGifSource.id ? _feed.more() : Future.value();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _feed.close();
    _collections.dispose();
  }

  void _publish() {
    if (_disposed) return;
    _collections.value = List.unmodifiable([
      Collection(
        id: id,
        metadata: const CollectionMetadata(title: title),
        contents: _feed.contents,
      ),
    ]);
  }
}

/// Search of Giphy as the one results collection the GIF page lists while the
/// user types, paged by offset.
///
/// A new query drops the one before it: its reply, if it still comes, is not
/// published. Blank text clears to idle without a request.
final class GiphyGifSearch implements SearchSource {
  /// Searches [client], remembering the clips found in [content].
  GiphyGifSearch({required GiphyClient client, required GiphyContent content})
    : _client = client,
      _content = content;

  final GiphyClient _client;
  final GiphyContent _content;
  final _results = listen.ValueNotifier(
    const Collection(id: CollectionId.query('')),
  );
  _Feed? _feed;
  var _disposed = false;

  @override
  listen.ValueListenable<Collection> get results => _results;

  @override
  Future<void> search(String query) async {
    final id = CollectionId.query(query);
    if (_disposed || _results.value.id == id) return;
    _feed?.close();
    if (query.trim().isEmpty) {
      _feed = null;
      _results.value = Collection(id: id);
      return;
    }
    final feed = _feed = _Feed(
      fetch: (offset) => _client.search(query, offset: offset),
      content: _content,
      onChange: () => _publish(id),
    );
    await feed.first();
  }

  @override
  Future<void> loadMore() async => _feed?.more();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _feed?.close();
    _results.dispose();
  }

  void _publish(CollectionId id) {
    if (_disposed) return;
    _results.value = Collection(id: id, contents: _feed!.contents);
  }
}
