import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:emoji_data/src/catalog/emoji_catalog.dart';
import 'package:emoji_data/src/collections/emoji_items.dart';
import 'package:emoji_data/src/collections/emoji_spoken_names.dart';
import 'package:emoji_data/src/search/keyword_index.dart';
import 'package:listen/listen.dart';

/// Emoji search as a [SearchSource]: a query over the keywords of an ordered
/// set of languages, merged into one ranked, paged results collection.
///
/// ## Matching
///
/// The packs of [languages] come from the [KeywordSource] (bundled packs, with
/// or without a host's on top; see `LayeredKeywordSource`). A language with no
/// pack is skipped, and two tags resolving to one pack count once. Query and
/// keywords are folded alike (case, punctuation and spacing do not matter). A
/// key matches at the best tier any of its keywords reaches in any language:
/// the keyword is the whole query (exact), starts with it (prefix), or has a
/// later word that does (later-token prefix). Flags and spoken names are
/// plain keywords, so `uzbekistan` finds the flag.
///
/// ## Ranking
///
/// Results are ordered by tier, then, within a tier, by recents frequency
/// (recent keys first, in the store's order, taken when the query runs), then
/// by palette order; keys the catalogue does not know come last. A key
/// appears once, however many languages or ways it matched.
///
/// ## Items
///
/// A hit on any key of an entry (its base or one of its variants) is one
/// result, shown as the variant the user chose for the entry, like the grid.
/// Emoji the [GlyphSupport] says the device cannot draw are left out. Each item carries the spoken name of its emoji from the first
/// of [languages] whose pack names it. Searching is not use: nothing is
/// recorded.
///
/// ## Lifecycle
///
/// Results follow the [SearchSource] contract. They also stay current: a
/// variant choice or glyph support change re-derives them, and a pack
/// arriving on [KeywordSource.changes] runs the current query again, both
/// without passing through `loading`. A failed query (a pack that exists but
/// cannot be read) is retried by searching the same text again.
final class EmojiSearchSource implements SearchSource {
  /// Creates a search over [catalog] answering from [keywords] for
  /// [languages], most preferred first.
  ///
  /// [pageSize] splits the results into pages (default: one page) and must be
  /// positive when given.
  EmojiSearchSource({
    required EmojiCatalog catalog,
    required KeywordSource keywords,
    required List<String> languages,
    required RecentsStore recents,
    required PreferenceStore preferences,
    GlyphSupport? glyphSupport,
    int? pageSize,
  }) : assert(
         pageSize == null || pageSize > 0,
         'A page size must be positive.',
       ),
       _catalog = catalog,
       _keywords = keywords,
       _languages = List<String>.unmodifiable(languages),
       _recents = recents,
       _preferences = preferences,
       _glyphSupport = glyphSupport,
       _pageSize = pageSize,
       _items = EmojiItems(
         catalog: catalog,
         preferences: preferences,
         glyphSupport: glyphSupport,
       ) {
    _keywords.changes.addListener(_rerun);
    _preferences.changes.addListener(_rederive);
    _glyphSupport?.changes.addListener(_rederive);
  }

  final EmojiCatalog _catalog;
  final KeywordSource _keywords;
  final List<String> _languages;
  final RecentsStore _recents;
  final PreferenceStore _preferences;
  final GlyphSupport? _glyphSupport;
  final int? _pageSize;
  final EmojiItems _items;

  final ValueNotifier<Collection> _results = ValueNotifier(
    const Collection(id: CollectionId.query('')),
  );
  final Expando<KeywordIndex> _indexes = Expando('KeywordIndex');

  String _query = '';
  // Each new query supersedes the one before: work for an older generation is
  // dropped when it lands.
  int _generation = 0;
  List<ContentKey> _ranked = const [];
  int _pages = 0;
  bool _loadingMore = false;
  bool _disposed = false;

  @override
  ValueListenable<Collection> get results => _results;

  @override
  Future<void> search(String query) async {
    if (_disposed) return;
    final retry = switch (_results.value.contents) {
      CollectionContents$Failed() => true,
      _ => false,
    };
    if (query == _query && !retry) return;
    _query = query;
    final generation = ++_generation;
    _ranked = const [];
    _pages = 0;
    final id = CollectionId.query(query);
    if (query.trim().isEmpty) {
      _results.value = Collection(id: id);
      return;
    }
    _results.value = Collection(id: id, contents: CollectionContents.loading);
    await _run(generation, id);
  }

