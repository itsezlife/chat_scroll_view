import 'dart:async' show Completer, Future, unawaited;
import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/src/data/catalog_data_source.dart';
import 'package:panel_catalog/src/debug/panel_catalog_dev_log.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_leaf_presentation.dart';
import 'package:panel_catalog/src/viewport/catalog_far_stitch.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_binding_pool.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_painter.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_pointer.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_press.dart';
import 'package:panel_catalog/src/viewport/catalog_near_scroll.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_physics.dart';
import 'package:panel_catalog/src/viewport/catalog_section_navigation.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_controller.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_scroll_events.dart';

/// Paint-leaf render object for the panel catalog body.
///
/// Owns **extent scroll**, **visible-band asset binding**, and **canvas paint**
/// for section headers + leaves. Layout fills the parent's constraints
/// ([size] is the viewport). Content taller than the viewport scrolls by an
/// absolute content offset on [PanelCatalogController].
///
/// Does **not** own panel chrome (category strip, search, type tabs, pickers),
/// asset fetch/decode ([CatalogAssetCache] does), or catalog fetch
/// ([CatalogDataSource] does). Hosts wire those; this object only listens and
/// projects.
///
/// ## Layout model
///
/// Catalog geometry is a known content height ([contentExtent]), not an
/// id-relative anchor. [projectCatalogSlots] flattens
/// [CatalogDataSource.sections] into absolute header/leaf slots in content
/// coordinates (y increases downward from the catalog top). Scroll range is:
///
/// ```text
/// maxOffset = max(0, contentExtent − size.height)
/// offset    ∈ [0, maxOffset]
/// ```
///
/// [size] is always the viewport. Intrinsic height is **not** the content
/// extent — parents that ask for intrinsic height get `0` so they do not
/// treat this as a tall scrollable child that expands to fit all rows.
///
/// ## Paint leaves (not child render objects)
///
/// Leaves are drawn by [CatalogLeafPainter] onto a clipped canvas. This
/// object MUST NOT mount a child [RenderBox] per leaf: a unicode panel can
/// hold thousands of cells, and per-cell element/RO inflation would dominate
/// memory and layout cost. Headers are paint-only as well.
///
/// Scrolling is Tier-1 cheap: clamp + re-sync bindings + [markNeedsPaint].
/// Unicode glyphs reuse a layout-once paragraph cache (drawParagraph only on
/// scroll). Geometry changes (span, pitch, padding, data notify) call
/// [markCatalogNeedsUpdate] so the next layout reprojects slots.
///
/// ## Binding recycle
///
/// [CatalogLeafBindingPool] attaches [CatalogAssetCache] bindings only for
/// leaf slots intersecting the visible window (viewport band plus one
/// [cellExtent] of overscan above and below). Leaves that leave that band
/// are detached unless their key is listed in the stitch pin set during
/// far-path flight ([CatalogFarStitch]) so outgoing strip bindings survive
/// the teleport. Readiness changes on attached bindings mark paint dirty so
/// placeholders flip to content without a full catalog reproject.
///
/// Overscan is intentionally one cell row: enough that a short drag does not
/// thrash attach/detach every frame, not a second viewport of prefetched
/// bindings. Empty / short catalogs still project headers; unbound leaves
/// paint as loading placeholders via [CatalogLeafPresentation].
///
/// ## Scroll input
///
/// Drag (`VerticalDragGestureRecognizer`) and pointer-wheel
/// ([PointerScrollEvent]) both call [PanelCatalogController.scrollBy].
/// Drag-up (negative primary delta) reveals content below → positive delta
/// on the controller. Drag start cancels fling and clears in-flight press.
///
/// Drag uses [DragStartBehavior.start] (Flutter default). On leaf downs,
/// [CatalogLeafPointer] registers tap / long-press into the same arena, so
/// vertical drag cannot win until the pointer exceeds touch slop. With
/// [DragStartBehavior.down], acceptance would dump the entire pending delta
/// as one [scrollBy] (~[kTouchSlop] jump). [DragStartBehavior.start] absorbs
/// that pending delta into the drag origin so the first applied scroll is
/// only post-acceptance motion.
///
/// ## Fling physics
///
/// Drag-end with sufficient velocity starts a ballistic fling
/// ([CatalogScrollPhysics] / [ClampingScrollSimulation]) in content offset
/// space. Each tick applies [PanelCatalogController.scrollBy] until the
/// simulation ends or offset hits `[0, maxOffset]`. Fling cancels on drag
/// start, wheel, [jumpTo], [PanelCatalogController.jumpToSection], scroll wall,
/// or pointer-down while flinging.
///
/// ## Section jump
///
/// [PanelCatalogController.jumpToSection] lands a section header under
/// [padding.top] (strip inset band). Path selection uses
/// [isNearPathSectionJump]: attached-header shortcut, else flat-row distance
/// `≤ [kFarPathDistanceGateFactor]` (not multiplied by [spanCount]). Near
/// targets animate via [CatalogNearScroll] (220ms decelerate curve). Far
/// targets use [CatalogFarStitch] (capture outgoing strip → teleport →
/// dual-translate).
///
/// While [PanelCatalogController.isSectionJumpActive], the controller ignores
/// additional [jumpToSection] requests (in-flight future returned; this object
/// is not re-entered). User drag / [jumpTo] / [scrollBy] cancel in-flight
/// near scroll or stitch. Motion writes [PanelCatalogController.correctOffset]
/// only so scroll-by listeners stay quiet; [PanelCatalogController.isSectionJumpActive]
/// gates host strip sync for both paths.
///
/// A pointer-down that cancels an in-flight fling suppresses leaf tap /
/// long-press for that pointer so stopping the coast does not insert a leaf.
/// Press scale is also skipped for that pointer; suppress clears post-frame
/// after pointer-up so arena tap resolution still sees the flag.
///
/// After every navigation notify, this object clamps via
/// [PanelCatalogController.correctOffset] (silent — jump/scroll listeners
/// are not re-fired). Until that correction runs, [offset] MAY briefly sit
/// outside `[0, maxOffset]` (e.g. jump past the end before layout knows
/// [contentExtent]).
///
/// ## Hit-test and press
///
/// The entire viewport is the hit target ([hitTestSelf]). On pointer-down,
/// [leafAt] maps viewport-local coordinates through scroll offset into a
/// [CatalogLeaf] (or `null` on headers / padding). [CatalogLeafPointer]
/// registers tap / long-press for leaf downs when wired;
/// [CatalogLeafPointer.leafLongPressEligible] skips the long-press recognizer
/// on ineligible leaves. Drag always receives the pointer so scroll still wins
/// the arena when the finger moves. Press scale starts on leaf-down via
/// [CatalogLeafPress], keyed by [CatalogLeafSlotKey] (content position), not
/// [CatalogLeaf.assetKey], so duplicate glyphs in different sections animate
/// independently. Painted as `0.8 + 0.2 * (1 − progress)`. Drag start and
/// long-press cancel call press-out. Pointer move that leaves the pressed cell
/// rect also releases.
/// List-selector highlight (full cell rect, themed radius/color) tracks the
/// same press progress without scaling with glyph content.
///
/// ## Paint theme
///
/// [CatalogLeafPaintTheme] is supplied at construction and updated via
/// [paintTheme]. Snapshot is built by [PanelCatalogViewport] from
/// [PanelCatalogTheme.of] + device pixel ratio — this object does not read
/// [BuildContext]. Paint-only changes mark [markNeedsPaint] without layout.
///
/// ## Cold-start warm-up
///
/// [warmAhead] walks unicode leaves in the first `[screens]` viewport heights
/// from the current offset, ensures layout-once paragraphs via
/// [CatalogLeafPainter.ensureGlyphParagraph], then optionally awaits
/// [CatalogLeafPainter.rasterizeGlyphsForWarmup]. Concurrent callers share one
/// in-flight future. Silent no-op before first layout, when detached, or when
/// the band has no unicode glyphs. Hosts invoke via
/// [PanelCatalogController.warmAhead] from open / idle — not from scroll ticks.
///
/// ## Lifecycle
///
/// - [attach]: register data + controller listeners; create drag, leaf
///   pointer, press tickers, and press controller.
/// - [detach]: unregister listeners; dispose recognizers / press / fling;
///   [CatalogLeafBindingPool.detachAll].
/// - [dispose]: same binding/painter teardown; safe if already detached.
///
/// Listeners are only live while attached. Swapping [dataSource] /
/// [controller] while attached rebinds without leaking the previous
/// subscription.
///
/// ## Paint coordinates
///
/// Content is painted with origin `paintOffset.translate(0, −offset)` so
/// content-y `offset` aligns with the viewport top. The canvas is clipped to
/// the viewport rect. Slots outside the visible window (including overscan)
/// are skipped in the paint loop even if still bound.
///
/// Constructed by [PanelCatalogViewport]; not exported from the public barrel.
class RenderPanelCatalog extends RenderBox {
  /// Creates a panel catalog render body.
  ///
  /// [spanCount] MUST be ≥ 1. [cellExtent] / [headerExtent] SHOULD be > 0;
  /// zero collapses rows/headers to empty bands but does not assert.
  /// Negative [padding] is undefined.
  ///
  /// Leaf callbacks are forwarded to [CatalogLeafPointer] while attached;
  /// null long-press start disables the long-press recognizer.
  RenderPanelCatalog({
    required CatalogDataSource dataSource,
    required CatalogAssetCache assetCache,
    required PanelCatalogController controller,
    required int spanCount,
    required double cellExtent,
    required double headerExtent,
    required EdgeInsets padding,
    double? headerLandingInset,
    required CatalogAssetCacheType cacheType,
    required CatalogLeafPaintTheme paintTheme,
    ValueChanged<CatalogLeaf>? onLeafTap,
    void Function(CatalogLeaf leaf, LongPressStartDetails details)?
    onLeafLongPressStart,
    void Function(CatalogLeaf leaf, LongPressMoveUpdateDetails details)?
    onLeafLongPressMove,
    void Function(CatalogLeaf leaf, LongPressEndDetails details)?
    onLeafLongPressEnd,
    bool Function(CatalogLeaf leaf)? leafLongPressEligible,
  }) : _dataSource = dataSource,
       _controller = controller,
       _spanCount = spanCount,
       _cellExtent = cellExtent,
       _headerExtent = headerExtent,
       _padding = padding,
       _headerLandingInset = headerLandingInset,
       _onLeafTap = onLeafTap,
       _onLeafLongPressStart = onLeafLongPressStart,
       _onLeafLongPressMove = onLeafLongPressMove,
       _onLeafLongPressEnd = onLeafLongPressEnd,
       _leafLongPressEligible = leafLongPressEligible,
       _paintTheme = paintTheme,
       _painter = CatalogLeafPainter(theme: paintTheme) {
    _pool = CatalogLeafBindingPool(
      assetCache: assetCache,
      cacheType: cacheType,
      onReadinessChanged: markNeedsPaint,
    );
    _leafPointer = CatalogLeafPointer(debugOwner: this)
      ..leafAt = leafAt
      ..onLeafTap = onLeafTap
      ..onLeafLongPressStart = onLeafLongPressStart
      ..onLeafLongPressMove = onLeafLongPressMove
      ..onLeafLongPressEnd = onLeafLongPressEnd
      ..leafLongPressEligible = leafLongPressEligible
      ..onGestureCancel = _onLeafGestureCancel
      ..flingCancelSuppresses = () => _flingCancelSuppressesLeaf;
  }

