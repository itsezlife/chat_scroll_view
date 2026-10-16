import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/snapshot/catalog_snapshot_builder.dart';
import 'package:panel_shell/panel_shell.dart';

/// The state behind a [CatalogPage]: what the catalogue shows, and what the page
/// does when the catalogue asks for more.
///
/// It owns no widget and no scroll position. Its inputs are the data sources,
/// the policy, the panel strings, the page's connection to the shell and the
/// catalogue's scroll events; its outputs are the [snapshots] the viewport
/// shows and the loads, searches and reports it causes.
///
/// ## What the catalogue shows
///
/// While browsing, the collections of the [source] (as the policy filters
/// them), one section each. While search is open **and the query is not
/// empty** and a [searchSource] exists, one section: the search results.
/// Search open with an empty query still browses; under the touch arrangement
/// the policy may narrow what it shows then, under the pointer arrangement it
/// shows what it always does.
///
/// Results of an earlier query stay up while the next one is searched
/// (typing does not flash skeletons); before any results exist for the first
/// query, the section is loading.
///
/// ## Loading
///
/// Nothing is loaded up front. A section announces itself when an edge of it
/// comes near the viewport (`PanelCatalogSectionNearViewport`) and the model
/// answers:
///
/// - an idle or failed collection is loaded (a failed one is retried when its
///   edge is announced again, that is, when the user scrolls back to it, never
///   in a loop);
/// - a loaded collection with a next page is paged on its **trailing** edge;
/// - a collection that is loading, or loaded with nothing more, is left alone.
///
/// Search results page the same way through the [searchSource].
///
/// ## Search
///
/// The model follows the shell's query through a [DebouncedSearch]: it
/// reports progress and, when results for the current query land, their count
/// once (paging does not announce again).
///
/// ## Replacing inputs
///
/// [source], [searchSource], [policy], [strings] and [arrangement] can change while the page
/// lives. Each takes effect at once; nothing is kept of the old source.
final class CatalogPageModel {
  /// A model that shows [source], asks [policy] for the kind-specific
  /// decisions and reports through [host].
  ///
  /// [events] are the catalogue's scroll events. The model starts following
  /// all of its inputs.
  CatalogPageModel({
    required CollectionSource source,
    required CatalogPagePolicy policy,
    required PanelStrings strings,
    required PanelPageHost host,
    required Stream<PanelCatalogScrollEvent> events,
    SearchSource? searchSource,
    PanelArrangement arrangement = PanelArrangement.touch,
    Duration searchDebounce = DebouncedSearch.defaultDebounce,
  }) : _source = source,
       _arrangement = arrangement,
       _searchSource = searchSource,
       _policy = policy,
       _strings = strings,
       _host = host,
       _builder = CatalogSnapshotBuilder(policy: policy) {
    _debounced = DebouncedSearch<void>(
      search: (query) => _searchSource?.search(query) ?? Future<void>.value(),
      onResult: (_, _) {},
      onCleared: _clearSearch,
      debounce: searchDebounce,
    );
    _debounced.busy.addListener(_reportBusy);
    _source.collections.addListener(_onSourceChanged);
    _searchSource?.results.addListener(_onResultsChanged);
    _host.search.addListener(_onSearchState);
    _eventSubscription = events.listen(_onEvent);
    _syncSearchState();
    _snapshots = ValueNotifier(_build());
  }

  final PanelPageHost _host;
  late final StreamSubscription<PanelCatalogScrollEvent> _eventSubscription;
  final CatalogSnapshotBuilder _builder;
  late final DebouncedSearch<void> _debounced;
  late final ValueNotifier<CatalogSnapshot> _snapshots;
  final _showsResults = ValueNotifier<bool>(false);
  final _entries = ValueNotifier<List<CatalogStripEntry>>(const []);

  CollectionSource _source;
  SearchSource? _searchSource;
  CatalogPagePolicy _policy;
  PanelStrings _strings;
  PanelArrangement _arrangement;
  var _searchOpen = false;
  var _query = '';
  CollectionId? _announced;
  var _disposed = false;

  /// What the viewport shows. A new snapshot per change, never an edit.
  ValueListenable<CatalogSnapshot> get snapshots => _snapshots;

  /// Whether the catalogue shows search results rather than the collections.
  ValueListenable<bool> get showsResults => _showsResults;

  /// The sections being browsed, for the page's top strip. Empty while search
  /// results are shown.
  ValueListenable<List<CatalogStripEntry>> get stripEntries => _entries;

  /// The collection behind section [sectionId] of the current catalogue, or
  /// null.
  Collection? collectionOf(String sectionId) =>
      _builder.collectionOf(sectionId);

