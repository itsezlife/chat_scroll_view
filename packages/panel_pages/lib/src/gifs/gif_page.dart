import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/gifs/gif_row_layout.dart';
import 'package:panel_pages/src/stickers/stickers_page_policy.dart';
import 'package:panel_shell/panel_shell.dart';

/// The GIF page: the clips of [source] in the reference client's justified
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
/// ## Sections
///
/// The recents come first, unless they are known to be empty, and every other
/// collection after them. A collection's title heads it, except the first
/// section's: the reference client titles only what follows its recents
/// (`FeaturedGifs`).
///
/// ## Playback
///
/// Only the rows in view are built (`cacheExtent` 0), and each clip attaches
/// to the host's asset cache while it is built, so the cache's pause layers
/// and its limit on what plays at once (the playback clock and budgets of
/// `catalog_assets`) are the only playback policy: a clip that is scrolled out
/// of view detaches and stops. A clip's stand-in is the cache's.
///
/// ## Search
///
/// A page given a [searchSource] follows the shell's search (the host's
/// `PanelPage` declares `PageCapabilities(search: true)`): once the typed text
/// has paused ([searchDebounce]) the source is asked for it, and its results
/// are listed in place of the collections until search closes or the text is
/// cleared. Results are paged as the end comes near, like a collection.
///
/// ## When there is nothing to show
///
/// A collection that failed to load, or a search that failed, ends the list
/// with the panel's [PanelStrings.gifsFailed] and a retry button; a search
/// that found nothing says [PanelStrings.gifsEmpty]. Clips already listed stay
/// above it. The [attribution], when the host gives one, heads the list: a
/// provider's terms may require its name on the content it supplies, and the
/// page knows no provider.
///
/// Not ported: the category chips, trending from a bot, and the preview a long
/// press opens.
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
    this.searchDebounce = DebouncedSearch.defaultDebounce,
    this.attribution,
    super.key,
  });

  /// The page's connection to the shell; fixed for the life of the widget.
  final PanelPageHost host;

  /// The clips, the recents first when the host keeps some: one collection
  /// each. The recents are `CollectionId.recent`.
  final CollectionSource source;

  /// The asset cache the clips draw through.
  final AssetCacheScope assets;

  /// Where search results come from, or null for a page that does not search.
  final SearchSource? searchSource;

  /// How long typing must pause before a search runs.
  final Duration searchDebounce;

  /// The line that heads the list, such as the name of the provider the clips
  /// come from, or null for none. Shown as given: it is not translated.
  final String? attribution;

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

class _GifPageState extends State<GifPage> {
  final _scroll = ScrollController();
  var _lines = const <_Line>[];
  var _lineKey = (<Collection>[], 0.0, null as PanelStrings?, null as String?);
  late DebouncedSearch<void> _debounced;
  var _query = '';
  String? _announced;

  PanelPageHost get _host => widget.host;
  CollectionSource get _source => widget.source;
  SearchSource? get _search => widget.searchSource;

  @override
  void initState() {
    super.initState();
    _source.collections.addListener(_onCollections);
    _host.reselected.addListener(_onReselected);
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
    _host.reselected.removeListener(_onReselected);
    _scroll.dispose();
    super.dispose();
  }

  // --- Loading --------------------------------------------------------------

