import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart' show CatalogLeafRemoveBadge;
import 'package:panel_pages/src/gifs/gif_row_layout.dart';
import 'package:panel_pages/src/menu/catalog_context_menu.dart';
import 'package:panel_pages/src/preview/catalog_content_preview.dart';
import 'package:panel_pages/src/preview/content_preview_item.dart';
import 'package:panel_pages/src/preview/content_preview_menu.dart';
import 'package:panel_pages/src/preview/content_preview_session.dart';
import 'package:panel_pages/src/stickers/stickers_page_policy.dart';
import 'package:panel_shell/panel_shell.dart';

/// The GIF page: the clips of [source] in justified
/// rows ([GifRowLayout]), each playing silently on a loop while it is in view.
///
/// ## What it is made of
///
/// A scroll view of rows, not the catalogue viewport: the viewport lays a
/// section out as a grid of equal cells, and rows of clips of different
/// proportions are not one. The page keeps the rest of a page's contract: it
/// loads each collection as the source lists it (and pages one that has more
/// as the end comes near), reports every pick to the shell as a pick of the
/// clip's own kind, reports its scroll as the typed activity that drives the
/// bottom bar, goes back to its start when its tab is chosen again, and names
/// every clip for assistive technology.
///
/// ## Its place
///
/// The offset the page was left at is kept in the host's controllers, so a
/// page the pager dropped for another tab, or a presentation switch rebuilt,
/// opens where it was left (one list is kept per page).
///
/// A fresh open of the panel (`PanelPageHost.freshOpen`) is the exception: the
/// list goes back to its start at once, mounted or not, each time its panel is shown. A close that
/// is followed by an open that is not fresh (a popup, a dock) keeps the place.
///
/// ## The bottom bar
///
/// Only reading back brings the bar back: the page never reports a rest at
/// an end of its list as one. The bottom tabs rest at either end of
/// the emoji grid alone; over GIFs they follow the distance scrolled.
///
/// ## Sections
///
/// The recents come first, unless they are known to be empty, and every other
/// collection after them. A collection's title heads it, except the first
/// section's: only what follows its recents gets a title.
///
/// ## Playback
///
/// Only the rows in view are built (`cacheExtent` 0), and each clip attaches
/// to the host's asset cache while it is built, so the cache's pause layers
/// and its limit on what plays at once (the playback clock and budgets of
/// `catalog_assets`) are the only playback policy: a clip that is scrolled out
/// of view detaches and stops. A clip's stand-in is the cache's.
///
/// ## Arrivals
///
/// What a change lists that was not listed before fades in
/// (`DefaultItemAnimator`'s add, 120 ms), and the cells that stay move and
/// resize to their new places in the row they are in (its move, the
/// `listTransition` motion role), never cross-faded: a page that arrives
/// reflows the last row and fades the clips it adds in, and results that
/// replace others fade theirs in. What a page lists when it is built shows at
/// once.
///
/// ## Search
///
/// A page given a [searchSource] follows the shell's search (the host's
/// `PanelPage` declares [searchCapabilities]): once the typed text has paused
/// ([searchDebounce]) the source is asked for it, and its results are listed
/// in place of the collections until search closes. Results are paged as the
/// end comes near, like a collection.
///
/// What is listed stays until the results of the new text arrive, while the
/// field shows progress; they then replace it at once, from the start of the
/// list. Open with no text,
/// search lists the [searchSuggestions] the host gives (its trending clips
/// there), or the collections when it gives none.
///
/// Such a page places the shell's search field itself, pinned above its list
/// on the shell's background: the clips start under it and are clipped at its
/// edge (the background may be see-through, so nothing scrolls behind it), and
/// the field moves with the page when the pager swipes. Its
/// hairline shows except while search is open with the list at its start, as
/// the field draws its shadow. The field needs the `PanelSearchFieldScope`
/// a `PanelShell` gives its pages.
///
/// ## When there is nothing to show
///
/// A collection that failed to load, or a search that failed, ends the list
/// with the panel's [PanelStrings.gifsFailed] and a retry button; a search
/// that found nothing, and a page whose collections all loaded with no clip
/// to list (no recents and no provider), say [PanelStrings.gifsEmpty]. Clips already listed stay
/// above it. The [attribution], when the host gives one, heads the list: a
/// provider's terms may require its name on the content it supplies, and the
/// page knows no provider.
///
/// ## Preview
///
/// Given [previews], a press held on a clip opens the content preview
/// (`ContentPreviewSession`): a finger after 200 ms, with its menu after 2 s
/// or a drag up; a mouse after 500 ms, without one, and a right click opens
/// the same items as a context menu. Its items are requests to the host
/// (`panelPreviewActions`): send is a pick, save and delete library edits.
///
/// Not ported: the category chips.
///
/// Requires the chrome theme, strings and motion scopes.
class GifPage extends StatefulWidget {
  /// The GIF page of [host], showing the clips of [source] and drawing through
  /// [assets].
  const GifPage({
    required this.host,
    required this.source,
    required this.assets,
    this.searchSource,
    this.searchSuggestions,
    this.searchDebounce = DebouncedSearch.defaultDebounce,
    this.attribution,
    this.previews,
    super.key,
  });