  /// The index of section [sectionId] in the current catalogue, or null.
  int? sectionIndexOf(String sectionId) {
    final sections = _snapshots.value.sections;
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].id == sectionId) return i;
    }
    return null;
  }

  // --- Replaceable inputs ---------------------------------------------------

  /// The source of the browsed collections.
  CollectionSource get source => _source;
  set source(CollectionSource next) {
    if (_disposed || identical(_source, next)) return;
    _source.collections.removeListener(_onSourceChanged);
    _source = next;
    _source.collections.addListener(_onSourceChanged);
    _republish();
  }

  /// The source of search results, or null for a page that does not search.
  SearchSource? get searchSource => _searchSource;
  set searchSource(SearchSource? next) {
    if (_disposed || identical(_searchSource, next)) return;
    _searchSource?.results.removeListener(_onResultsChanged);
    _searchSource = next;
    _searchSource?.results.addListener(_onResultsChanged);
    _announced = null;
    if (next != null && _query.isNotEmpty) unawaited(next.search(_query));
    _republish();
  }

  /// The policy of the kind of content the page shows.
  CatalogPagePolicy get policy => _policy;
  set policy(CatalogPagePolicy next) {
    if (_disposed || identical(_policy, next)) return;
    _policy = next;
    _builder.policy = next;
    _republish();
  }

  /// The panel strings of the host's language.
  PanelStrings get strings => _strings;
  set strings(PanelStrings next) {
    if (_disposed || identical(_strings, next)) return;
    _strings = next;
    _republish();
  }

  /// How the page's chrome is arranged. Under an arrangement that does not
  /// narrow an empty search the policy is never told search is open.
  PanelArrangement get arrangement => _arrangement;
  set arrangement(PanelArrangement next) {
    if (_disposed || _arrangement == next) return;
    _arrangement = next;
    _republish();
  }

  // --- Following the inputs -------------------------------------------------

  void _onSourceChanged() {
    if (!_showsResults.value) _republish();
  }

  void _onResultsChanged() {
    if (_showsResults.value) _republish();
    _announceResults();
  }

  void _onSearchState() {
    final changed = _syncSearchState();
    if (!changed) return;
    _debounced.update(_searchOpen ? _query : '');
    _republish();
  }

  /// Takes the parts of the shell's search state the catalogue depends on and
  /// says whether any changed.
  bool _syncSearchState() {
    final state = _host.search.value;
    final open = state.isOpen;
    final query = open ? state.query.trim() : '';
    final changed = open != _searchOpen || query != _query;
    _searchOpen = open;
    _query = query;
    return changed;
  }

  void _clearSearch() {
    _announced = null;
    unawaited(_searchSource?.search('') ?? Future<void>.value());
  }

  void _reportBusy() => _host.reportSearchProgress(busy: _debounced.busy.value);

  void _announceResults() {
    final results = _searchSource?.results.value;
    if (results == null || _query.isEmpty) return;
    if (results.id != CollectionId.query(_query) || _announced == results.id) {
      return;
    }
    if (results.contents case CollectionContents$Loaded(:final items)) {
      _announced = results.id;
      _host.reportSearchResultCount(items.length);
    }
  }

  // --- Near-viewport answers ------------------------------------------------

  void _onEvent(PanelCatalogScrollEvent event) {
    if (event case PanelCatalogSectionNearViewport(
      :final sectionId,
      :final edge,
    )) {
      _onSectionNear(sectionId, edge);
    }
  }

  void _onSectionNear(String sectionId, CatalogSectionEdge edge) {
    final collection = _builder.collectionOf(sectionId);
    if (collection == null) return;
    final trailing = edge == CatalogSectionEdge.trailing;
    final contents = collection.contents;
    if (_showsResults.value) {
      if (trailing && _hasNextPage(contents)) {
        unawaited(_searchSource?.loadMore() ?? Future<void>.value());
      }
      return;
    }
    switch (contents) {
      case CollectionContents$Idle() || CollectionContents$Failed():
        unawaited(_source.load(collection.id));
      case CollectionContents$Loaded() when trailing && _hasNextPage(contents):
        unawaited(_source.loadMore(collection.id));
      case CollectionContents$Loaded() || CollectionContents$Loading():
        break;
    }
  }

  bool _hasNextPage(CollectionContents contents) => switch (contents) {
    CollectionContents$Loaded(nextPageToken: != null) => true,
    _ => false,
  };

  // --- Building the catalogue -----------------------------------------------

  void _republish() {
    _snapshots.value = _build();
  }

  CatalogSnapshot _build() {
    final results = _searchSource != null && _query.isNotEmpty;
    _showsResults.value = results;
    final collections = results
        ? [_resultsFor(_query)]
        : _policy.visibleCollections(
            _source.collections.value,
            searchOpen: _searchOpen && _arrangement.narrowsEmptySearch,
          );
    final snapshot = _builder.build(collections, strings: _strings);
    _entries.value = results
        ? const []
        : List.unmodifiable([
            for (final collection in collections)
              CatalogStripEntry(
                sectionId: _policy.sectionIdOf(collection),
                collection: collection,
              ),
          ]);
    return snapshot;
  }

  Collection _resultsFor(String query) {
    final current = _searchSource!.results.value;
    if (current.id case CollectionId$Query(
      :final text,
    ) when text.trim().isNotEmpty) {
      return current;
    }
    return Collection(
      id: CollectionId.query(query),
      contents: CollectionContents.loading,
    );
  }

  /// Stops following every input and releases what the model owns.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_eventSubscription.cancel());
    _host.search.removeListener(_onSearchState);
    _source.collections.removeListener(_onSourceChanged);
    _searchSource?.results.removeListener(_onResultsChanged);
    _debounced
      ..busy.removeListener(_reportBusy)
      ..dispose();
    _snapshots.dispose();
    _showsResults.dispose();
    _entries.dispose();
  }
}