  void _onCollections() {
    for (final collection in _source.collections.value) {
      if (collection.contents is CollectionContents$Idle) {
        unawaited(_source.load(collection.id));
      }
    }
    if (mounted) setState(() {});
  }

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
    if (!_syncQuery()) return;
    _debounced.update(_query);
    setState(() {});
  }

  void _reportBusy() => _host.reportSearchProgress(busy: _debounced.busy.value);

  // The results are what the page lists only once they are those of the text
  // in the field: between a keystroke and the reply they are the last
  // query's, and not shown.
  Collection? get _results {
    final results = _search?.results.value;
    if (_query.isEmpty || results == null) return null;
    return results.id == CollectionId.query(_query) ? results : null;
  }

  void _onResults() {
    if (_results?.contents case CollectionContents$Loaded(
      :final items,
    ) when _announced != _query) {
      _announced = _query;
      _host.reportSearchResultCount(items.length);
    }
    if (mounted) setState(() {});
  }

  void _retry() {
    if (_query.isNotEmpty) {
      // A search is not retried by asking for the same text again, which the
      // source ignores: clearing it first makes the text new.
      final query = _query;
      _announced = null;
      unawaited(_search!.search('').then((_) => _search?.search(query)));
      return;
    }
    for (final collection in _source.collections.value) {
      if (collection.contents is CollectionContents$Failed) {
        unawaited(_source.load(collection.id));
      }
    }
  }

  // The next page of every collection that has one, as the end comes near.
  void _loadMoreNearEnd() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.extentAfter > position.viewportDimension) return;
    if (_query.isNotEmpty) {
      if (_results?.contents case CollectionContents$Loaded(
        :final nextPageToken,
      ) when nextPageToken != null) {
        unawaited(_search!.loadMore());
      }
      return;
    }
    for (final collection in _source.collections.value) {
      if (collection.contents case CollectionContents$Loaded(
        :final nextPageToken,
      ) when nextPageToken != null) {
        unawaited(_source.loadMore(collection.id));
      }
    }
  }

  void _onReselected() {
    if (!_scroll.hasClients) return;
    final motion = ChromeMotionScope.of(context).specOf(MotionRole.fade);
    unawaited(
      _scroll.animateTo(0, duration: motion.duration, curve: motion.curve),
    );
  }

  // --- Reporting ------------------------------------------------------------

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    switch (notification) {
      case ScrollUpdateNotification(:final scrollDelta?, :final dragDetails):
        _host.reportScrollActivity(
          dragDetails == null
              ? PageScrollActivity.fling(scrollDelta)
              : PageScrollActivity.drag(scrollDelta),
        );
        _loadMoreNearEnd();
      case ScrollEndNotification(:final metrics):
        _host.reportScrollActivity(
          PageScrollActivity.idle(
            atEdge:
                metrics.pixels <= metrics.minScrollExtent ||
                metrics.pixels >= metrics.maxScrollExtent,
          ),
        );
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
  List<_Line> _linesFor(double width, PanelStrings strings) {
    final results = _results;
    final collections = _query.isNotEmpty
        ? [?results]
        : [
            for (final collection in _source.collections.value)
              if (!_isEmptyRecents(collection)) collection,
          ];
    final stale =
        _lineKey.$2 != width ||
        !identical(_lineKey.$3, strings) ||
        _lineKey.$4 != widget.attribution ||
        !_sameCollections(_lineKey.$1, collections);
    if (!stale) return _lines;
    _lineKey = (collections, width, strings, widget.attribution);
    // A collection that failed ends its own rows with the failure, so it is
    // read where the clips would have been, not after the ones that follow.
    final rows = [
      for (final (i, collection) in collections.indexed) ...[
        if (i > 0 && (collection.metadata.title ?? '').isNotEmpty)
          _HeaderLine(collection.metadata.title!),
        ..._rowsOf(collection, width),
        if (collection.id != CollectionId.recent &&
            collection.contents is CollectionContents$Failed)
          _NoticeLine(strings.gifsFailed, onRetry: _retry),
      ],
    ];
    final foundNothing = switch (results?.contents) {
      CollectionContents$Loaded(:final items) => items.isEmpty,
      _ => false,
    };
    return _lines = [
      if (widget.attribution case final attribution?
          when rows.any((line) => line is _RowLine))
        _AttributionLine(attribution),
      ...rows,
      if (foundNothing) _NoticeLine(strings.gifsEmpty),
    ];
  }

  static bool _sameCollections(List<Collection> a, List<Collection> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  static Iterable<_Line> _rowsOf(Collection collection, double width) sync* {
    final items = _itemsOf(collection);
    final rows = GifRowLayout.of([
      for (final item in items) _sizeOf(item),
    ], width: width);
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
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lines = _linesFor(
            constraints.maxWidth,
            ChromeStringsScope.panelOf(context),
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
              ),
            },
          );
        },
      ),
    );
  }
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
  });

  final GifRow row;
  final Collection collection;
  final PanelPageHost host;
  final AssetCacheScope assets;

  @override
  Widget build(BuildContext context) {
    final items = _GifPageState._itemsOf(collection);
    return Padding(
      padding: const EdgeInsets.only(top: GifRowLayout.gap),
      child: Stack(
        children: [
          for (final cell in row.cells)
            PositionedDirectional(
              start: cell.left,
              width: cell.width,
              top: 0,
              height: GifRowLayout.rowExtent,
              child: _Cell(
                item: items[cell.index],
                size: Size(cell.width, GifRowLayout.rowExtent),
                onTap: () => _pick(items[cell.index]),
                assets: assets,
              ),
            ),
        ],
      ),
    );
  }

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
    required this.assets,
  });

  final CollectionItem item;
  final Size size;
  final VoidCallback onTap;
  final AssetCacheScope assets;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  var _pressed = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final density = MediaQuery.devicePixelRatioOf(context);
    final size = widget.size;
    final label =
        widget.item.descriptor?.spokenName ??
        ChromeStringsScope.panelOf(context).tabLabel('gif');
    return Semantics(
      button: true,
      label: label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ContentView(
                content: widget.item.key,
                scope: widget.assets,
                preset: AssetPreset(
                  size: size,
                  spec: AssetSpec.atDensity(
                    logicalWidth: size.width,
                    logicalHeight: size.height,
                    devicePixelRatio: density,
                  ),
                  // Silent and looping, while it is in view.
                  profile: const AssetProfile(animate: true),
                ),
              ),
              // The catalogue's press wash: the text colour at 0x0F.
              if (_pressed)
                ColoredBox(color: palette.onSurface.withAlpha(0x0F)),
            ],
          ),
        ),
      ),
    );
  }
}