  /// What the host's `PanelPage` declares for a page given a [searchSource]:
  /// search, with the field the page places itself.
  static const PageCapabilities searchCapabilities = PageCapabilities(
    search: true,
    searchPlacement: SearchPlacement.inline,
  );

  /// The page's connection to the shell; fixed for the life of the widget.
  final PanelPageHost host;

  /// The clips, the recents first when the host keeps some: one collection
  /// each. The recents are `CollectionId.recent`.
  final CollectionSource source;

  /// The asset cache the clips draw through.
  final AssetCacheScope assets;

  /// Where search results come from, or null for a page that does not search.
  final SearchSource? searchSource;

  /// What search lists while it is open with no text, loaded once it is
  /// first listed, or null to list the collections of [source] there too.
  final CollectionSource? searchSuggestions;

  /// How long typing must pause before a search runs.
  final Duration searchDebounce;

  /// The line that heads the list, such as the name of the provider the clips
  /// come from, or null for none. Shown as given: it is not translated.
  final String? attribution;

  /// The host's handle on content previews, or null for no preview.
  final ContentPreviewController? previews;

  @override
  State<GifPage> createState() => _GifPageState();
}

// What one line of the list is: a header or a row of one section.
sealed class _Line {
  const _Line(this.height);
  final double height;
}

final class _HeaderLine extends _Line {
  const _HeaderLine(this.title) : super(StickersPagePolicy.headerExtent);
  final String title;
}

final class _NoticeLine extends _Line {
  const _NoticeLine(this.text, {this.onRetry}) : super(_noticeExtent);
  final String text;
  final VoidCallback? onRetry;
}

final class _AttributionLine extends _Line {
  const _AttributionLine(this.text) : super(_attributionExtent);
  final String text;
}

const double _noticeExtent = 120;
const double _attributionExtent = 36;

final class _RowLine extends _Line {
  _RowLine(this.collection, this.row) : super(row.height);
  final Collection collection;
  final GifRow row;
}

// Which of its lists the page shows, unless it shows the results of a query
// (their collection id).
enum _Listed { collections, suggestions }

// What the page keeps across being unmounted: the offset it was left at,
// back at the start on a fresh open whether or not the page is mounted then.
final class _GifPageKept implements PanelPageController {
  _GifPageKept(this._freshOpen) {
    _freshOpen.addListener(_onFreshOpen);
  }

  final listen.Listenable _freshOpen;
  double offset = 0;

  void _onFreshOpen() => offset = 0;

  @override
  void dispose() => _freshOpen.removeListener(_onFreshOpen);
}

class _GifPageState extends State<GifPage> with SingleTickerProviderStateMixin {
  // `DefaultItemAnimator`'s add duration: how long an added cell fades in.
  static const _appearDuration = Duration(milliseconds: 120);

  late final _GifPageKept _kept = _host.controllers.obtain(
    _host.pageId,
    () => _GifPageKept(_host.freshOpen),
  );
  late final _scroll = ScrollController(initialScrollOffset: _kept.offset);
  final _hairline = listen.ValueNotifier<bool>(true);
  var _lines = const <_Line>[];
  var _lineKey = (<Collection>[], 0.0, null as PanelStrings?, null as String?);
  // The width the lines' rows were grouped at, or null for their own.
  double? _lineGroup;
  Object? _lineListed;
  // What is listed (which list, and its collections); null before the first
  // listing.
  ({Object id, List<Collection> collections})? _listed;
  // The clips the last change listed that were not listed before: they fade
  // in on [_appear].
  var _fresh = const <ContentKey>{};
  late final AnimationController _appear;
  // Whether the cells of the lines last laid out move to their places: not
  // when the width changed or another list replaced the one shown.
  var _moveCells = false;
  late DebouncedSearch<void> _debounced;
  final _menu = CatalogContextMenuController();
  ContentPreviewSession? _preview;
  // The cells laid out now, which a pointer preview slides between.
  final _cells = <_CellState>{};
  var _query = '';
  String? _announced;