  @override
  Future<void> loadMore() async {
    if (_disposed || _loadingMore) return;
    switch (_results.value.contents) {
      case CollectionContents$Loaded(nextPageToken: != null):
        break;
      case _:
        return;
    }
    _loadingMore = true;
    final generation = _generation;
    await Future<void>.value();
    _loadingMore = false;
    if (_disposed || generation != _generation) return;
    _pages++;
    _publishLoaded();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _keywords.changes.removeListener(_rerun);
    _preferences.changes.removeListener(_rederive);
    _glyphSupport?.changes.removeListener(_rederive);
    _results.dispose();
  }

  // Ranks the current query over the packs and publishes the first page, or
  // the failure. Dropped when a newer query started meanwhile.
  Future<void> _run(int generation, CollectionId id) async {
    final List<KeywordPack> packs;
    try {
      packs = await _packs();
    } on Object catch (error, stackTrace) {
      if (_disposed || generation != _generation) return;
      _results.value = Collection(
        id: id,
        contents: CollectionContents.failed(error, stackTrace),
      );
      return;
    }
    if (_disposed || generation != _generation) return;
    _items.spokenNames = EmojiSpokenNames(_catalog, packs);
    _ranked = _rank(_folded(_query), packs);
    _pages = 1;
    _publishLoaded();
  }

  // A pack arriving: run the current query again over the new keywords, with
  // no loading state in between since results are already on screen.
  void _rerun() {
    if (_disposed || _folded(_query).isEmpty) return;
    switch (_results.value.contents) {
      case CollectionContents$Loaded() || CollectionContents$Failed():
        break;
      case CollectionContents$Idle() || CollectionContents$Loading():
        return;
    }
    final generation = _generation;
    unawaited(() async {
      final List<KeywordPack> packs;
      try {
        packs = await _packs();
      } on Object catch (error, stackTrace) {
        // The results already on screen stay; the failure goes to the zone
        // like any other nobody awaits.
        Zone.current.handleUncaughtError(error, stackTrace);
        return;
      }
      if (_disposed || generation != _generation) return;
      _items.spokenNames = EmojiSpokenNames(_catalog, packs);
      _ranked = _rank(_folded(_query), packs);
      _publishLoaded();
    }());
  }

  void _rederive() {
    if (_disposed) return;
    if (_results.value.contents case CollectionContents$Loaded()) {
      _publishLoaded();
    }
  }

  Future<List<KeywordPack>> _packs() async {
    final found = await Future.wait([
      for (final language in _languages) _keywords.pack(language),
    ]);
    return [
      for (final pack in {...found.nonNulls}) pack,
    ];
  }

  List<ContentKey> _rank(String folded, List<KeywordPack> packs) {
    final best = <ContentKey, MatchTier>{};
    for (final pack in packs) {
      final index = _indexes[pack] ??= KeywordIndex(pack);
      for (final MapEntry(:key, value: tier) in index.match(folded).entries) {
        final known = best[key];
        if (known == null || tier.index < known.index) best[key] = tier;
      }
    }
    final recent = {
      for (final (rank, key)
          in _recents.recents(SemanticKind.unicodeEmoji).indexed)
        key: rank,
    };
    const last = 1 << 30;
    final keys = best.keys.toList()
      ..sort((a, b) {
        final byTier = best[a]!.index.compareTo(best[b]!.index);
        if (byTier != 0) return byTier;
        final byRecents = (recent[a] ?? last).compareTo(recent[b] ?? last);
        if (byRecents != 0) return byRecents;
        final byPalette = (_catalog.positionOf(a) ?? last).compareTo(
          _catalog.positionOf(b) ?? last,
        );
        return byPalette != 0 ? byPalette : a.encoded.compareTo(b.encoded);
      });
    return keys;
  }

  // Items of the ranked keys as the grid would show them, de-duplicated by the
  // key finally shown (a base and its chosen variant are one result).
  void _publishLoaded() {
    final seen = <ContentKey>{};
    final items = <CollectionItem>[];
    for (final key in _ranked) {
      final entry = _catalog.entryOf(key);
      // A hit on any spelling of an entry (the base, a tone, a gender) is a
      // hit on the entry, shown as the grid shows it. The page bakes only
      // what the grid shows, so a variant of its own would be a circle.
      final item = entry != null
          ? _items.itemOf(entry)
          : _items.itemForKey(key);
      if (item != null && seen.add(item.key)) items.add(item);
    }
    final size = _pageSize;
    final shown = switch (size) {
      final size? => (_pages * size).clamp(0, items.length),
      null => items.length,
    };
    _results.value = Collection(
      id: CollectionId.query(_query),
      contents: CollectionContents.loaded(
        items.sublist(0, shown),
        nextPageToken: shown < items.length ? PageToken('$shown') : null,
      ),
    );
  }

  static String _folded(String query) => KeywordIndex.fold(query);
}
