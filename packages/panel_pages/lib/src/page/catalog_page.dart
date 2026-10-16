import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/bake/bake_activity_port.dart';
import 'package:panel_pages/src/bake/catalog_bake_forwarder.dart';
import 'package:panel_pages/src/input/catalog_keyboard_focus.dart';
import 'package:panel_pages/src/page/bottom_extent_reporter.dart';
import 'package:panel_pages/src/page/catalog_page_controller.dart';
import 'package:panel_pages/src/page/catalog_page_model.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/scroll/page_scroll_reporter.dart';
import 'package:panel_pages/src/theme/chrome_catalog_theme.dart';
import 'package:panel_shell/panel_shell.dart';

/// The shared scaffold of a panel page: a catalogue of the [Collection]s of a
/// [CollectionSource], with search results, loading as sections come near,
/// scroll reporting and the bake hand-off.
///
/// An emoji, sticker or GIF page is a thin composition of this widget, a
/// source and a [CatalogPagePolicy]; the page's builder passes the `host` it
/// is given.
///
/// ## What it does
///
/// - Hosts the [PanelCatalogViewport] on a [CatalogPageModel]'s snapshots: one
///   section per collection while browsing, one section of results while the
///   shell's search is open with a query (see the model for the rules).
/// - Loads a section when an edge of it comes near, and pages it at its end.
/// - Reports the catalogue's scroll to the shell as `PageScrollActivity`
///   (drives the bottom bar) and forwards its motion and visible band to the
///   glyph bake through [bake].
/// - Reports picks to the shell: a tap becomes `host.pick` as the policy
///   decides, a long press is carried to a session the policy begins.
/// - Scrolls to the start when the user selects the page's tab again, and
///   brings the browse offset back when search results go.
/// - Binds the keys of the roving focus (arrows, Home, End, Enter, Space).
/// - Scopes the catalogue's theme from the chrome theme above
///   ([ChromeCatalogTheme]).
///
/// ## What it does not do
///
/// It measures nothing and keeps no scroll maths: geometry, offsets and
/// landing are the viewport's and its controller's. It writes no recents and
/// plans no atlas: picks go to the shell, and the page that owns an atlas gives
/// this one a [BakeActivityPort].
///
/// Requires a `ChromeThemeScope` and a `ChromeStringsScope` above.
///
/// The [host] of a page does not change for the life of its widget.
class CatalogPage extends StatefulWidget {
  /// A page that shows [source] as [policy] decides, drawing through [assets].
  const CatalogPage({
    required this.host,
    required this.source,
    required this.policy,
    required this.assets,
    this.searchSource,
    this.bake,
    this.padding = EdgeInsets.zero,
    this.sectionNearExtent,
    this.searchDebounce = DebouncedSearch.defaultDebounce,
    super.key,
  });

  /// The page's connection to the shell.
  final PanelPageHost host;

  /// Where the collections come from. May be replaced while the page lives; the
  /// catalogue shows the new source at once.
  final CollectionSource source;

  /// Where search results come from, or null for a page that does not search.
  final SearchSource? searchSource;

  /// The decisions that depend on the kind of content.
  final CatalogPagePolicy policy;

  /// The host's asset cache scope the viewport draws through.
  ///
  /// How unicode glyphs are drawn (baked sprites or text) is decided by how
  /// the scope is built; see [PageAssets].
  final AssetCacheScope assets;

  /// Where the bake hears of the catalogue's motion and visible band, or null
  /// where nothing is baked. May be replaced while the page lives (an atlas
  /// replanned for another density).
  final BakeActivityPort? bake;

  /// Padding around the catalogue, passed to the viewport.
  final EdgeInsets padding;

  /// How far beyond the viewport a section edge counts as near, or null for the
  /// viewport's default (one viewport height).
  final double? sectionNearExtent;