  // --- Configuration --------------------------------------------------------

  /// Authoritative catalog contents. Reprojected on [CatalogDataSource]
  /// notify while attached.
  ///
  /// Swapping while attached moves the data listener to the new source and
  /// marks layout+paint dirty. The previous source is unsubscribed first.
  CatalogDataSource _dataSource;
  set dataSource(CatalogDataSource value) {
    if (_dataSource == value) return;
    if (attached) {
      _dataSource.removeDataListener(_onDataChanged);
    }
    _dataSource = value;
    if (attached) {
      _dataSource.addDataListener(_onDataChanged);
    }
    markCatalogNeedsUpdate();
  }

  /// Absolute content-offset owner. Jump/scroll listeners drive clamp +
  /// binding sync + paint (not layout) while attached.
  ///
  /// Swapping while attached rebinds listeners, reclamps, and re-syncs the
  /// visible band against the new controller's [PanelCatalogController.offset].
  /// [jumpTo] cancels an in-flight fling before navigation runs.
  PanelCatalogController _controller;
  set controller(PanelCatalogController value) {
    if (_controller == value) return;
    if (attached) {
      _unbindController(_controller);
    }
    _controller = value;
    if (attached) {
      _bindController(_controller);
    }
    _clampOffset();
    _syncVisibleBindings();
    markNeedsPaint();
  }

  /// Process-wide asset cache. Replacing detaches every binding first
  /// ([CatalogLeafBindingPool.replaceCache]) then reprojects.
  set assetCache(CatalogAssetCache value) {
    _pool.replaceCache(value);
    markCatalogNeedsUpdate();
  }

  /// Leaf columns in the grid. Changing span reprojects all slots.
  int _spanCount;
  set spanCount(int value) {
    if (_spanCount == value) return;
    _spanCount = value;
    markCatalogNeedsUpdate();
  }

  /// Square cell pitch in content coordinates.
  ///
  /// Also the visible-band overscan unit: the bind window extends one
  /// [cellExtent] above and below the viewport.
  double _cellExtent;
  set cellExtent(double value) {
    if (_cellExtent == value) return;
    _cellExtent = value;
    markCatalogNeedsUpdate();
  }

  /// Section header band height in content coordinates.
  double _headerExtent;
  set headerExtent(double value) {
    if (_headerExtent == value) return;
    _headerExtent = value;
    markCatalogNeedsUpdate();
  }

