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
/// Not ported: the search field and its category chips, trending from a bot,
/// and the preview a long press opens.
///
/// Requires the chrome theme, strings and motion scopes.
class GifPage extends StatefulWidget {
  /// The GIF page of [host], showing the clips of [source] and drawing through
  /// [assets].
  const GifPage({
    required this.host,
    required this.source,
    required this.assets,
    super.key,
  });

  /// The page's connection to the shell; fixed for the life of the widget.
  final PanelPageHost host;

  /// The clips, the recents first when the host keeps some: one collection
  /// each. The recents are `CollectionId.recent`.
  final CollectionSource source;

  /// The asset cache the clips draw through.
  final AssetCacheScope assets;

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

final class _RowLine extends _Line {
  _RowLine(this.collection, this.row) : super(row.height);
  final Collection collection;
  final GifRow row;
}

class _GifPageState extends State<GifPage> {
  final _scroll = ScrollController();
  var _lines = const <_Line>[];
  var _lineKey = (<Collection>[], 0.0);

  PanelPageHost get _host => widget.host;
  CollectionSource get _source => widget.source;

  @override
  void initState() {
    super.initState();
    _source.collections.addListener(_onCollections);
    _host.reselected.addListener(_onReselected);
    _onCollections();
  }

  @override
  void didUpdateWidget(GifPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      oldWidget.source.collections.removeListener(_onCollections);
      widget.source.collections.addListener(_onCollections);
      _onCollections();
    }
  }

  @override
  void dispose() {
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

  // The next page of every collection that has one, as the end comes near.
  void _loadMoreNearEnd() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.extentAfter > position.viewportDimension) return;
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

  // The lines for [width], rebuilt only when the collections or the width
  // change: the rows are a function of nothing else.
  List<_Line> _linesFor(double width) {
    final collections = [
      for (final collection in _source.collections.value)
        if (!_isEmptyRecents(collection)) collection,
    ];
    final stale =
        _lineKey.$2 != width ||
        _lineKey.$1.length != collections.length ||
        !_sameCollections(_lineKey.$1, collections);
    if (!stale) return _lines;
    _lineKey = (collections, width);
    return _lines = [
      for (final (i, collection) in collections.indexed) ...[
        if (i > 0 && (collection.metadata.title ?? '').isNotEmpty)
          _HeaderLine(collection.metadata.title!),
        ..._rowsOf(collection, width),
      ],
    ];
  }

  static bool _sameCollections(List<Collection> a, List<Collection> b) {
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
          final lines = _linesFor(constraints.maxWidth);
          return ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.only(bottom: bottom),
            cacheExtent: 0,
            itemCount: lines.length,
            itemExtentBuilder: (index, _) => lines[index].height,
            itemBuilder: (context, index) => switch (lines[index]) {
              _HeaderLine(:final title) => _Header(title: title),
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