  PanelPageHost get _host => widget.host;
  CollectionSource get _source => widget.source;
  SearchSource? get _search => widget.searchSource;
  CollectionSource? get _suggestions => widget.searchSuggestions;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: _appearDuration,
      value: 1,
    );
    _source.collections.addListener(_onCollections);
    _suggestions?.collections.addListener(_onCollections);
    _host.reselected.addListener(_onReselected);
    _host.freshOpen.addListener(_onFreshOpen);
    _startSearch();
    _onCollections();
  }

  void _startSearch() {
    _debounced = DebouncedSearch<void>(
      search: (query) => _search?.search(query) ?? Future<void>.value(),
      onResult: (_, _) {},
      onCleared: () => unawaited(_search?.search('') ?? Future<void>.value()),
      debounce: widget.searchDebounce,
    );
    _debounced.busy.addListener(_reportBusy);
    _search?.results.addListener(_onResults);
    _host.search.addListener(_onSearchState);
    _syncHairline();
    _syncQuery();
    _debounced.update(_query);
  }

  void _stopSearch() {
    _host.search.removeListener(_onSearchState);
    _search?.results.removeListener(_onResults);
    _debounced.busy.removeListener(_reportBusy);
    _debounced.dispose();
  }

  @override
  void didUpdateWidget(GifPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      oldWidget.source.collections.removeListener(_onCollections);
      widget.source.collections.addListener(_onCollections);
      _onCollections();
    }
    if (!identical(oldWidget.searchSuggestions, widget.searchSuggestions)) {
      oldWidget.searchSuggestions?.collections.removeListener(_onCollections);
      widget.searchSuggestions?.collections.addListener(_onCollections);
      _onCollections();
    }
    if (!identical(oldWidget.searchSource, widget.searchSource)) {
      oldWidget.searchSource?.results.removeListener(_onResults);
      _host.search.removeListener(_onSearchState);
      _debounced.busy.removeListener(_reportBusy);
      _debounced.dispose();
      _startSearch();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _stopSearch();
    _source.collections.removeListener(_onCollections);
    _suggestions?.collections.removeListener(_onCollections);
    _host.reselected.removeListener(_onReselected);
    _host.freshOpen.removeListener(_onFreshOpen);
    _preview?.cancel();
    _menu.dispose();
    _appear.dispose();
    _scroll.dispose();
    _hairline.dispose();
    super.dispose();
  }

  // --- Loading --------------------------------------------------------------

  // Loads what the page lists and has not loaded: the collections from the
  // start, the suggestions once search lists them.
  void _onCollections() {
    for (final source in [_source, if (_suggesting) ?_suggestions]) {
      for (final collection in source.collections.value) {
        if (collection.contents is CollectionContents$Idle) {
          unawaited(source.load(collection.id));
        }
      }
    }
    _relist();
  }

  // The source of what is listed, unless it is search results.
  CollectionSource? get _listedSource => switch (_listed?.id) {
    _Listed.collections => _source,
    _Listed.suggestions => _suggestions,
    _ => null,
  };

  // --- Search ---------------------------------------------------------------

  // The text the page searches for: the shell's, trimmed, while search is open
  // and the page has a source to ask. Says whether it changed.
  bool _syncQuery() {
    final state = _host.search.value;
    final query = _search != null && state.isOpen ? state.query.trim() : '';
    final changed = query != _query;
    _query = query;
    return changed;
  }

  void _onSearchState() {
    _syncHairline();
    if (_syncQuery()) _debounced.update(_query);
    // Opening search lists the suggestions, which may need loading.
    _onCollections();
  }

  // Whether search is open with no text, for a page given suggestions.
  bool get _suggesting =>
      _suggestions != null &&
      _search != null &&
      _host.search.value.isOpen &&
      _query.isEmpty;

  void _reportBusy() => _host.reportSearchProgress(busy: _debounced.busy.value);

  // The results, once they are those of the text in the field and have
  // arrived: between a keystroke and the reply they are the last query's, or
  // the new one's still loading, and what was listed stays.
  Collection? get _results {
    final results = _search?.results.value;
    if (_query.isEmpty || results == null) return null;
    if (results.id != CollectionId.query(_query)) return null;
    return switch (results.contents) {
      CollectionContents$Loaded() || CollectionContents$Failed() => results,
      _ => null,
    };
  }

  void _onResults() {
    if (_results?.contents case CollectionContents$Loaded(
      :final items,
    ) when _announced != _query) {
      _announced = _query;
      _host.reportSearchResultCount(items.length);
    }
    _relist();
  }

  // --- Listing --------------------------------------------------------------

  // Works out what the page lists now. Another list than before starts at the
  // top at once; clips no list showed before fade in, unless this is the
  // first listing (a page built again shows what it had at once).
  void _relist() {
    if (!mounted) return;
    final listed = _listing();
    final previous = _listed;
    _listed = listed;
    if (previous != null) {
      final before = {
        for (final collection in previous.collections)
          for (final item in _itemsOf(collection)) item.key,
      };
      final fresh = {
        for (final collection in listed.collections)
          for (final item in _itemsOf(collection))
            if (!before.contains(item.key)) item.key,
      };
      if (fresh.isNotEmpty) {
        _fresh = fresh;
        unawaited(_appear.forward(from: 0));
      }
      if (previous.id != listed.id && _scroll.hasClients) _scroll.jumpTo(0);
    }
    setState(() {});
  }

  ({Object id, List<Collection> collections}) _listing() {
    if (_query.isNotEmpty) {
      if (_results case final results?) {
        return (id: results.id, collections: [results]);
      }
      return _listed ??
          (id: CollectionId.query(_query), collections: const <Collection>[]);
    }
    if (_suggestions case final suggestions? when _suggesting) {
      return (
        id: _Listed.suggestions,
        collections: suggestions.collections.value,
      );
    }
    return (
      id: _Listed.collections,
      collections: [
        for (final collection in _source.collections.value)
          if (!_isEmptyRecents(collection)) collection,
      ],
    );
  }

  void _retry() {
    if (_listed?.id case CollectionId$Query(:final text)) {
      // A search is not retried by asking for the same text again, which the
      // source ignores: clearing it first makes the text new.
      _announced = null;
      unawaited(_search!.search('').then((_) => _search?.search(text)));
      return;
    }
    final source = _listedSource;
    if (source == null) return;
    for (final collection in source.collections.value) {
      if (collection.contents is CollectionContents$Failed) {
        unawaited(source.load(collection.id));
      }
    }
  }

  // The next page of every collection that has one, as the end comes near.
  void _loadMoreNearEnd() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.extentAfter > position.viewportDimension) return;
    final source = _listedSource;
    if (source == null) {
      if (_results?.contents case CollectionContents$Loaded(
        :final nextPageToken,
      ) when nextPageToken != null) {
        unawaited(_search!.loadMore());
      }
      return;
    }
    for (final collection in source.collections.value) {
      if (collection.contents case CollectionContents$Loaded(
        :final nextPageToken,
      ) when nextPageToken != null) {
        unawaited(source.loadMore(collection.id));
      }
    }
  }

  // At once, not animated: the panel is not on screen yet.
  void _onFreshOpen() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _onReselected() {
    if (!_scroll.hasClients) return;
    final motion = ChromeMotionScope.of(context).specOf(MotionRole.fade);
    unawaited(
      _scroll.animateTo(0, duration: motion.duration, curve: motion.curve),
    );
  }

  // --- Reporting ------------------------------------------------------------

  // The field's hairline: shown unless search is open and nothing has passed
  // under the field.
  void _syncHairline() {
    final offset = _scroll.hasClients ? _scroll.offset : _kept.offset;
    _hairline.value = !_host.search.value.isOpen || offset > 0.5;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    _kept.offset = notification.metrics.pixels;
    _syncHairline();
    switch (notification) {
      case ScrollUpdateNotification(:final scrollDelta?, :final dragDetails):
        _host.reportScrollActivity(
          dragDetails == null
              ? PageScrollActivity.fling(scrollDelta)
              : PageScrollActivity.drag(scrollDelta),
        );
        _loadMoreNearEnd();
      case ScrollEndNotification():
        _host.reportScrollActivity(const PageScrollActivity.idle());
      case _:
        break;
    }
    return false;
  }

  // --- Lines ----------------------------------------------------------------

  static bool _isEmptyRecents(Collection collection) =>
      collection.id == CollectionId.recent &&
      switch (collection.contents) {
        CollectionContents$Loaded(:final items) => items.isEmpty,
        _ => false,
      };

  static List<CollectionItem> _itemsOf(Collection collection) =>
      switch (collection.contents) {
        CollectionContents$Loaded(:final items) => items,
        _ => const [],
      };

  // The lines for [width], rebuilt only when what they are a function of
  // changes: the collections listed, the width, the strings and the
  // attribution.
  List<_Line> _linesFor(
    double width,
    PanelStrings strings, {
    double? groupWidth,
  }) {
    final listed = _listed!;
    final collections = listed.collections;
    final stale =
        _lineGroup != groupWidth ||
        _lineKey.$2 != width ||
        !identical(_lineKey.$3, strings) ||
        _lineKey.$4 != widget.attribution ||
        !_sameCollections(_lineKey.$1, collections);
    if (!stale) return _lines;
    // Cells move to their places for a change of what one list holds; a new
    // width or another list puts them there at once.
    _moveCells = _lineKey.$2 == width && _lineListed == listed.id;
    _lineListed = listed.id;
    _lineKey = (collections, width, strings, widget.attribution);
    _lineGroup = groupWidth;
    // A collection that failed ends its own rows with the failure, so it is
    // read where the clips would have been, not after the ones that follow.
    final rows = [
      for (final (i, collection) in collections.indexed) ...[
        if (i > 0 && (collection.metadata.title ?? '').isNotEmpty)
          _HeaderLine(collection.metadata.title!),
        ..._rowsOf(collection, width, groupWidth: groupWidth),
        if (collection.id != CollectionId.recent &&
            collection.contents is CollectionContents$Failed)
          _NoticeLine(strings.gifsFailed, onRetry: _retry),
      ],
    ];
    // Nothing to list at all, as for a search that found nothing or a host
    // with no provider and no recents: said only once every collection has
    // loaded, so neither a page still loading nor one whose load failed (it
    // has its own line) says it.
    final listsNothing =
        rows.isEmpty &&
        collections.every(
          (collection) => collection.contents is CollectionContents$Loaded,
        );
    return _lines = [
      if (widget.attribution case final attribution?
          when rows.any((line) => line is _RowLine))
        _AttributionLine(attribution),
      ...rows,
      if (listsNothing) _NoticeLine(strings.gifsEmpty),
    ];
  }

  static bool _sameCollections(List<Collection> a, List<Collection> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  static Iterable<_Line> _rowsOf(
    Collection collection,
    double width, {
    double? groupWidth,
  }) sync* {
    final items = _itemsOf(collection);
    final rows = GifRowLayout.of(
      [for (final item in items) _sizeOf(item)],
      width: width,
      groupWidth: groupWidth,
    );
    for (final row in rows) {
      yield _RowLine(collection, row);
    }
  }

  static Size _sizeOf(CollectionItem item) {
    final size = item.descriptor?.size;
    return size == null
        ? const Size(100, 100)
        : Size(size.width.toDouble(), size.height.toDouble());
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final searches = _search != null;
    final list = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Under a pointer the rows keep their clips at any width (a
          // docked panel being resized); only the cells scale.
          final lines = _linesFor(
            constraints.maxWidth,
            ChromeStringsScope.panelOf(context),
            groupWidth:
                PanelArrangementScope.of(context) == PanelArrangement.pointer
                ? GifRowLayout.pointerGroupWidth
                : null,
          );
          return ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.only(bottom: bottom),
            cacheExtent: 0,
            itemCount: lines.length,
            itemExtentBuilder: (index, _) => lines[index].height,
            itemBuilder: (context, index) => switch (lines[index]) {
              _HeaderLine(:final title) => _Header(title: title),
              _NoticeLine(:final text, :final onRetry) => _Notice(
                text: text,
                onRetry: onRetry,
              ),
              _AttributionLine(:final text) => _Attribution(text: text),
              _RowLine(:final collection, :final row) => _Row(
                row: row,
                collection: collection,
                host: _host,
                assets: widget.assets,
                fresh: _fresh,
                appear: _appear,
                preview: _previewOf(collection),
                move: _moveCells
                    ? ChromeMotionScope.of(
                        context,
                      ).specOf(MotionRole.listTransition)
                    : null,
              ),
            },
          );
        },
      ),
    );
    // The clips start under the field and are clipped at its edge, never
    // scrolled behind it: the panel's background may be see-through (glass),
    // so a field over them would show them through it.
    final page = searches
        ? Stack(
            children: [
              Positioned.fill(top: PanelSearchField.height, child: list),
              PositionedDirectional(
                start: 0,
                end: 0,
                top: 0,
                child: ColoredBox(
                  color: PanelBackgroundScope.of(context),
                  child: PanelSearchField(shadow: _hairline),
                ),
              ),
            ],
          )
        : list;
    return CatalogContextMenuHost(host: _host, controller: _menu, child: page);
  }

  // --- Preview --------------------------------------------------------------

  _GifPreview? _previewOf(Collection collection) => switch (widget.previews) {
    final previews? => _GifPreview(
      begin: (context, item, kind) {
        _preview?.cancel();
        _menu.close();
        final hold = _host.holdAutoHide();
        return _preview = ContentPreviewSession.show(
          context: context,
          item: item,
          assets: widget.assets,
          actions: _actions,
          library: previews.library,
          kind: kind,
          hold: hold,
          controller: previews,
          itemAt: _itemAt,
        );
      },
      cells: _cells,
      menu: (item, globalPosition) {
        final entries = ContentPreviewMenu.entriesOf(
          item,
          _actions,
          ChromeStringsScope.panelOf(context),
          library: previews.library,
        );
        _menu.show(
          globalPosition: globalPosition,
          entries: entries,
          onSelected: (id) {
            if (ContentPreviewAction.byId(id) case final action?) {
              ContentPreviewMenu.perform(action, item, _actions);
            }
          },
        );
      },
      inRecents: collection.id == CollectionId.recent,
    ),
    null => null,
  };

  // The clip under [globalPosition] among the cells laid out, or null.
  ContentPreviewItem? _itemAt(Offset globalPosition) {
    for (final cell in _cells) {
      if (cell.itemAt(globalPosition) case final item?) return item;
    }
    return null;
  }

  ContentPreviewActions get _actions => panelPreviewActions(
    _host,
    searching: switch (_listed?.id) {
      CollectionId$Query() => true,
      _ => false,
    },
  );
}