  /// How long typing pauses before a search runs.
  final Duration searchDebounce;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final CatalogPageController _controller;
  late final CatalogPageModel _model;
  late final PageScrollReporter _reporter;
  late final CatalogBakeForwarder _forwarder;
  late final StreamSubscription<PanelCatalogScrollEvent> _catalogEvents;
  late final _StripHandle _strip;
  CatalogLongPressSession? _longPress;
  var _showsResults = false;
  var _modelReady = false;
  var _stripAtBottom = false;

  PanelPageHost get _host => widget.host;
  PanelCatalogController get _catalog => _controller.catalog;

  @override
  void initState() {
    super.initState();
    _controller = _host.controllers.obtain(
      _host.pageId,
      CatalogPageController.new,
    );
    _reporter = PageScrollReporter(
      events: _catalog.events,
      report: _host.reportScrollActivity,
      atEdge: _atEdge,
    );
    _forwarder = CatalogBakeForwarder(
      events: _catalog.events,
      port: widget.bake,
    );
    _catalogEvents = _catalog.events.listen(_onCatalogEvent);
    _host.reselected.addListener(_onReselected);
    _host.isActive.addListener(_onActiveChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final strings = ChromeStringsScope.panelOf(context);
    final arrangement = PanelArrangementScope.of(context);
    if (!_modelReady) {
      _modelReady = true;
      _model = CatalogPageModel(
        source: widget.source,
        searchSource: widget.searchSource,
        policy: widget.policy,
        strings: strings,
        host: _host,
        events: _catalog.events,
        arrangement: arrangement,
        searchDebounce: widget.searchDebounce,
      );
      _strip = _StripHandle(_model, _catalog);
      _showsResults = _model.showsResults.value;
      _model.showsResults.addListener(_onShowsResultsChanged);
    } else {
      _model
        ..strings = strings
        ..arrangement = arrangement;
    }
    _syncStripPlacement();
  }

  @override
  void didUpdateWidget(CatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.host, widget.host),
      'The host of a CatalogPage does not change.',
    );
    _model
      ..source = widget.source
      ..searchSource = widget.searchSource
      ..policy = widget.policy;
    _forwarder.port = widget.bake;
    _syncStripPlacement();
  }

  @override
  void dispose() {
    _releaseBottomExtent();
    unawaited(_catalogEvents.cancel());
    _host.isActive.removeListener(_onActiveChanged);
    _host.reselected.removeListener(_onReselected);
    _model.showsResults.removeListener(_onShowsResultsChanged);
    _cancelLongPress();
    _forwarder.dispose();
    _reporter.dispose();
    _model.dispose();
    super.dispose();
  }

  // --- The strip at the bottom -----------------------------------------------

  // The extent the shell was told stays true only while the strip is pinned at
  // the bottom: when the arrangement or the policy moves it, the clearance it
  // asked of the shell goes with it. Told a microtask later, because this is
  // reached from build and dispose, where the shell must not be asked to
  // rebuild.
  void _syncStripPlacement() {
    final atBottom = widget.policy.stripAtBottom(_model.arrangement);
    if (_stripAtBottom && !atBottom) _releaseBottomExtent();
    _stripAtBottom = atBottom;
  }

  void _releaseBottomExtent() {
    if (!_stripAtBottom) return;
    _stripAtBottom = false;
    final host = _host;
    scheduleMicrotask(() => host.reportBottomExtent(0));
  }

  // --- Reacting to the shell ------------------------------------------------

  bool _atEdge() {
    final offset = _catalog.offset;
    return offset <= 0.5 || offset >= _catalog.maxScrollExtent - 0.5;
  }

  // The user took hold of the catalogue: the soft keyboard goes, so the
  // results are not hidden behind it. A drag that continues a section jump the
  // user started with the strip is a drag all the same.
  void _onCatalogEvent(PanelCatalogScrollEvent event) {
    if (event case PanelCatalogUserDragStart()) _host.releaseSearchFocus();
  }

  void _onReselected() {
    _cancelLongPress();
    _catalog.animateTo(0);
  }

  void _onActiveChanged() {
    if (!_host.isActive.value) _cancelLongPress();
  }

  void _onShowsResultsChanged() {
    final shows = _model.showsResults.value;
    if (shows == _showsResults) return;
    if (shows) {
      _controller.browseOffset = _catalog.offset;
      _catalog.jumpTo(0);
    } else {
      final offset = _controller.browseOffset;
      _controller.browseOffset = null;
      // The viewport clamps a jump to the extent it laid out last, which is the
      // results'. The offset is put back once the collections are laid out.
      if (offset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showsResults) _catalog.jumpTo(offset);
        });
      }
    }
    setState(() => _showsResults = shows);
  }

  // --- Interaction ----------------------------------------------------------

  void _onTap(CatalogLeafHit hit) {
    final collection = _model.collectionOf(hit.sectionId);
    if (collection == null) return;
    final pick = widget.policy.pickOf(
      hit,
      collection,
      searching: _showsResults,
    );
    if (pick == null) return;
    _host.pick(pick.key, kind: pick.kind, source: pick.source);
  }

  bool _longPressEligible(CatalogLeafHit hit) {
    final collection = _model.collectionOf(hit.sectionId);
    return collection != null && widget.policy.hasLongPress(hit, collection);
  }

  void _onLongPressStart(CatalogLeafHit hit, LongPressStartDetails details) {
    _cancelLongPress();
    final collection = _model.collectionOf(hit.sectionId);
    if (collection == null) return;
    _longPress = widget.policy.beginLongPress(
      context,
      hit,
      collection,
      details,
    );
  }

  void _onLongPressMove(CatalogLeafHit hit, LongPressMoveUpdateDetails d) =>
      _longPress?.update(d);

  void _onLongPressEnd(CatalogLeafHit hit, LongPressEndDetails details) {
    final session = _longPress;
    _longPress = null;
    session?.end(details);
  }

  void _cancelLongPress() {
    final session = _longPress;
    _longPress = null;
    session?.cancel();
  }

  void _onSectionAction(String sectionId, String actionId) {
    final collection = _model.collectionOf(sectionId);
    if (collection == null) return;
    widget.policy.onSectionAction(collection, actionId, _host);
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final strip = _showsResults
        ? null
        : widget.policy.buildStrip(context, _strip);
    final atBottom = widget.policy.stripAtBottom(_model.arrangement);
    return ChromeCatalogTheme(
      child: Column(
        children: [
          if (!atBottom) ?strip,
          Expanded(
            // Only the catalogue binds the arrows and Space: a strip above it
            // keeps the keys of its own controls.
            child: CatalogKeyboardFocus(
              controller: _catalog,
              child: PanelCatalogViewport(
                snapshots: _model.snapshots,
                assets: widget.assets,
                controller: _catalog,
                padding: widget.padding,
                sectionNearExtent: widget.sectionNearExtent,
                onLeafTap: _onTap,
                leafLongPressEligible: _longPressEligible,
                onLeafLongPressStart: _onLongPressStart,
                onLeafLongPressMove: _onLongPressMove,
                onLeafLongPressEnd: _onLongPressEnd,
                onSectionAction: _onSectionAction,
              ),
            ),
          ),
          // Measured, not assumed: no strip (results showing, a single
          // category) is an extent of nothing.
          if (atBottom)
            BottomExtentReporter(
              onExtent: _host.reportBottomExtent,
              child: strip ?? const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

final class _StripHandle implements CatalogStripHandle {
  _StripHandle(this._model, this._catalog);

  final CatalogPageModel _model;
  final PanelCatalogController _catalog;

  @override
  listen.ValueListenable<List<CatalogStripEntry>> get entries =>
      _model.stripEntries;

  @override
  Stream<PanelCatalogScrollEvent> get scrollEvents => _catalog.events;

  @override
  String? get currentSectionId => _catalog.currentSection?.sectionId;

  @override
  Future<void> jumpToSection(String sectionId) {
    final index = _model.sectionIndexOf(sectionId);
    return switch (index) {
      final index? => _catalog.jumpToSection(index),
      null => Future<void>.value(),
    };
  }
}
