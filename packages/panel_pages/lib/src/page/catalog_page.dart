import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/bake/bake_activity_port.dart';
import 'package:panel_pages/src/bake/catalog_bake_forwarder.dart';
import 'package:panel_pages/src/input/catalog_keyboard_focus.dart';
import 'package:panel_pages/src/menu/catalog_context_menu.dart';
import 'package:panel_pages/src/page/bottom_extent_reporter.dart';
import 'package:panel_pages/src/page/catalog_page_controller.dart';
import 'package:panel_pages/src/page/catalog_page_model.dart';
import 'package:panel_pages/src/page/catalog_sticky_header.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_pages/src/page/listen_value_builder.dart';
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
/// - Opens the policy's context menu at a mouse's right click, and keeps a
///   session's cell pinned (hover wash held, wheel locked) while the session
///   is open. Menu and session each hold the host's auto-hide while up.
/// - Scrolls to the start when the user selects the page's tab again, and
///   brings the browse offset back when search results go.
/// - Binds the keys of the roving focus (arrows, Home, End, Enter, Space).
/// - Scopes the catalogue's theme from the chrome theme above
///   ([ChromeCatalogTheme]).
/// - Draws the page's **sticky header** over the catalogue under the touch
///   arrangement, and a plain column around it under the pointer arrangement
///   (below).
///
/// ## The arrangement
///
/// `PanelArrangementScope` says which of two layouts the page takes; without a
/// shell above it is `touch`.
///
/// - `touch`: the sticky header below. A strip the policy keeps at the top and
///   declares an extent for is a part of it; so is an inline search field.
/// - `pointer`: nothing slides but the content. The strip is a part of the
///   column, above the catalogue or, where [CatalogPagePolicy.stripAtBottom]
///   says so, pinned below it with its measured height reported through
///   `PanelPageHost.reportBottomExtent`; an inline search field is the first
///   thing in the content, scrolls away with it and does not pin when search
///   opens.
///
/// ## The sticky header
///
/// The policy's strip and, for a page that declares `SearchPlacement.inline`,
/// the shell's search field are drawn over the catalogue, which is padded by
/// their extent so its first row starts under both.
///
/// - The **strip** (above the field) slides away as the user reads on and
///   comes back as they read back; a tap on one of its entries lands the
///   section's header right under it ([PanelCatalogViewport.headerLandingInset]).
///   It is not part of the page while search is open or results show.
/// - The **field** is the first thing in the content: it scrolls away with it,
///   and pins to the top while search is open, with a hairline under it while
///   content passes beneath.
/// - Both rest on an opaque panel background so the content passes under them.
///
/// The geometry (offsets, hairlines, when the strip yields) is
/// [CatalogStickyHeader]'s; this widget feeds it the catalogue's scroll and
/// paints what it publishes.
///
/// ## What it does not do
///
/// It measures nothing and keeps no scroll maths: geometry, offsets and
/// landing are the viewport's and its controller's. It writes no recents and
/// plans no atlas: picks go to the shell, and the page that owns an atlas gives
/// this one a [BakeActivityPort].
///
/// Requires a `ChromeThemeScope` and a `ChromeStringsScope` above, and, for an
/// inline search field, the `PanelSearchFieldScope` a `PanelShell` provides.
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
    this.searchFieldReady,
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

  /// Whether the inline search field may mount, or null for always.
  ///
  /// The band it occupies is reserved either way, so a page that paces its
  /// first mount over frames (grid, then field, then strip) does not move its
  /// content when the field arrives.
  final listen.ValueListenable<bool>? searchFieldReady;

  /// Padding around the catalogue, passed to the viewport. The header's extent
  /// is added to its top.
  final EdgeInsets padding;

  /// How far beyond the viewport a section edge counts as near, or null for the
  /// viewport's default (one viewport height).
  final double? sectionNearExtent;

  /// How long typing pauses before a search runs.
  final Duration searchDebounce;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage>
    with SingleTickerProviderStateMixin {
  late final CatalogPageController _controller;
  late final CatalogPageModel _model;
  late final PageScrollReporter _reporter;
  late final CatalogBakeForwarder _forwarder;
  late final StreamSubscription<PanelCatalogScrollEvent> _catalogEvents;
  late final _StripHandle _strip;
  final _menu = CatalogContextMenuController();
  late CatalogStickyHeader _header;
  late final _CatalogMetrics _metrics;
  late bool _inlineSearch;
  // What the header was last built for, to know when the arrangement or the
  // policy asks for another one.
  double _headerStripExtent = -1;
  bool? _headerInline;
  late final AnimationController _reveal;
  var _revealFrom = 0.0;
  Curve _revealCurve = Curves.linear;
  CatalogLongPressSession? _longPress;
  CatalogLeafHit? _pinned;
  // The kind of the pointer that went down last: the long-press callbacks
  // carry none, and what a long press opens depends on it.
  var _lastKind = PointerDeviceKind.touch;
  var _showsResults = false;
  var _searchOpen = false;
  var _modelReady = false;
  var _stripAtBottom = false;
  var _disposed = false;

  PanelPageHost get _host => widget.host;
  PanelCatalogController get _catalog => _controller.catalog;

  PanelArrangement get _arrangement => _model.arrangement;

  // Pinned at the bottom of the page's column (the policy says, per
  // arrangement): a fixed part of the column, never part of the header.
  bool get _stripAtBottomNow => widget.policy.stripAtBottom(_arrangement);

  // The strip is a sticky header (over the catalogue, sliding away as the user
  // reads on) only where the arrangement lets a header slide and the policy
  // keeps its strip at the top and declares how tall it is. Otherwise it is a
  // plain part of the column.
  bool get _stripSticky =>
      _arrangement.headerSlidesAway &&
      !_stripAtBottomNow &&
      widget.policy.stripExtent > 0;

  double get _stripExtent => _stripSticky ? widget.policy.stripExtent : 0;

  // The sticky strip is part of the page only while browsing: search, open or
  // with results, takes its place at the top.
  bool get _stripShown => _stripExtent > 0 && !_searchOpen && !_showsResults;

  @override
  void initState() {
    super.initState();
    _controller = _host.controllers.obtain(
      _host.pageId,
      CatalogPageController.new,
    );
    _metrics = _CatalogMetrics(_catalog);
    _reveal = AnimationController(vsync: this)..addListener(_onRevealTick);
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
    _searchOpen = _host.search.value.isOpen;
    _host.search.addListener(_onSearchChanged);
    widget.searchFieldReady?.addListener(_onFieldReady);
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
      _strip = _StripHandle(_model, _catalog, _revealNow);
      _showsResults = _model.showsResults.value;
      _model.showsResults.addListener(_onShowsResultsChanged);
    } else {
      _model
        ..strings = strings
        ..arrangement = arrangement;
    }
    _syncLayout();
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
    _syncLayout();
    if (!identical(oldWidget.searchFieldReady, widget.searchFieldReady)) {
      oldWidget.searchFieldReady?.removeListener(_onFieldReady);
      widget.searchFieldReady?.addListener(_onFieldReady);
    }
  }

  @override
  void dispose() {
    _releaseBottomExtent();
    _disposed = true;
    unawaited(_catalogEvents.cancel());
    widget.searchFieldReady?.removeListener(_onFieldReady);
    _host.search.removeListener(_onSearchChanged);
    _host.isActive.removeListener(_onActiveChanged);
    _host.reselected.removeListener(_onReselected);
    _model.showsResults.removeListener(_onShowsResultsChanged);
    _reveal
      ..removeListener(_onRevealTick)
      ..dispose();
    _cancelLongPress(unpin: false);
    _menu.dispose();
    _forwarder.dispose();
    _reporter.dispose();
    _model.dispose();
    _header.dispose();
    super.dispose();
  }

  // --- The layout the arrangement asks for -----------------------------------

  // The page is laid out for an arrangement and a policy: the sticky header
  // (strip over the catalogue, inline search field that pins) under the touch
  // arrangement, a plain column (strip above or pinned below the catalogue,
  // an inline search field that only scrolls) under the pointer arrangement.
  // Either can
  // change while the page lives (a popup docked in place), so this is asked
  // again whenever one does.
  void _syncLayout() {
    final capabilities = widget.policy.capabilities;
    _inlineSearch =
        capabilities.search &&
        capabilities.searchPlacement == SearchPlacement.inline &&
        widget.searchSource != null;
    _syncStripPlacement();
    final stripExtent = _stripExtent;
    if (_headerInline == _inlineSearch && _headerStripExtent == stripExtent) {
      return;
    }
    final first = _headerInline == null;
    final old = first ? null : _header;
    _headerInline = _inlineSearch;
    _headerStripExtent = stripExtent;
    _header = CatalogStickyHeader(
      stripExtent: stripExtent,
      searchExtent: _inlineSearch ? PanelSearchField.height : 0,
    );
    _configureHeader();
    if (old != null) {
      // The layers below still listen to the old one until they rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  // The extent the shell was told stays true only while the strip is pinned at
  // the bottom: when the arrangement or the policy moves it, the clearance it
  // asked of the shell goes with it. Told a microtask later, because this is
  // reached from build and dispose, where the shell must not be asked to
  // rebuild.
  void _syncStripPlacement() {
    final atBottom = _stripAtBottomNow;
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

  // A field that pins when search opens does so under the arrangement that
  // says so; under the other it stays among the content however search is.
  void _configureHeader() => _header.configure(
    searchOpen: _searchOpen && _arrangement.pinsSearchWhenOpen,
    stripShown: _stripShown,
    metrics: _metrics,
  );

  // The header's notifiers feed widgets, so a change made while the frame is
  // building or laying out waits for the end of it.
  void _whenSafe(void Function() run) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) run();
      });
    } else {
      run();
    }
  }

  void _onCatalogEvent(PanelCatalogScrollEvent event) {
    switch (event) {
      // The user took hold of the catalogue: the soft keyboard goes, so the
      // results are not hidden behind it. A drag that continues a section jump
      // the user started with the strip is a drag all the same.
      case PanelCatalogUserDragStart():
        _host.releaseSearchFocus();
      case PanelCatalogViewportScrolled(:final delta):
        _whenSafe(() => _header.scrolled(delta, _metrics));
      case PanelCatalogOffsetChanged() ||
          PanelCatalogProgrammaticJump() ||
          PanelCatalogSectionJumpStart() ||
          PanelCatalogSectionJumpEnd() ||
          PanelCatalogAnimateStart():
        _whenSafe(() => _header.sync(_metrics));
      default:
        break;
    }
  }

  void _onSearchChanged() {
    final open = _host.search.value.isOpen;
    if (open == _searchOpen) return;
    _searchOpen = open;
    _configureHeader();
    if (!open) {
      // The strip is part of the page again: it comes back, whatever it was
      // doing when search opened.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) unawaited(_revealStrip());
      });
    }
    setState(() {});
  }

  void _onFieldReady() => setState(() {});

  void _onReselected() {
    _cancelLongPress();
    if (_stripShown) {
      unawaited(_revealThenJumpToFirstSection());
    } else {
      _catalog.animateTo(0);
    }
  }

  Future<void> _revealThenJumpToFirstSection() async {
    await _revealStrip();
    if (_disposed) return;
    final first = _model.snapshots.value.sections;
    if (first.isNotEmpty) await _catalog.jumpToSection(0);
  }

  void _onActiveChanged() {
    if (_host.isActive.value) return;
    _cancelLongPress();
    _menu.close();
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
    _showsResults = shows;
    _configureHeader();
    setState(() {});
  }

  // --- The strip's reveal ---------------------------------------------------

  // Slides the strip back at once: a jump to a section starts from a strip
  // that is whole.
  void _revealNow() {
    _reveal.stop();
    _header.setStripOffset(0, _metrics);
  }

  void _onRevealTick() => _header.setStripOffset(
    _revealFrom * (1 - _revealCurve.transform(_reveal.value)),
    _metrics,
  );

  // Slides the strip back over the reveal role's motion; completes when it is
  // whole, or when another motion took over.
  Future<void> _revealStrip() async {
    final from = _header.stripOffset.value;
    final spec = ChromeMotionScope.of(context).specOf(MotionRole.stripReveal);
    if (from >= -0.5 || spec.duration == Duration.zero) {
      _revealNow();
      return;
    }
    _revealFrom = from;
    _revealCurve = spec.curve;
    _reveal
      ..stop()
      ..duration = spec.duration;
    try {
      await _reveal.forward(from: 0);
      if (!_disposed) _header.setStripOffset(0, _metrics);
    } on TickerCanceled {
      // A newer reveal, or the page leaving, took over.
    }
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

  Duration? _longPressDelay(CatalogLeafHit hit, PointerDeviceKind kind) {
    final collection = _model.collectionOf(hit.sectionId);
    return collection == null
        ? null
        : widget.policy.longPressDelayOf(hit, collection, kind);
  }

  void _onLongPressStart(CatalogLeafHit hit, LongPressStartDetails details) {
    _cancelLongPress();
    final collection = _model.collectionOf(hit.sectionId);
    final cell = _catalog.leafBoundsOf(hit);
    final viewport = _catalog.viewportBounds;
    if (collection == null || cell == null || viewport == null) return;
    final session = widget.policy.beginLongPress(
      context,
      hit,
      collection,
      details,
      kind: _lastKind,
      cellBounds: cell,
      viewportBounds: viewport,
    );
    if (session == null) return;
    _longPress = session;
    session.isOpen.addListener(_onSessionOpenChanged);
    // A session that was over before it came back to us leaves nothing to pin.
    if (session.isOpen.value) setState(() => _pinned = hit);
  }

  void _onLongPressMove(CatalogLeafHit hit, LongPressMoveUpdateDetails d) =>
      _longPress?.update(d);

  // The session is not forgotten at the end of the gesture: one that waits for
  // the next click is still up, and goes with the page if it is still there.
  void _onLongPressEnd(CatalogLeafHit hit, LongPressEndDetails details) =>
      _longPress?.end(details);

  void _onSessionOpenChanged() {
    final session = _longPress;
    if (session == null || session.isOpen.value) return;
    session.isOpen.removeListener(_onSessionOpenChanged);
    _longPress = null;
    if (mounted && _pinned != null) setState(() => _pinned = null);
  }

  // [unpin] is false while the state is going away: nothing is left to draw.
  void _cancelLongPress({bool unpin = true}) {
    final session = _longPress;
    if (session == null) return;
    session.isOpen.removeListener(_onSessionOpenChanged);
    _longPress = null;
    session.cancel();
    if (unpin && mounted && _pinned != null) setState(() => _pinned = null);
  }

  void _onSecondaryTap(CatalogLeafHit hit, Offset globalPosition) {
    final collection = _model.collectionOf(hit.sectionId);
    if (collection == null) return;
    final entries = widget.policy.menuOf(
      hit,
      collection,
      _model.strings,
      arrangement: _model.arrangement,
    );
    if (entries.isEmpty) return;
    _cancelLongPress();
    _menu.show(
      globalPosition: globalPosition,
      entries: entries,
      onSelected: (id) =>
          widget.policy.onMenuAction(hit, collection, id, _host),
    );
  }

  void _onSectionAction(String sectionId, String actionId) {
    final collection = _model.collectionOf(sectionId);
    if (collection == null) return;
    widget.policy.onSectionAction(
      collection,
      actionId,
      _host,
      context: context,
      bounds: _catalog.sectionActionBoundsOf(sectionId),
      viewportBounds: _catalog.viewportBounds,
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final panel = ChromeThemeScope.panelOf(context);
    // The shell's background: transparent on glass, which the bands over the
    // catalogue then let through.
    final background = PanelBackgroundScope.of(context);
    final atBottom = _stripAtBottomNow;
    final sticky = _stripSticky;
    final browsing = sticky ? _stripShown : !_showsResults;
    final strip = browsing ? widget.policy.buildStrip(context, _strip) : null;
    // A sticky strip is drawn over the catalogue; any other is a part of the
    // column, above the catalogue or below it.
    final overlay = sticky ? strip : null;
    final inColumn = sticky ? null : strip;
    final fieldBand = _inlineSearch ? PanelSearchField.height : 0.0;
    final stripBand = overlay == null ? 0.0 : _stripExtent;
    final padding = widget.padding.copyWith(
      top: widget.padding.top + stripBand + fieldBand,
    );
    final fieldMounted = widget.searchFieldReady?.value ?? true;
    return ChromeCatalogTheme(
      child: CatalogContextMenuHost(
        host: _host,
        controller: _menu,
        child: Column(
          children: [
            if (!atBottom) ?inColumn,
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Only the catalogue binds the arrows and Space: a strip
                  // around it keeps the keys of its own controls.
                  _BelowHeader(
                    header: _header,
                    stripExtent: overlay == null ? 0 : _stripExtent,
                    fieldExtent: _inlineSearch && fieldMounted
                        ? PanelSearchField.height
                        : 0,
                    child: CatalogKeyboardFocus(
                      controller: _catalog,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (event) => _lastKind = event.kind,
                        child: PanelCatalogViewport(
                          snapshots: _model.snapshots,
                          assets: widget.assets,
                          controller: _catalog,
                          padding: padding,
                          // A header lands under the strip that overlays the
                          // catalogue, never under the field's band, which
                          // scrolls away (or, pinned, keeps a band of its own).
                          headerLandingInset: widget.padding.top + stripBand,
                          sectionNearExtent: widget.sectionNearExtent,
                          onLeafTap: _onTap,
                          onLeafSecondaryTap: _onSecondaryTap,
                          leafLongPressEligible: _longPressEligible,
                          leafLongPressDelay: _longPressDelay,
                          onLeafLongPressStart: _onLongPressStart,
                          onLeafLongPressMove: _onLongPressMove,
                          onLeafLongPressEnd: _onLongPressEnd,
                          pinnedLeaf: _pinned,
                          onSectionAction: _onSectionAction,
                        ),
                      ),
                    ),
                  ),
                  if (_inlineSearch && fieldMounted)
                    _SearchLayer(
                      header: _header,
                      background: background,
                      stripShown: overlay != null,
                      stripExtent: _stripExtent,
                    ),
                  if (overlay != null)
                    _StripLayer(
                      header: _header,
                      background: background,
                      hairline: panel.hairline,
                      extent: _stripExtent,
                      child: overlay,
                    ),
                ],
              ),
            ),
            // Measured, not assumed: no strip (results showing, a single
            // category) is an extent of nothing.
            if (atBottom)
              BottomExtentReporter(
                onExtent: _host.reportBottomExtent,
                child: inColumn ?? const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

/// The catalogue controller seen as the scroll the header reads.
final class _CatalogMetrics implements CatalogScrollMetrics {
  _CatalogMetrics(this._catalog);

  final PanelCatalogController _catalog;

  @override
  double get offset => _catalog.offset;

  @override
  double get maxScrollExtent => _catalog.maxScrollExtent;

  @override
  bool get isSectionJumpActive => _catalog.isSectionJumpActive;
}

/// The catalogue, painted from the lower edge of the bands over it (the strip,
/// the field) as they move: nothing is drawn behind them, so a band on a
/// see-through background shows what is behind the panel (its glass), not
/// cells passing under it. Hit testing is not clipped; the bands take their
/// own taps above it.
class _BelowHeader extends StatelessWidget {
  const _BelowHeader({
    required this.header,
    required this.stripExtent,
    required this.fieldExtent,
    required this.child,
  });

  final CatalogStickyHeader header;
  final double stripExtent;
  final double fieldExtent;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenValueBuilder<double>(
    listenable: header.stripOffset,
    builder: (context, stripOffset) => ListenValueBuilder<double>(
      listenable: header.searchOffset,
      builder: (context, searchOffset) {
        final strip = stripExtent > 0 ? stripExtent + stripOffset : 0.0;
        final field = fieldExtent > 0 ? searchOffset + fieldExtent : 0.0;
        return ClipRect(
          clipper: _TopEdgeClipper(math.max(0, math.max(strip, field))),
          child: child,
        );
      },
    ),
  );
}

/// The search field over the catalogue: in its band at rest, translated by the
/// header, clipped at the strip's lower edge so it passes under the strip
/// rather than over it.
class _SearchLayer extends StatelessWidget {
  const _SearchLayer({
    required this.header,
    required this.background,
    required this.stripShown,
    required this.stripExtent,
  });

  final CatalogStickyHeader header;
  final Color background;
  final bool stripShown;
  final double stripExtent;

  @override
  Widget build(BuildContext context) {
    // Built once: a frame of scrolling rebuilds the clip and the translation
    // around it, never the field.
    final field = ColoredBox(
      color: background,
      child: PanelSearchField(shadow: header.searchShadow),
    );
    return Positioned.fill(
      child: ListenValueBuilder<double>(
        listenable: header.searchOffset,
        builder: (context, offset) => ListenValueBuilder<double>(
          listenable: header.stripOffset,
          builder: (context, stripOffset) {
            final clipTop = stripShown
                ? (stripExtent + stripOffset + 1).clamp(0.0, double.infinity)
                : 0.0;
            return ClipRect(
              clipper: _TopEdgeClipper(clipTop),
              child: Align(
                alignment: Alignment.topCenter,
                child: Transform.translate(
                  offset: Offset(0, offset),
                  child: field,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The strip over the catalogue: slid up by the header, on an opaque
/// background, with a hairline under it while content passes beneath.
class _StripLayer extends StatelessWidget {
  const _StripLayer({
    required this.header,
    required this.background,
    required this.hairline,
    required this.extent,
    required this.child,
  });

  final CatalogStickyHeader header;
  final Color background;
  final Color hairline;
  final double extent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final strip = SizedBox(
      height: extent,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ColoredBox(color: background, child: child),
          ),
          // Painted below the strip's box: the strip's own layout stays its
          // height, and a hairline that fades in does not move it.
          Positioned(
            left: 0,
            right: 0,
            top: extent,
            child: _Hairline(visible: header.stripShadow, color: hairline),
          ),
        ],
      ),
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ListenValueBuilder<double>(
        listenable: header.stripOffset,
        builder: (context, offset) =>
            Transform.translate(offset: Offset(0, offset), child: strip),
      ),
    );
  }
}

/// A 1 px line that fades in and out with [visible].
class _Hairline extends StatefulWidget {
  const _Hairline({required this.visible, required this.color});

  final listen.ValueListenable<bool> visible;
  final Color color;

  @override
  State<_Hairline> createState() => _HairlineState();
}

class _HairlineState extends State<_Hairline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: widget.visible.value ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_onVisible);
  }

  @override
  void didUpdateWidget(_Hairline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.visible, widget.visible)) {
      oldWidget.visible.removeListener(_onVisible);
      widget.visible.addListener(_onVisible);
      _onVisible();
    }
  }

  @override
  void dispose() {
    widget.visible.removeListener(_onVisible);
    _fade.dispose();
    super.dispose();
  }

  void _onVisible() {
    final duration = ChromeMotionScope.of(context).durationOf(MotionRole.fade);
    if (widget.visible.value) {
      unawaited(_fade.animateTo(1, duration: duration));
    } else {
      unawaited(_fade.animateBack(0, duration: duration));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    builder: (context, _) {
      final t = Curves.easeOut.transform(_fade.value);
      if (t <= 0.001) return const SizedBox.shrink();
      // Alpha on the fill, not an Opacity: no saveLayer while it fades over
      // scrolling content.
      return ColoredBox(
        color: widget.color.withValues(alpha: widget.color.a * t),
        child: const SizedBox(height: 1, width: double.infinity),
      );
    },
  );
}

/// Keeps painting below [top]; anything drawn above that edge is clipped.
final class _TopEdgeClipper extends CustomClipper<Rect> {
  const _TopEdgeClipper(this.top);

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);

  @override
  bool shouldReclip(_TopEdgeClipper oldClipper) => oldClipper.top != top;
}

final class _StripHandle implements CatalogStripHandle {
  _StripHandle(this._model, this._catalog, this._revealNow);

  final CatalogPageModel _model;
  final PanelCatalogController _catalog;
  final void Function() _revealNow;

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
      final index? => () {
        // A jump starts from a strip that is whole: it lands under it.
        _revealNow();
        return _catalog.jumpToSection(index);
      }(),
      null => Future<void>.value(),
    };
  }
}