/// What a clip's cell opens on a long press and a right click: the page's
/// preview, given the item of the clip.
final class _GifPreview {
  const _GifPreview({
    required this.begin,
    required this.menu,
    required this.inRecents,
    required this.cells,
  });

  /// The page's cells laid out now: each cell is in it while mounted.
  final Set<_CellState> cells;

  final ContentPreviewSession Function(
    BuildContext context,
    ContentPreviewItem item,
    PointerDeviceKind kind,
  )
  begin;

  final void Function(ContentPreviewItem item, Offset globalPosition) menu;

  final bool inRecents;

  ContentPreviewItem itemOf(CollectionItem item) => ContentPreviewItem(
    key: item.key,
    semanticKind: SemanticKind.gif,
    inRecents: inRecents,
    size: item.descriptor?.size,
    spokenName: item.descriptor?.spokenName,
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.panelOf(context);
    return Semantics(
      header: true,
      label: title,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: StickersPagePolicy.headerStartInsetValue,
            top: 5,
            end: 25,
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.sectionTitle,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final tokens = ChromeThemeScope.panelOf(context);
    final retry = onRetry;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.sectionTitle, fontSize: 15),
          ),
          if (retry != null)
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: retry,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    ChromeStringsScope.panelOf(context).retryAction,
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.panelOf(context);
    return Center(
      child: Text(
        text,
        style: TextStyle(color: tokens.sectionTitle, fontSize: 12),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.collection,
    required this.host,
    required this.assets,
    required this.fresh,
    required this.appear,
    required this.move,
    required this.preview,
  });