  /// Insets included in [contentExtent] (top/bottom) and cell x (left/right).
  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markCatalogNeedsUpdate();
  }

  /// Section-jump landing inset; null → [padding.top].
  double? _headerLandingInset;
  set headerLandingInset(double? value) {
    if (_headerLandingInset == value) return;
    _headerLandingInset = value;
    markCatalogNeedsUpdate();
  }

  /// Attach size class for leaf bindings. Replacing detaches then reprojects.
  set cacheType(CatalogAssetCacheType value) {
    _pool.replaceCacheType(value);
    markCatalogNeedsUpdate();
  }

  /// [CatalogLeafPaintTheme] forwarded to [CatalogLeafPainter].
  ///
  /// No-op when [value] equals the current snapshot. Does not reproject layout.
  /// DPR changes MUST produce a new unequal snapshot from the viewport.
  CatalogLeafPaintTheme _paintTheme;
  set paintTheme(CatalogLeafPaintTheme value) {
    if (_paintTheme == value) return;
    _paintTheme = value;
    _painter.theme = value;
    markNeedsPaint();
  }

  /// Shell tap callback. Rebinding updates the leaf pointer while attached.
  ValueChanged<CatalogLeaf>? _onLeafTap;
  set onLeafTap(ValueChanged<CatalogLeaf>? value) {
    if (_onLeafTap == value) return;
    _onLeafTap = value;
    _leafPointer.onLeafTap = value;
  }

  /// Shell long-press start. Null disables the long-press recognizer.
  void Function(CatalogLeaf leaf, LongPressStartDetails details)?
  _onLeafLongPressStart;
  set onLeafLongPressStart(
    void Function(CatalogLeaf leaf, LongPressStartDetails details)? value,
  ) {
    if (_onLeafLongPressStart == value) return;
    _onLeafLongPressStart = value;
    _leafPointer.onLeafLongPressStart = value;
  }

  /// Shell long-press move. Ignored when start is null.
  void Function(CatalogLeaf leaf, LongPressMoveUpdateDetails details)?
  _onLeafLongPressMove;
  set onLeafLongPressMove(
    void Function(CatalogLeaf leaf, LongPressMoveUpdateDetails details)? value,
  ) {
    if (_onLeafLongPressMove == value) return;
    _onLeafLongPressMove = value;
    _leafPointer.onLeafLongPressMove = value;
  }

  /// Shell long-press end. Ignored when start is null.
  void Function(CatalogLeaf leaf, LongPressEndDetails details)?
  _onLeafLongPressEnd;
  set onLeafLongPressEnd(
    void Function(CatalogLeaf leaf, LongPressEndDetails details)? value,
  ) {
    if (_onLeafLongPressEnd == value) return;
    _onLeafLongPressEnd = value;
    _leafPointer.onLeafLongPressEnd = value;
  }

  /// Per-leaf long-press registration gate. Null = all leaves eligible.
  bool Function(CatalogLeaf leaf)? _leafLongPressEligible;
  set leafLongPressEligible(bool Function(CatalogLeaf leaf)? value) {
    if (_leafLongPressEligible == value) return;
    _leafLongPressEligible = value;
    _leafPointer.leafLongPressEligible = value;
  }

  // --- Runtime state --------------------------------------------------------

  late CatalogLeafBindingPool _pool;
  final CatalogLeafPainter _painter;
  late final CatalogLeafPointer _leafPointer;

  /// Ballistic scroll simulation and tick integration in content offset space.
  final CatalogScrollPhysics _physics = CatalogScrollPhysics();

  /// Near-path section jump animation; null after [detach] / [dispose].
  CatalogNearScroll? _nearScroll;

  /// Far-path stitch animation; null after [detach] / [dispose].
  CatalogFarStitch? _farStitch;

  /// Outgoing strip captured before stitch teleport (viewport-local geometry).
  List<CatalogStitchCapturedSlot> _stitchOutgoing = const [];

  /// Outgoing leaf bindings pinned for the stitch flight.
  Set<CatalogAssetKey> _stitchPinnedKeys = const {};

  /// Completes when the in-flight far stitch settles or is cancelled.
  Completer<void>? _stitchFlightCompleter;

  /// Shared [TickerProvider] for press animation and fling ticks while attached.
  CatalogPressTickerProvider? _pressTickers;

  /// Press-scale controller; null after [detach] / [dispose].
  CatalogLeafPress? _press;

  /// Drives [_onFlingTick] while [_physics.isFlinging]; stopped on cancel.
  Ticker? _flingTicker;

  /// Active press pointer and its viewport-local leaf rect for move-out cancel.
  int? _pressPointer;
  Offset? _pressLeafOrigin;
  Size? _pressLeafSize;

  /// Pointer that cancelled an in-flight fling; leaf tap/long-press suppressed
  /// until that pointer goes up (cleared post-frame so the arena tap still
  /// sees the flag).
  int? _flingCancelPointer;
  var _flingCancelSuppressesLeaf = false;

  /// Flattened header + leaf slots from the last [performLayout] project.
  /// Empty until the first layout.
  List<CatalogLayoutSlot> _slots = const [];

  double _contentExtent = 0;
  VerticalDragGestureRecognizer? _drag;

  // --- Diagnostics (filter DevTools / logcat by logger name) ----------------

  final PanelCatalogDevLog _layoutLog = PanelCatalogDevLog(
    'PanelCatalogLayout',
  );
  final PanelCatalogDevLog _scrollLog = PanelCatalogDevLog(
    'PanelCatalogScroll',
  );
  final PanelCatalogDevLog _paintLog = PanelCatalogDevLog('PanelCatalogPaint');

  double? _layoutLogLastExtent;
  int? _layoutLogLastSlotCount;

  // --- Observability --------------------------------------------------------

  /// Total catalog content height after the last project (padding included).
  ///
  /// `0` before the first layout. Short catalogs may be smaller than
  /// [size].height — then [maxOffset] is `0` and scroll input is a no-op after
  /// clamp.
  double get contentExtent => _contentExtent;

  /// Maximum scroll offset for the current viewport height.
  ///
  /// Requires [hasSize]; callers MUST NOT read this before the first layout.
  /// Equals `max(0, contentExtent − size.height)`.
  double get maxOffset => math.max(0.0, _contentExtent - size.height);

  /// Flat leaf [CatalogAssetKey]s in projection order (headers omitted).
  ///
  /// Reflects the last project — empty before layout, or when every section
  /// has no leaves.
  List<CatalogAssetKey> get projectedAssetKeys => [
    for (final slot in _slots)
      if (slot case final CatalogLeafSlot leaf) leaf.leaf.assetKey,
  ];

  /// Presentation for [key], or `null` when no projected leaf matches.
  ///
  /// Uses the binding pool (live bind or settled [CatalogAssetCache.readinessOf]).
  /// `null` means the key is absent from the current projection entirely.
  CatalogLeafPresentation? presentationOf(CatalogAssetKey key) {
    for (final slot in _slots) {
      if (slot case final CatalogLeafSlot leaf when leaf.leaf.assetKey == key) {
        return _pool.presentationFor(leaf.leaf);
      }
    }
    return null;
  }

  /// Count of leaves currently retained via asset-cache attach.
  ///
  /// Bounded by the visible window + overscan, not by total catalog size.
  int get attachedLeafCount => _pool.attachedCount;

  /// Test seam: drops every pool binding without disposing this render object.
  ///
  /// Models pager keep-alive leave (`detachAll` while the page [State] and
  /// [CatalogAssetCache] survive). Settled cache readiness MUST still drive
  /// [presentationOf] so paint does not flash loading placeholders.
  @visibleForTesting
  void debugDetachBindings() => _pool.detachAll();

  /// Whether a ballistic fling is currently driving [PanelCatalogController.offset].
  bool get isFlinging => _physics.isFlinging;

  /// Cell currently receiving press-scale feedback, or `null` when idle.
  ///
  /// Test / debug seam for paint press — keyed by content slot, not
  /// [CatalogLeaf.assetKey], so duplicate glyphs animate independently.
  CatalogLeafSlotKey? get pressedSlotKey => _press?.pressedSlotKey;

  /// Press amount for [pressedSlotKey]: `0` idle … `1` fully pressed; may be
  /// slightly negative during overshoot release.
  double get pressProgress => _press?.progress ?? 0;

  /// Whether a near-path section jump animation is driving offset.
  bool get isSectionJumpAnimating => _nearScroll?.isActive ?? false;

  /// Whether a far-path stitch flight is active (post-teleport dual-translate).
  bool get isFarStitchActive => _farStitch?.isActive ?? false;

  /// Eased stitch progress in `[0, 1]` while [isFarStitchActive]; `0` when idle.
  double get farStitchProgress => _farStitch?.progress ?? 0;

  /// Wall time of the last [performLayout] (project + size + bind sync).
  ///
  /// Test / diagnostics seam — not part of the host contract. Updated every
  /// layout pass (always-on wall clock, not assert-gated). `Duration.zero`
  /// before the first layout.
  @visibleForTesting
  Duration debugLastLayoutDuration = Duration.zero;

  /// Wall time of the last [paint] (clip + leaf/header draw, or stitch flight).
  ///
  /// Test / diagnostics seam — not part of the host contract. Updated every
  /// paint (always-on wall clock, not assert-gated). `Duration.zero` before
  /// the first paint.
  @visibleForTesting
  Duration debugLastPaintDuration = Duration.zero;

  /// Resolves the [CatalogLeaf] under [localPosition], or `null` when the
  /// point lies on a header, padding, or empty band.
  ///
  /// [localPosition] is viewport-local (post-hit-test). Content y adds the
  /// current scroll [PanelCatalogController.offset]. Requires [hasSize] and
  /// a prior project — returns `null` before the first layout.
  CatalogLeaf? leafAt(Offset localPosition) => leafSlotAt(localPosition)?.leaf;

  /// Resolves the leaf [CatalogLeafSlot] under [localPosition], or `null`.
  ///
  /// Used for press feedback and pointer routing so duplicate [CatalogLeaf]
  /// identities in different sections stay independent.
  CatalogLeafSlot? leafSlotAt(Offset localPosition) {
    if (!hasSize) return null;
    final contentX = localPosition.dx;
    final contentY = localPosition.dy + _controller.offset;
    for (final slot in _slots) {
      if (slot case final CatalogLeafSlot leaf) {
        if (contentX >= leaf.left &&
            contentX < leaf.left + leaf.width &&
            contentY >= leaf.top &&
            contentY < leaf.bottom) {
          return leaf;
        }
      }
    }
    return null;
  }

  // --- Cold-start warm-up ---------------------------------------------------

  /// In-flight warm-up future; concurrent [warmAhead] callers share it.
  Future<void>? _warmInFlight;

  /// Prepares unicode glyphs for the first `[screens]` viewport heights.
  ///
  /// Band is `[offset, offset + height × screens]` clamped to content
  /// ([screens] clamped to `[1, 8]`). Ensures layout-once paragraphs for each
  /// unicode leaf in the band; when [rasterize] is true, awaits
  /// [CatalogLeafPainter.rasterizeGlyphsForWarmup]. Concurrent callers share
  /// one future. Silent no-op when detached, before first layout, when
  /// glyph width ≤ 0, or when the band has no unicode leaves. Completes
  /// immediately when [rasterize] is false after paragraph ensure. MUST NOT
  /// be driven from scroll / paint ticks.
  Future<void> warmAhead({double screens = 2.5, bool rasterize = true}) {
    final existing = _warmInFlight;
    if (existing != null) return existing;
    final future = _warmAheadBody(screens: screens, rasterize: rasterize);
    _warmInFlight = future;
    return future.whenComplete(() {
      if (identical(_warmInFlight, future)) {
        _warmInFlight = null;
      }
    });
  }

  /// Band walk + optional offscreen raster for [warmAhead]. Clears
  /// [_warmInFlight] via the public future’s `whenComplete`.
  Future<void> _warmAheadBody({
    required double screens,
    required bool rasterize,
  }) async {
    if (!attached || !hasSize || _slots.isEmpty) return;
    final bandBottom = math.min(
      _contentExtent,
      _controller.offset + size.height * screens.clamp(1.0, 8.0),
    );
    final bandTop = _controller.offset.clamp(0.0, _contentExtent);
    final glyphWidth = _glyphLogicalWidth;
    if (glyphWidth <= 0) return;

    final glyphs = <String>[];
    final start = _firstSlotIndexAtOrBelow(bandTop);
    final end = _slotIndexAfter(bandBottom);
    for (var i = start; i < end; i++) {
      final slot = _slots[i];
      if (slot.bottom < bandTop || slot.top > bandBottom) continue;
      if (slot case CatalogLeafSlot(:final leaf)) {
        if (leaf case UnicodeCatalogLeaf(:final glyph)) {
          glyphs.add(glyph);
          _painter.ensureGlyphParagraph(glyph, glyphWidth);
        }
      }
    }
    if (!rasterize || glyphs.isEmpty) return;
    await _painter.rasterizeGlyphsForWarmup(
      glyphs: glyphs,
      logicalWidth: glyphWidth,
    );
  }

  /// Logical glyph draw width matching [CatalogLeafPainter] (~72% of cell pitch).
  double get _glyphLogicalWidth {
    final usableW = (size.width - _padding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final cellW = usableW > 0 ? usableW / _spanCount : _cellExtent;
    return math.min(cellW, _cellExtent) * 0.72;
  }

  // --- Catalog invalidation -------------------------------------------------

  /// Marks layout and paint dirty after catalog or geometry changes.
  ///
  /// Prefer this over bare [markNeedsLayout] when slot projection may change
  /// — paint alone would show stale slot geometry until the next unrelated
  /// layout.
  void markCatalogNeedsUpdate() {
    markNeedsLayout();
    markNeedsPaint();
  }

  void _onDataChanged() {
    if (_layoutLog.enabled) {
      _layoutLog.event('data.notify', {
        'sections': _dataSource.sections.length,
        'leaves': _dataSource.sections.fold<int>(
          0,
          (n, s) => n + s.leaves.length,
        ),
      });
    }
    markCatalogNeedsUpdate();
  }

  // --- Controller binding ---------------------------------------------------

  /// Shared path for jump + scroll-by: clamp, recycle bindings, paint.
  ///
  /// Does **not** mark layout — absolute offset changes do not alter slot
  /// geometry, only which band is visible and where content is translated.
  void _onNavigation() {
    _clampOffset();
    _syncVisibleBindings();
    markNeedsPaint();
  }

  void _bindController(PanelCatalogController controller) {
    controller
      ..addJumpListener(_onJump)
      ..addScrollByListener(_onScrollBy)
      ..addSectionJumpListener(_onSectionJump)
      ..addAnimateToListener(_onAnimateTo)
      ..bindWarmAheadHandler((screens) => warmAhead(screens: screens));
  }

  void _unbindController(PanelCatalogController controller) {
    controller
      ..removeJumpListener(_onJump)
      ..removeScrollByListener(_onScrollBy)
      ..removeSectionJumpListener(_onSectionJump)
      ..removeAnimateToListener(_onAnimateTo)
      ..bindWarmAheadHandler(null);
  }

  /// Cancels near scroll + fling, then runs the navigation path.
  void _onJump(double pixels) {
    _cancelSectionJumpMotion();
    _cancelFling();
    _onNavigation();
    if (_scrollLog.enabled) {
      _scrollLog.event('jump', {'offset': DevLogFormat.f(_controller.offset)});
    }
  }

  void _onScrollBy(double delta) {
    _cancelSectionJumpMotion();
    _onNavigation();
    if (_scrollLog.enabled) {
      _scrollLog.event('scrollBy', {
        'delta': DevLogFormat.f(delta),
        'offset': DevLogFormat.f(_controller.offset),
      });
    }
  }

  void _onSectionJump(int sectionIndex) {
    _handleSectionJump(sectionIndex);
  }

  void _onAnimateTo() {
    unawaited(_handleAnimateTo());
  }

  /// Runs a host-requested [PanelCatalogController.animateTo].
  Future<void> _handleAnimateTo() async {
    final pending = _controller.pendingAnimateTo;
    if (pending == null) return;
    final (target, duration, curve, completer) = pending;

    if (!attached) {
      _controller.completePendingAnimateTo();
      return;
    }

    if (!hasSize) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) {
          unawaited(_handleAnimateTo());
        }
      });
      return;
    }

    if (maxOffset + 0.5 < target) {
      markNeedsLayout();
      await WidgetsBinding.instance.endOfFrame;
      if (!attached || _controller.pendingAnimateTo == null) return;
    }

    _cancelSectionJumpMotion();
    _cancelFling();

    if ((_controller.offset - target).abs() < 1) {
      _controller.applyOffset(target);
      _onNavigation();
      _controller.completePendingAnimateTo();
      return;
    }

    final nearScroll = _nearScroll;
    if (nearScroll == null || !hasSize) {
      _controller.jumpTo(target);
      _onNavigation();
      _clampOffset();
      _controller.completePendingAnimateTo();
      return;
    }

    markNeedsLayout();
    _controller.notifyScrollEvent(PanelCatalogAnimateStart(target, duration));
    try {
      final from = _controller.offset;
      await nearScroll.animate(
        from: from,
        to: target,
        duration: duration,
        curve: curve,
        applyOffset: _controller.applyOffset,
      );
      _clampOffset();
      _syncVisibleBindings();
      markNeedsPaint();
    } finally {
      _controller.notifyScrollEvent(PanelCatalogAnimateEnd(_controller.offset));
      _controller.completePendingAnimateTo();
    }
  }

  // --- Section jump (near-path animate; far-path stitch) --------------------

  /// Path-selects near smooth scroll vs far stitch, then completes the pending
  /// [PanelCatalogController.jumpToSection] future.
  Future<void> _handleSectionJump(int sectionIndex) async {
    final sections = _dataSource.sections;
    if (sectionIndex < 0 || sectionIndex >= sections.length) {
      _controller.setSectionJumpActive(false);
      _controller.completePendingSectionJump(sectionIndex: sectionIndex);
      return;
    }
    if (!hasSize) {
      _controller.setSectionJumpActive(false);
      _controller.completePendingSectionJump(sectionIndex: sectionIndex);
      return;
    }

    _cancelFling();
    _cancelSectionJumpMotion();

    final targetOffset = scrollOffsetForSectionHeader(
      sectionIndex: sectionIndex,
      sections: sections,
      spanCount: _spanCount,
      cellExtent: _cellExtent,
      headerExtent: _headerExtent,
      padding: _padding,
      headerLandingInset: _headerLandingInset,
    ).clamp(0.0, maxOffset);

    if ((targetOffset - _controller.offset).abs() < 1) {
      _controller.applyOffset(targetOffset);
      _onNavigation();
      _controller.setSectionJumpActive(false);
      _controller.completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.notifyScrollEvent(PanelCatalogSectionJumpEnd(sectionIndex));
      return;
    }

    final near = isNearPathSectionJump(
      targetSectionIndex: sectionIndex,
      sections: sections,
      spanCount: _spanCount,
      cellExtent: _cellExtent,
      headerExtent: _headerExtent,
      padding: _padding,
      scrollOffset: _controller.offset,
      viewportHeight: size.height,
    );

    if (_scrollLog.enabled) {
      _scrollLog.event('sectionJump.begin', {
        'section': sectionIndex,
        'from': DevLogFormat.f(_controller.offset),
        'to': DevLogFormat.f(targetOffset),
        'near': near,
        'sectionId': sections[sectionIndex].id,
      });
    }

    _controller.setSectionJumpActive(true);

    if (!near) {
      await _runFarStitch(
        sectionIndex: sectionIndex,
        targetOffset: targetOffset,
      );
      return;
    }

    _controller.notifyScrollEvent(
      PanelCatalogSectionJumpStart(sectionIndex, targetOffset, farPath: false),
    );

    final nearScroll = _nearScroll;
    if (nearScroll == null) {
      _controller.jumpTo(targetOffset);
      _onNavigation();
      _controller.setSectionJumpActive(false);
      _controller.completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.notifyScrollEvent(PanelCatalogSectionJumpEnd(sectionIndex));
      return;
    }

    try {
      final from = _controller.offset;
      await nearScroll.animate(
        from: from,
        to: targetOffset,
        applyOffset: _controller.applyOffset,
      );
      _clampOffset();
      _syncVisibleBindings();
      markNeedsPaint();
    } finally {
      _controller.setSectionJumpActive(false);
      _controller.completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.notifyScrollEvent(PanelCatalogSectionJumpEnd(sectionIndex));
      if (_scrollLog.enabled) {
        _scrollLog.event('sectionJump.end', {
          'section': sectionIndex,
          'offset': DevLogFormat.f(_controller.offset),
          'path': 'near',
        });
      }
    }
  }

  void _cancelNearScroll({int? forSectionIndex}) {
    final wasActive = _nearScroll?.isActive ?? false;
    _nearScroll?.cancel();
    if (!wasActive) return;
    if (_controller.pendingAnimateTo != null) {
      _controller.completePendingAnimateTo();
      return;
    }
    _controller.setSectionJumpActive(false);
    _controller.completePendingSectionJump(sectionIndex: forSectionIndex);
  }

  /// Cancels an in-flight far-path stitch and completes the pending section jump.
  void _cancelFarStitch({int? forSectionIndex}) {
    final wasActive = _farStitch?.isActive ?? false;
    _farStitch?.cancel();
    if (wasActive) {
      _clearStitchCapture();
      final completer = _stitchFlightCompleter;
      _stitchFlightCompleter = null;
      completer?.complete();
      _controller.setSectionJumpActive(false);
      _controller.completePendingSectionJump(sectionIndex: forSectionIndex);
    }
  }

  /// Cancels near-path scroll and far-path stitch programmatic motion.
  void _cancelSectionJumpMotion({int? forSectionIndex}) {
    _cancelNearScroll(forSectionIndex: forSectionIndex);
    _cancelFarStitch(forSectionIndex: forSectionIndex);
    _controller.completePendingAnimateTo();
  }

  /// Runs far-path stitch: capture → teleport → measure → dual-translate.
  ///
  /// When [_farStitch] is null (detached tickers), falls back to silent
  /// [PanelCatalogController.correctOffset] only. When the outgoing capture
  /// is empty, still runs an incoming-only stitch flight (destination band
  /// slides in from off-screen) rather than showing the teleported catalog
  /// at rest for one frame.
  Future<void> _runFarStitch({
    required int sectionIndex,
    required double targetOffset,
  }) async {
    final farStitch = _farStitch;
    if (farStitch == null) {
      _controller.applyOffset(targetOffset);
      _clampOffset();
      _onNavigation();
      _controller.notifyScrollEvent(
        PanelCatalogSectionJumpStart(sectionIndex, targetOffset, farPath: true),
      );
      _controller.setSectionJumpActive(false);
      _controller.completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.notifyScrollEvent(PanelCatalogSectionJumpEnd(sectionIndex));
      return;
    }

    final fromOffset = _controller.offset;
    final towardNewer = targetOffset > fromOffset;

    _stitchOutgoing = captureCatalogStitchOutgoing(
      slots: _slots,
      scrollOffset: fromOffset,
      viewportHeight: size.height,
    );
    _stitchPinnedKeys = catalogStitchOutgoingLeafKeys(_stitchOutgoing);

    final flight = Completer<void>();
    _stitchFlightCompleter = flight;
    farStitch.begin(towardNewer: towardNewer);
    _controller.applyOffset(targetOffset);
    _clampOffset();
    _syncVisibleBindings();
    _controller.notifyScrollEvent(
      PanelCatalogSectionJumpStart(sectionIndex, targetOffset, farPath: true),
    );
    _beginStitchMeasureIfNeeded();
    markNeedsLayout();
    markNeedsPaint();

    try {
      await flight.future;
      if (!attached) return;
      _clampOffset();
      _syncVisibleBindings();
      markNeedsPaint();
    } finally {
      _clearStitchCapture();
      if (_controller.isSectionJumpActive) {
        _controller.setSectionJumpActive(false);
      }
      _controller.completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.notifyScrollEvent(PanelCatalogSectionJumpEnd(sectionIndex));
      if (identical(_stitchFlightCompleter, flight)) {
        _stitchFlightCompleter = null;
      }
      if (_scrollLog.enabled) {
        _scrollLog.event('sectionJump.end', {
          'section': sectionIndex,
          'offset': DevLogFormat.f(_controller.offset),
          'path': 'far',
        });
      }
    }
  }

  /// Drops stitch capture state after settle or cancel.
  void _clearStitchCapture() {
    _stitchOutgoing = const [];
    _stitchPinnedKeys = const {};
  }

  /// After stitch teleport layout, measures travel and starts progress animation.
  ///
  /// Idempotent once [CatalogFarStitch.measured] is true. Also invoked
  /// synchronously from [_runFarStitch] so the first post-teleport paint can
  /// apply provisional incoming off-screen offsets without waiting another frame.
  void _beginStitchMeasureIfNeeded() {
    final farStitch = _farStitch;
    if (farStitch == null ||
        !farStitch.isActive ||
        !farStitch.jumped ||
        farStitch.measured) {
      return;
    }
    if (!hasSize) return;

    final (top, bottom) = _visibleWindow();
    final incomingVisible = [
      for (final slot in _slots)
        if (slot.bottom >= top && slot.top <= bottom) slot,
    ];
    final travel = measureCatalogStitchTravel(
      outgoing: _stitchOutgoing,
      incomingVisible: incomingVisible,
      towardNewer: farStitch.towardNewer,
      scrollOffset: _controller.offset,
      viewportHeight: size.height,
    );

    unawaited(
      farStitch
          .applyMeasure(scrollLength: travel, viewportHeight: size.height)
          .then((_) {
            if (!attached) return;
            _clearStitchCapture();
            _clampOffset();
            _syncVisibleBindings();
            markNeedsPaint();
            final completer = _stitchFlightCompleter;
            _stitchFlightCompleter = null;
            completer?.complete();
          }),
    );
  }

  /// Silently writes [PanelCatalogController.offset] into `[0, maxOffset]`.
  ///
  /// No-op before [hasSize] (cannot know viewport height). Uses
  /// [PanelCatalogController.correctOffset] so jump/scroll listeners are not
  /// re-entered during clamp.
  void _clampOffset() {
    if (!hasSize) return;
    final clamped = _controller.offset.clamp(0.0, maxOffset).toDouble();
    if (clamped == _controller.offset) return;
    _controller.correctOffset(clamped);
  }

  // --- Lifecycle ------------------------------------------------------------

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _dataSource.addDataListener(_onDataChanged);
    _bindController(_controller);
    _pressTickers = CatalogPressTickerProvider();
    _press = CatalogLeafPress(vsync: _pressTickers!, onChanged: markNeedsPaint);
    _nearScroll = CatalogNearScroll(
      vsync: _pressTickers!,
      onTick: () {
        _clampOffset();
        _syncVisibleBindings();
        markNeedsPaint();
      },
    );
    _farStitch = CatalogFarStitch(
      vsync: _pressTickers!,
      onTick: markNeedsPaint,
    );
    _drag = VerticalDragGestureRecognizer()
      ..onStart = _onDragStart
      ..onUpdate = _onDragUpdate
      ..onEnd = _onDragEnd;
    final pending = _controller.pendingSectionJump;
    if (pending != null) {
      _handleSectionJump(pending.$1);
    }
    final animatePending = _controller.pendingAnimateTo;
    if (animatePending != null) {
      _handleAnimateTo();
    }
    // Keep-alive pager leave/return reattaches without a constraint change —
    // force layout so [syncVisible] re-binds before the first paint.
    markNeedsLayout();
  }

  @override
  void detach() {
    _dataSource.removeDataListener(_onDataChanged);
    _unbindController(_controller);
    _clearPressPointerRoute();
    _cancelSectionJumpMotion();
    _cancelFling();
    _flingTicker = null;
    _nearScroll?.dispose();
    _nearScroll = null;
    _farStitch?.dispose();
    _farStitch = null;
    _clearStitchCapture();
    _stitchFlightCompleter = null;
    _flingCancelSuppressesLeaf = false;
    _flingCancelPointer = null;
    _drag?.dispose();
    _drag = null;
    _press?.dispose();
    _press = null;
    _pressTickers?.dispose();
    _pressTickers = null;
    // Drop every attach so cache refcounts fall when this viewport leaves
    // the tree — even if the same cache is shared with another surface.
    _pool.detachAll();
    super.detach();
  }

  @override
  void dispose() {
    _clearPressPointerRoute();
    _cancelSectionJumpMotion();
    _cancelFling();
    _flingTicker = null;
    _nearScroll?.dispose();
    _nearScroll = null;
    _farStitch?.dispose();
    _farStitch = null;
    _clearStitchCapture();
    _stitchFlightCompleter = null;
    _flingCancelSuppressesLeaf = false;
    _flingCancelPointer = null;
    _drag?.dispose();
    _drag = null;
    _leafPointer.dispose();
    _press?.dispose();
    _press = null;
    _pressTickers?.dispose();
    _pressTickers = null;
    _pool.detachAll();
    _painter.dispose();
    super.dispose();
  }

  // --- Layout projection ----------------------------------------------------

  /// Rebuilds [_slots] / [_contentExtent] from the current data + geometry.
  ///
  /// Pure projection + store; does not touch the asset cache. Binding sync
  /// runs separately after size/offset are known.
  void _project(double maxWidth) {
    final projection = projectCatalogSlots(
      sections: _dataSource.sections,
      spanCount: _spanCount,
      cellExtent: _cellExtent,
      headerExtent: _headerExtent,
      padding: _padding,
      maxWidth: maxWidth,
    );
    _slots = projection.slots;
    _contentExtent = projection.contentExtent;
  }

  /// Content-y window used for **binding** sync (viewport + one-cell overscan).
  ///
  /// When sized: `[offset − cellExtent, offset + height + cellExtent]`
  /// clamped to `[0, contentExtent]`. Before [hasSize], returns the full
  /// content band so a pre-layout sync (rare) does not attach nothing then
  /// thrash on first paint.
  ///
  /// Paint uses [_paintWindow] (no overscan) so scroll frames do not draw an
  /// extra fringe row that the user cannot see.
  (double, double) _visibleWindow() {
    if (!hasSize) {
      return (0, _contentExtent);
    }
    final overscan = _cellExtent;
    final pixels = _controller.offset;
    final top = (pixels - overscan).clamp(0.0, _contentExtent);
    final bottom = (pixels + size.height + overscan).clamp(0.0, _contentExtent);
    return (top, bottom);
  }

  /// Content-y window used for **paint** culling (strict viewport, no overscan).
  ///
  /// Binding overscan stays on [_visibleWindow]; drawing the fringe costs
  /// color-emoji paint/raster for cells that never appear on screen.
  (double, double) _paintWindow() {
    if (!hasSize) {
      return (0, _contentExtent);
    }
    final pixels = _controller.offset;
    final top = pixels.clamp(0.0, _contentExtent);
    final bottom = (pixels + size.height).clamp(0.0, _contentExtent);
    return (top, bottom);
  }

  /// First index in [_slots] whose `bottom >= [top]` (binary search).
  ///
  /// Slots are projected in ascending content-y order. Returns
  /// [_slots.length] when every slot ends above [top].
  int _firstSlotIndexAtOrBelow(double top) {
    final slots = _slots;
    var lo = 0;
    var hi = slots.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (slots[mid].bottom < top) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Exclusive end index in [_slots] for slots with `top <= [bottom]`.
  int _slotIndexAfter(double bottom) {
    final slots = _slots;
    var lo = 0;
    var hi = slots.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (slots[mid].top <= bottom) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Reconciles [CatalogLeafBindingPool] attaches to the current [_visibleWindow].
  void _syncVisibleBindings() {
    final (top, bottom) = _visibleWindow();
    _pool.syncVisible(
      slots: _slots,
      top: top,
      bottom: bottom,
      pinnedKeys: _stitchPinnedKeys.isEmpty ? null : _stitchPinnedKeys,
    );
  }

  // --- Scroll — drag --------------------------------------------------------

  /// Cancels fling and press before a new drag gesture owns the pointer.
  void _onDragStart(DragStartDetails details) {
    _cancelSectionJumpMotion();
    _cancelFling();
    _clearPressPointerRoute();
    _press?.pressOut();
    _controller.notifyScrollEvent(const PanelCatalogUserDragStart());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? details.delta.dy;
    // Drag up (negative dy) reveals content below → increase offset.
    _controller.scrollBy(-dy);
  }

  /// Starts a fling when release velocity exceeds the physics threshold.
  ///
  /// No-op when [maxOffset] is `0` (nothing to scroll) or velocity is below
  /// the minimum. Finger-up velocity is negated into content-offset space.
  void _onDragEnd(DragEndDetails details) {
    final fingerVelocity = details.primaryVelocity ?? 0;
    // Finger up (negative primaryVelocity) → positive content-offset velocity.
    final contentVelocity = -fingerVelocity;
    _controller.notifyScrollEvent(PanelCatalogUserDragEnd(contentVelocity));
    if (!hasSize || maxOffset <= 0) return;
    if (contentVelocity.abs() < 50) return;
    _controller.notifyScrollEvent(PanelCatalogFlingStart(contentVelocity));
    _startFling(contentVelocity);
  }

  // --- Scroll — fling -------------------------------------------------------

  /// Arms [_physics] and ensures the fling ticker is running.
  void _startFling(double contentVelocity) {
    _physics.startFling(contentVelocity);
    _ensureFlingTicker();
  }

  /// Stops simulation and ticker; safe when already idle.
  void _cancelFling() {
    final wasFlinging = _physics.isFlinging;
    _physics.cancelFling();
    _flingTicker?.stop();
    if (wasFlinging) {
      _controller.notifyScrollEvent(const PanelCatalogFlingEnd());
    }
  }

  /// Lazily creates and starts [_flingTicker] on [_pressTickers].
  ///
  /// No-op when detached (no ticker provider). Reuses the same ticker across
  /// successive flings while attached.
  void _ensureFlingTicker() {
    final tickers = _pressTickers;
    if (tickers == null) return;
    _flingTicker ??= tickers.createTicker(_onFlingTick);
    if (!(_flingTicker?.isActive ?? false)) {
      _flingTicker!.start();
    }
  }

  /// Applies one fling simulation step via [PanelCatalogController.scrollBy].
  ///
  /// Cancels when simulation ends, delta is zero, applied scroll is zero
  /// (wall hit), or offset reaches `[0, maxOffset]`.
  void _onFlingTick(Duration elapsed) {
    if (!_physics.isFlinging || !hasSize) {
      _cancelFling();
      return;
    }
    final delta = _physics.tickFling(elapsed);
    if (delta == 0) {
      if (!_physics.isFlinging) {
        _flingTicker?.stop();
        _controller.notifyScrollEvent(const PanelCatalogFlingEnd());
      }
      return;
    }
    final before = _controller.offset;
    final target = (before + delta).clamp(0.0, maxOffset);
    final applied = target - before;
    if (applied == 0) {
      _cancelFling();
      return;
    }
    _controller.scrollBy(applied);
    if (target <= 0 || target >= maxOffset) {
      _cancelFling();
    }
  }

  // --- Press feedback -------------------------------------------------------

  /// Long-press arena loss releases press scale without waiting for pointer-up.
  void _onLeafGestureCancel() {
    _press?.pressOut();
  }

  /// Starts press-scale and registers a pointer route for move-out cancel.
  ///
  /// Stores viewport-local cell rect from [slot]. No-op when [slot] is absent
  /// from the current [_slots] snapshot (should not happen for live hit-test).
  void _beginLeafPress(PointerDownEvent event, CatalogLeafSlot slot) {
    _pressPointer = event.pointer;
    _pressLeafOrigin = Offset(slot.left, slot.top - _controller.offset);
    _pressLeafSize = Size(slot.width, slot.height);
    _press?.pressIn(slot.key);
    GestureBinding.instance.pointerRouter.addRoute(
      event.pointer,
      _handlePressPointerRoute,
    );
  }

  /// Removes the press pointer route and clears tracked rect state.
  void _clearPressPointerRoute() {
    final pointer = _pressPointer;
    if (pointer != null) {
      GestureBinding.instance.pointerRouter.removeRoute(
        pointer,
        _handlePressPointerRoute,
      );
    }
    _pressPointer = null;
    _pressLeafOrigin = null;
    _pressLeafSize = null;
  }

  /// Releases press when the finger leaves the leaf rect or lifts/cancels.
  void _handlePressPointerRoute(PointerEvent event) {
    if (event.pointer != _pressPointer) return;
    switch (event) {
      case PointerMoveEvent():
        final origin = _pressLeafOrigin;
        final size = _pressLeafSize;
        if (origin == null || size == null) return;
        final local = globalToLocal(event.position);
        final rect = origin & size;
        if (!rect.contains(local)) {
          _clearPressPointerRoute();
          _press?.pressOut();
        }
      case PointerUpEvent() || PointerCancelEvent():
        _clearPressPointerRoute();
        _press?.pressOut();
      default:
        break;
    }
  }

  // --- RenderBox layout -----------------------------------------------------

  /// Preferred width: horizontal padding + [spanCount] × [cellExtent].
  ///
  /// Used when the parent passes unbounded width. Height argument is ignored
  /// — pitch is square and independent of constraint height.
  @override
  double computeMinIntrinsicWidth(double height) =>
      _padding.horizontal + _spanCount * _cellExtent;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      computeMinIntrinsicWidth(height);

  /// Viewport-sized body: intrinsic height is not [contentExtent].
  ///
  /// Returning content height here would make some parents expand to fit the
  /// whole catalog and defeat scrolling. Usable scroll requires a bounded
  /// height constraint from the parent.
  @override
  double computeMinIntrinsicHeight(double width) {
    return 0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  /// Projects slots, sizes to the viewport, clamps offset, syncs bindings.
  ///
  /// Unbounded width falls back to [computeMinIntrinsicWidth]. Unbounded
  /// height constrains against the last-known [_contentExtent] (may be `0`
  /// on the first pass before project).
  ///
  /// Records [debugLastLayoutDuration] each pass.
  @override
  void performLayout() {
    final sw = Stopwatch()..start();
    final maxWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : computeMinIntrinsicWidth(constraints.maxHeight);
    final maxHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : constraints.constrainHeight(_contentExtent);
    _project(maxWidth);
    size = constraints.constrain(Size(maxWidth, maxHeight));
    _clampOffset();
    _syncVisibleBindings();
    _beginStitchMeasureIfNeeded();
    debugLastLayoutDuration = sw.elapsed;
    _logLayoutEnd(constraints);
  }

  void _logLayoutEnd(BoxConstraints constraints) {
    if (!_layoutLog.enabled) return;
    final frame = _layoutLog.bumpLayoutFrame();
    final slotCount = _slots.length;
    final leafSlots = _slots.whereType<CatalogLeafSlot>().length;
    final changed =
        _layoutLogLastExtent != _contentExtent ||
        _layoutLogLastSlotCount != slotCount;
    _layoutLogLastExtent = _contentExtent;
    _layoutLogLastSlotCount = slotCount;
    if (!changed && frame > 1 && frame % 30 != 0) return;
    final (winTop, winBottom) = _visibleWindow();
    final usableW = (constraints.maxWidth - _padding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final cellW = usableW > 0 ? usableW / _spanCount : _cellExtent;
    _layoutLog.event('layout.end', {
      'frame': frame,
      'cw': DevLogFormat.f(constraints.maxWidth),
      'ch': DevLogFormat.f(constraints.maxHeight),
      'vw': DevLogFormat.f(size.width),
      'vh': DevLogFormat.f(size.height),
      'span': _spanCount,
      'cell': DevLogFormat.f(_cellExtent),
      'cellW': DevLogFormat.f(cellW),
      'header': DevLogFormat.f(_headerExtent),
      'padT': DevLogFormat.f(_padding.top),
      'padB': DevLogFormat.f(_padding.bottom),
      'padH': DevLogFormat.f(_padding.horizontal),
      'extent': DevLogFormat.f(_contentExtent),
      'maxOff': DevLogFormat.f(maxOffset),
      'offset': DevLogFormat.f(_controller.offset),
      'slots': slotCount,
      'leaves': leafSlots,
      'attached': _pool.attachedCount,
      'winTop': DevLogFormat.f(winTop),
      'winBot': DevLogFormat.f(winBottom),
      'sections': _dataSource.sections.length,
    });
  }

  // --- Hit-test and pointer routing -----------------------------------------

  /// The entire viewport is a hit target so drag / wheel / leaf gestures
  /// reach [handleEvent].
  @override
  bool hitTestSelf(Offset position) => size.contains(position);

  /// Routes pointer-down to drag, leaf press/pointer, and fling-cancel logic;
  /// wheel scroll cancels fling and scrolls by delta.
  ///
  /// Fling-cancel pointer-down suppresses [_beginLeafPress] and relies on
  /// [_flingCancelSuppressesLeaf] for [CatalogLeafPointer]. Post-frame clear
  /// on pointer-up preserves suppress through arena tap resolution.
  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    assert(debugHandleEvent(event, entry));
    switch (event) {
      case PointerDownEvent():
        var suppressLeafActions = false;
        if (_physics.isFlinging) {
          _cancelFling();
          _flingCancelSuppressesLeaf = true;
          _flingCancelPointer = event.pointer;
          suppressLeafActions = true;
        } else if (_flingCancelPointer == null && _flingCancelSuppressesLeaf) {
          // Stale suppress from a prior fling-cancel tap whose post-frame
          // clear has not run yet.
          _flingCancelSuppressesLeaf = false;
        }
        _drag?.addPointer(event);
        final slot = leafSlotAt(event.localPosition);
        if (slot != null) {
          // Fling-cancel taps stop the coast only — no press chrome / pick.
          if (!suppressLeafActions) {
            _beginLeafPress(event, slot);
          }
          _leafPointer.addPointer(event);
        }
      case PointerUpEvent() || PointerCancelEvent():
        if (_flingCancelPointer == event.pointer) {
          _flingCancelPointer = null;
          // Tap onTap fires after pointer up; defer clear so the arena still
          // sees suppress when the tap resolves.
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (attached) {
              _flingCancelSuppressesLeaf = false;
            }
          });
        }
      case PointerScrollEvent(:final scrollDelta):
        _cancelFling();
        _controller.scrollBy(scrollDelta.dy);
      default:
        break;
    }
  }

  // --- Paint ----------------------------------------------------------------

  /// Clips to the viewport, translates by `−offset`, paints intersecting slots.
  ///
  /// During far-path stitch, paints captured outgoing strip and incoming band
  /// with dual-translate dy instead of the normal single-pass loop.
  ///
  /// Paint culling uses [_paintWindow] (strict viewport). Binding sync keeps
  /// [_visibleWindow] overscan so cells entering the band are already attached;
  /// overscan fringe is not drawn.
  ///
  /// The cell under [pressedSlotKey] is drawn with [CatalogLeafPress.scale].
  ///
  /// Records [debugLastPaintDuration] each pass.
  @override
  void paint(PaintingContext context, Offset offset) {
    final sw = Stopwatch()..start();
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);

    final scroll = _controller.offset;
    final contentOrigin = offset.translate(0, -scroll);
    final (top, bottom) = _paintWindow();
    final pressedSlotKey = _press?.pressedSlotKey;
    final pressScale = _press?.scale ?? 1.0;
    final pressProgress = _press?.progress ?? 0.0;

    final farStitch = _farStitch;
    switch (farStitch) {
      case final stitch? when stitch.isActive && stitch.jumped:
        _paintStitchFlight(
          canvas: canvas,
          viewportOrigin: offset,
          contentOrigin: contentOrigin,
          visibleTop: top,
          visibleBottom: bottom,
          farStitch: stitch,
          pressedSlotKey: pressedSlotKey,
          pressScale: pressScale,
          pressProgress: pressProgress,
        );
        canvas.restore();
        debugLastPaintDuration = sw.elapsed;
        return;
      default:
        break;
    }

    final slots = _slots;
    final start = _firstSlotIndexAtOrBelow(top);
    final end = _slotIndexAfter(bottom);
    for (var i = start; i < end; i++) {
      final slot = slots[i];
      if (slot.bottom < top || slot.top > bottom) continue;
      _paintLayoutSlot(
        canvas: canvas,
        origin: contentOrigin,
        slot: slot,
        pressedSlotKey: pressedSlotKey,
        pressScale: pressScale,
        pressProgress: pressProgress,
      );
    }

    _logPaintSummary(top, bottom);

    canvas.restore();
    debugLastPaintDuration = sw.elapsed;
  }

  void _logPaintSummary(double visibleTop, double visibleBottom) {
    if (!_paintLog.enabled) return;
    final frame = _paintLog.bumpPaintFrame();
    if (frame % 15 != 0) return;
    var content = 0;
    var circle = 0;
    var thumb = 0;
    var failed = 0;
    for (final slot in _slots) {
      if (slot is! CatalogLeafSlot) continue;
      if (slot.bottom < visibleTop || slot.top > visibleBottom) continue;
      switch (_pool.presentationFor(slot.leaf)) {
        case CatalogLeafPresentation.content:
          content++;
        case CatalogLeafPresentation.circlePlaceholder:
          circle++;
        case CatalogLeafPresentation.thumbFirstPlaceholder:
        case CatalogLeafPresentation.shapedLoadingWash:
          thumb++;
        case CatalogLeafPresentation.failed:
          failed++;
      }
    }
    _paintLog.event('paint.summary', {
      'frame': frame,
      'offset': DevLogFormat.f(_controller.offset),
      'content': content,
      'circle': circle,
      'thumb': thumb,
      'failed': failed,
      'attached': _pool.attachedCount,
    });
  }

  /// Paints one projected [CatalogLayoutSlot] at [origin] (content coordinates).
  void _paintLayoutSlot({
    required Canvas canvas,
    required Offset origin,
    required CatalogLayoutSlot slot,
    required CatalogLeafSlotKey? pressedSlotKey,
    required double pressScale,
    required double pressProgress,
  }) {
    switch (slot) {
      case final CatalogHeaderSlot header:
        _painter.paintHeader(
          canvas: canvas,
          origin: origin,
          header: header,
          contentWidth: size.width,
          padding: _padding,
        );
      case final CatalogLeafSlot leaf:
        final isPressed = pressedSlotKey != null && leaf.key == pressedSlotKey;
        _painter.paintLeaf(
          canvas: canvas,
          origin: origin,
          slot: leaf,
          presentation: _pool.presentationFor(leaf.leaf),
          pressScale: isPressed ? pressScale : 1.0,
          pressProgress: isPressed ? pressProgress : 0,
        );
    }
  }

  /// Dual-translate paint for an in-flight far-path stitch.
  ///
  /// Outgoing capture paints in **viewport** space (`viewportOrigin + dy`).
  /// Incoming visible slots paint in **content** space (`contentOrigin + dy`).
  /// Before [CatalogFarStitch.measured], incoming uses [provisionalTravel]
  /// fully off-screen; outgoing uses the same travel with progress `0`.
  void _paintStitchFlight({
    required Canvas canvas,
    required Offset viewportOrigin,
    required Offset contentOrigin,
    required double visibleTop,
    required double visibleBottom,
    required CatalogFarStitch farStitch,
    required CatalogLeafSlotKey? pressedSlotKey,
    required double pressScale,
    required double pressProgress,
  }) {
    final towardNewer = farStitch.towardNewer;
    final measured = farStitch.measured;
    final travel = farStitch.scrollLength;
    final progress = farStitch.progress;
    final provisionalTravel = size.height;

    for (final captured in _stitchOutgoing) {
      final dy = catalogStitchOutgoingPaintDy(
        towardNewer: towardNewer,
        travel: measured ? travel : provisionalTravel,
        progress: measured ? progress : 0,
      );
      final bandOrigin = viewportOrigin.translate(0, captured.viewportTop + dy);
      switch (captured) {
        case CatalogStitchCapturedHeader(:final title, :final height):
          _paintLayoutSlot(
            canvas: canvas,
            origin: bandOrigin,
            slot: CatalogHeaderSlot(top: 0, height: height, title: title),
            pressedSlotKey: pressedSlotKey,
            pressScale: pressScale,
            pressProgress: pressProgress,
          );
        case CatalogStitchCapturedLeaf(
          :final left,
          :final width,
          :final height,
          :final leaf,
        ):
          _paintLayoutSlot(
            canvas: canvas,
            origin: bandOrigin,
            slot: CatalogLeafSlot(
              top: 0,
              height: height,
              left: left,
              width: width,
              leaf: leaf,
            ),
            pressedSlotKey: pressedSlotKey,
            pressScale: pressScale,
            pressProgress: pressProgress,
          );
      }
    }

    final slots = _slots;
    final start = _firstSlotIndexAtOrBelow(visibleTop);
    final end = _slotIndexAfter(visibleBottom);
    for (var i = start; i < end; i++) {
      final slot = slots[i];
      if (slot.bottom < visibleTop || slot.top > visibleBottom) continue;
      if (catalogStitchSlotIsOutgoing(slot, _stitchOutgoing)) continue;
      final dy = catalogStitchIncomingPaintDy(
        towardNewer: towardNewer,
        travel: travel,
        progress: progress,
        measured: measured,
        provisionalTravel: provisionalTravel,
      );
      _paintLayoutSlot(
        canvas: canvas,
        origin: contentOrigin.translate(0, dy),
        slot: slot,
        pressedSlotKey: pressedSlotKey,
        pressScale: pressScale,
        pressProgress: pressProgress,
      );
    }
  }

  // --- Debug ----------------------------------------------------------------

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('contentExtent', contentExtent))
      ..add(DoubleProperty('offset', _controller.offset))
      ..add(DoubleProperty('maxOffset', hasSize ? maxOffset : null))
      ..add(IntProperty('attachedLeaves', attachedLeafCount))
      ..add(FlagProperty('isFlinging', value: isFlinging, ifTrue: 'flinging'))
      ..add(
        FlagProperty(
          'isFarStitchActive',
          value: isFarStitchActive,
          ifTrue: 'stitch',
        ),
      );
  }
}
