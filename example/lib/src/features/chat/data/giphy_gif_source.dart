import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_content.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

// One list of Giphy clips that is loaded a page at a time: the part trending
// and search share. It owns no timer and no listener; [onChange] says that
// [contents] changed.
//
// A page's rows are added once their stills are in memory, or after
// [stillWait]. With [readAhead], the page after the one just added is fetched
// at once, its stills too, and [more] adds it from there without waiting for
// the network.
//
// Paging by offset lives here and nowhere else: the page token it publishes
// is the next offset as text, which only this class reads back.
final class _Feed {
  _Feed({
    required Future<GiphyPage> Function(int offset) fetch,
    required GiphyContent content,
    required void Function() onChange,
    required Duration stillWait,
    required bool readAhead,
  }) : _fetch = fetch,
       _content = content,
       _onChange = onChange,
       _stillWait = stillWait,
       _readAhead = readAhead;

  final Future<GiphyPage> Function(int offset) _fetch;
  final GiphyContent _content;
  final void Function() _onChange;
  final Duration _stillWait;
  final bool _readAhead;
  final Set<ContentKey> _seen = {};
  var _paging = false;
  var _closed = false;
  // The page read ahead and its offset.
  (int, Future<GiphyPage>)? _ahead;

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
      page = await _page(0);
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
    _readNext(page);
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
      final offset = int.parse(current.nextPageToken!.value);
      final ahead = _ahead;
      _ahead = null;
      final page = await (ahead != null && ahead.$1 == offset
          ? ahead.$2
          : _page(offset));
      if (_closed) return;
      contents = CollectionContents.loaded([
        ...current.items,
        ..._described(page),
      ], nextPageToken: _tokenOf(page));
      _onChange();
      _readNext(page);
    } on GiphyFailure {
      // Stays loaded with the same token.
    } finally {
      _paging = false;
    }
  }

  void close() => _closed = true;

  // The clips at [offset], with their stills in memory or [_stillWait] spent.
  Future<GiphyPage> _page(int offset) async {
    final page = await _fetch(offset);
    if (!_closed) {
      await _content.prepareStills(page.clips, within: _stillWait);
    }
    return page;
  }

  // Starts fetching the page after [page], unless it was the last. A failure
  // is [more]'s to meet: it is kept in the future, not reported here.
  void _readNext(GiphyPage page) {
    final next = page.nextOffset;
    if (!_readAhead || _closed || next == null) return;
    final future = _page(next)..ignore();
    _ahead = (next, future);
  }

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
/// fetcher and resolver read. A page's rows are added with their stills
/// fetched, waiting up to [stillWait] for them, and with [readAhead] the next
/// page is fetched while the current one shows (see [defaultStillWait]).
final class GiphyGifSource implements CollectionSource {
  /// Lists the trending clips of [client], remembering them in [content].
  GiphyGifSource({
    required GiphyClient client,
    required GiphyContent content,
    Duration stillWait = GiphyGifSource.defaultStillWait,
    bool readAhead = true,
  }) : _collections = listen.ValueNotifier(const []) {
    _feed = _Feed(
      fetch: (offset) => client.trending(offset: offset),
      content: content,
      onChange: _publish,
      stillWait: stillWait,
      readAhead: readAhead,
    );
    _publish();
  }

  /// How long a page of clips waits for its stills before its rows are added
  /// anyway.
  ///
  /// A still is a few KB from Giphy's media host, which a phone fetches in one
  /// or two hundred milliseconds once connected and in about twice that on the
  /// first request of a session (a new connection). 500 ms lets that first
  /// request finish, so a cold first page shows its blurred stills rather than
  /// boxes, while keeping the page's whole wait (the API's answer, then this)
  /// under a second. A still later than this shows the box until it arrives,
  /// as before. Pages read ahead wait the same, out of sight.
  static const Duration defaultStillWait = Duration(milliseconds: 500);

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
/// published. Blank text clears to idle without a request. Stills and the
/// next page are fetched as [GiphyGifSource] fetches them.
///
/// The last [cachedQueries] queries are kept with what they found, so going
/// back to one (deleting the letter just typed) shows its results at once and
/// asks nothing, as the reference clients keep a result per query; one that
/// failed is asked again.
final class GiphyGifSearch implements SearchSource {
  /// Searches [client], remembering the clips found in [content].
  GiphyGifSearch({
    required GiphyClient client,
    required GiphyContent content,
    Duration stillWait = GiphyGifSource.defaultStillWait,
    bool readAhead = true,
    this.cachedQueries = 16,
  }) : _client = client,
       _content = content,
       _stillWait = stillWait,
       _readAhead = readAhead;

  /// How many queries are kept with their results.
  final int cachedQueries;

  final GiphyClient _client;
  final GiphyContent _content;
  final Duration _stillWait;
  final bool _readAhead;
  // The queries kept, the least recently searched first.
  final _feeds = <String, _Feed>{};
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
    if (query.trim().isEmpty) {
      _feed = null;
      _results.value = Collection(id: id);
      return;
    }
    // A feed left for another query stays in the cache and goes on loading,
    // but publishes only while it is the current one.
    late final _Feed feed;
    feed = _feed =
        _feeds.remove(query) ??
        _Feed(
          fetch: (offset) => _client.search(query, offset: offset),
          content: _content,
          onChange: () {
            if (identical(_feed, feed)) _publish(id);
          },
          stillWait: _stillWait,
          readAhead: _readAhead,
        );
    _feeds[query] = feed;
    while (_feeds.length > cachedQueries) {
      _feeds.remove(_feeds.keys.first)!.close();
    }
    // A feed that loaded, or is loading, is shown as it is; [_Feed.first]
    // publishes for any other.
    if (feed.contents
        case CollectionContents$Loaded() || CollectionContents$Loading()) {
      _publish(id);
    }
    await feed.first();
  }

  @override
  Future<void> loadMore() async => _feed?.more();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final feed in _feeds.values) {
      feed.close();
    }
    _results.dispose();
  }

  void _publish(CollectionId id) {
    if (_disposed) return;
    _results.value = Collection(id: id, contents: _feed!.contents);
  }
}