  final GifRow row;
  final Collection collection;
  final PanelPageHost host;
  final AssetCacheScope assets;

  // The clips that fade in on [appear]; the others show as they are.
  final Set<ContentKey> fresh;
  final Animation<double> appear;

  // How a cell that stays in this row moves to its new place, or null to put
  // it there at once.
  final MotionSpec? move;

  // What a long press and a right click open, or null for nothing.
  final _GifPreview? preview;

  @override
  Widget build(BuildContext context) {
    final items = _GifPageState._itemsOf(collection);
    final move = this.move;
    return Padding(
      padding: const EdgeInsets.only(top: GifRowLayout.gap),
      child: Stack(
        children: [
          for (final cell in row.cells)
            AnimatedPositionedDirectional(
              // Keyed by the clip, so a cell that stays in the row is the same
              // cell, moved: its attach and its fade go on.
              key: ValueKey(items[cell.index].key),
              duration: move?.duration ?? Duration.zero,
              curve: move?.curve ?? Curves.linear,
              start: cell.left,
              width: cell.width,
              top: 0,
              height: GifRowLayout.rowExtent,
              child: _appearing(
                items[cell.index].key,
                _Cell(
                  item: items[cell.index],
                  size: Size(cell.width, GifRowLayout.rowExtent),
                  onTap: () => _pick(items[cell.index]),
                  // A saved clip leaves the list from its badge.
                  onRemove: collection.id == CollectionId.recent
                      ? () => host.requestRemoveRecent(
                          items[cell.index].key,
                          kind: SemanticKind.gif,
                        )
                      : null,
                  assets: assets,
                  preview: preview,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _appearing(ContentKey key, Widget cell) =>
      fresh.contains(key) ? FadeTransition(opacity: appear, child: cell) : cell;

  void _pick(CollectionItem item) {
    final kind = switch (item.descriptor?.semanticKind) {
      null || SemanticKind.unknown => SemanticKind.gif,
      final kind => kind,
    };
    host.pick(
      item.key,
      kind: kind,
      source: collection.id == CollectionId.recent
          ? PickSource.recents
          : PickSource.collection,
    );
  }
}

class _Cell extends StatefulWidget {
  const _Cell({
    required this.item,
    required this.size,
    required this.onTap,
    required this.onRemove,
    required this.assets,
    required this.preview,
  });

  final CollectionItem item;
  final Size size;
  final VoidCallback onTap;

  /// Removes the clip from its list, from the remove badge a mouse over the
  /// cell shows; null shows none.
  final VoidCallback? onRemove;
  final AssetCacheScope assets;
  final _GifPreview? preview;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  // The loader's disc in a grid cell, whatever the cell's size.
  static const double _loadingRadius = 12;

  // Whether a mouse is over the cell, and over its remove badge.
  var _hovered = false;
  var _badgeHovered = false;

  // Whether a hold took the press over: the ink draws nothing until the next
  // press.
  var _held = false;
  ContentPreviewSession? _session;

  @override
  void initState() {
    super.initState();
    widget.preview?.cells.add(this);
  }

  @override
  void didUpdateWidget(_Cell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.preview?.cells, widget.preview?.cells)) return;
    oldWidget.preview?.cells.remove(this);
    widget.preview?.cells.add(this);
  }

  @override
  void dispose() {
    widget.preview?.cells.remove(this);
    super.dispose();
  }

  /// This clip's preview item when [globalPosition] is over the cell.
  ContentPreviewItem? itemAt(Offset globalPosition) =>
      switch ((widget.preview, context.findRenderObject())) {
        (final preview?, final RenderBox box)
            when box.attached &&
                box.hasSize &&
                (Offset.zero & box.size).contains(
                  box.globalToLocal(globalPosition),
                ) =>
          preview.itemOf(widget.item),
        _ => null,
      };

  // The remove badge's look on this platform.
  static const CatalogLeafRemoveBadge _look = kIsWeb
      ? CatalogLeafRemoveBadge.web
      : CatalogLeafRemoveBadge.pointer;

  // The badge a mouse over a removable cell shows, while no preview is up.
  CatalogLeafRemoveBadge? get _badge =>
      _hovered && widget.onRemove != null && _session == null ? _look : null;

  void _hover(PointerEvent event, {required bool inside}) {
    final mouse = event.kind == PointerDeviceKind.mouse && inside;
    var overBadge = false;
    if (mouse) {
      final rect = _look.rectOn(
        Offset.zero & widget.size,
        Directionality.of(context),
      );
      overBadge = rect.contains(event.localPosition);
    }
    if (mouse == _hovered && overBadge == _badgeHovered) return;
    setState(() {
      _hovered = mouse;
      _badgeHovered = overBadge;
    });
  }

  void _begin(LongPressStartDetails details, PointerDeviceKind kind) {
    setState(() => _held = true);
    final preview = widget.preview;
    if (preview == null) return;
    _session = preview.begin(context, preview.itemOf(widget.item), kind);
  }

  // A finger and a mouse are held for different times, so each has a
  // recognizer of its own (a recognizer's deadline is fixed when made).
  Map<Type, GestureRecognizerFactory> _gestures() {
    final preview = widget.preview;
    return {
      if (preview != null) ...{
        _TouchHold: GestureRecognizerFactoryWithHandlers<_TouchHold>(
          () => _TouchHold(debugOwner: this),
          (hold) => _wire(hold, PointerDeviceKind.touch),
        ),
        _MouseHold: GestureRecognizerFactoryWithHandlers<_MouseHold>(
          () => _MouseHold(debugOwner: this),
          (hold) => _wire(hold, PointerDeviceKind.mouse),
        ),
      },
    };
  }

  void _wire(LongPressGestureRecognizer hold, PointerDeviceKind kind) => hold
    ..onLongPressStart = ((details) => _begin(details, kind))
    ..onLongPressMoveUpdate = ((details) => _session?.update(details))
    ..onLongPressEnd = ((details) {
      _session?.end(details);
      _session = null;
    });

  // A new press draws its ink again; the held one faded out unseen.
  void _release(PointerDownEvent event) {
    // A secondary click is the context menu's, not a pick: the ink's tap
    // takes every button, so it is told which one pressed.
    _secondaryAt =
        event.kind == PointerDeviceKind.mouse &&
            event.buttons & kSecondaryMouseButton != 0
        ? event.position
        : null;
    if (_held) setState(() => _held = false);
  }

  // Where a secondary click went down, until the ink reports its tap.
  Offset? _secondaryAt;

  void _onTap() {
    final secondary = _secondaryAt;
    _secondaryAt = null;
    switch ((secondary, widget.preview)) {
      case (final at?, final preview?):
        preview.menu(preview.itemOf(widget.item), at);
      case (null, _):
        widget.onTap();
      case (_, null):
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final density = MediaQuery.devicePixelRatioOf(context);
    final size = widget.size;
    final decode = GifRowLayout.decodeBoxOf(
      switch (widget.item.descriptor?.size) {
        final clip? => Size(clip.width.toDouble(), clip.height.toDouble()),
        null => null,
      },
    );
    final label =
        widget.item.descriptor?.spokenName ??
        ChromeStringsScope.panelOf(context).tabLabel('gif');
    return Semantics(
      button: true,
      label: label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: _gestures(),
          // The platform's press: a ripple on Android, the highlight on iOS,
          // a ripple from the press on a desktop (no hover fill), in the
          // catalogue's press colour, the text colour at 0x0F.
          child: MouseRegion(
            onEnter: (event) => _hover(event, inside: true),
            onHover: (event) => _hover(event, inside: true),
            onExit: (event) => _hover(event, inside: false),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Listener(
                  onPointerDown: _release,
                  child: ChromeInk(
                    color: _held
                        ? const Color(0x00000000)
                        : palette.onSurface.withAlpha(0x0F),
                    onTap: _onTap,
                    child: ContentView(
                      content: widget.item.key,
                      scope: widget.assets,
                      preset: AssetPreset(
                        size: size,
                        // Decoded for the clip, not for the cell: a cell
                        // resized with its row plays on.
                        spec: AssetSpec.atDensity(
                          logicalWidth: decode.width,
                          logicalHeight: decode.height,
                          devicePixelRatio: density,
                        ),
                        // Silent and looping, while it is in view; the clip fills its
                        // cell and is cut at the edge.
                        profile: const AssetProfile(
                          animate: true,
                          fit: AssetFit.cover,
                        ),
                      ),
                      // The cell's rectangle in a quiet token until the thumbnail
                      // arrives, under the
                      // loader the cell has until the clip's first frame.
                      tint: ChromeThemeScope.of(context).placeholder.skeleton,
                      loadingRadius: _loadingRadius,
                    ),
                  ),
                ),
                if (_badge case final badge?)
                  PositionedDirectional(
                    top: badge.inset,
                    end: badge.inset,
                    width: badge.extent,
                    height: badge.extent,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onRemove,
                      child: CustomPaint(
                        painter: _BadgePainter(badge, over: _badgeHovered),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A finger's (or a stylus's) hold on a clip: the preview's 200 ms.
final class _TouchHold extends LongPressGestureRecognizer {
  _TouchHold({super.debugOwner})
    : super(
        duration: ContentPreviewSession.touchHoldDelay,
        supportedDevices: {
          for (final kind in PointerDeviceKind.values)
            if (kind != PointerDeviceKind.mouse) kind,
        },
      );
}

/// A mouse's hold on a clip: the drag time.
final class _MouseHold extends LongPressGestureRecognizer {
  _MouseHold({super.debugOwner})
    : super(
        duration: ContentPreviewSession.pointerHoldDelay,
        supportedDevices: const {PointerDeviceKind.mouse},
      );
}

// The remove badge drawn in the box it is laid out in.
class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.badge, {required this.over});

  final CatalogLeafRemoveBadge badge;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) =>
      badge.paint(canvas, Offset.zero & size, over: over);

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.badge != badge || old.over != over;
}
