import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/src/data/catalog_data_source.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_leaf_presentation.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_binding_pool.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_painter.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_pointer.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_press.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_physics.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_controller.dart';

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
/// Geometry changes (span, pitch, padding, data notify) call
/// [markCatalogNeedsUpdate] so the next layout reprojects slots.
///
/// ## Binding recycle
///
/// [CatalogLeafBindingPool] attaches [CatalogAssetCache] bindings only for
/// leaf slots intersecting the visible window (viewport band plus one
/// [cellExtent] of overscan above and below). Leaves that leave that band
/// are detached. Readiness changes on attached bindings mark paint dirty so
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
/// ## Fling physics
///
/// Drag-end with sufficient velocity starts a ballistic fling
/// ([CatalogScrollPhysics] / [ClampingScrollSimulation]) in content offset
/// space. Each tick applies [PanelCatalogController.scrollBy] until the
/// simulation ends or offset hits `[0, maxOffset]`. Fling cancels on drag
/// start, wheel, [jumpTo], scroll wall, or pointer-down while flinging.
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
/// registers tap / long-press only for leaf downs; drag always receives the
/// pointer so scroll still wins the arena when the finger moves. Press scale
/// starts on leaf-down via [CatalogLeafPress] and is painted into the leaf
/// (`0.8 + 0.2 * (1 − progress)`). Drag start and long-press cancel call
/// press-out. Pointer move that leaves the pressed leaf rect also releases.
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
    required CatalogAssetCacheType cacheType,
    required Color placeholderColor,
    ValueChanged<CatalogLeaf>? onLeafTap,
    void Function(CatalogLeaf leaf, LongPressStartDetails details)?
    onLeafLongPressStart,
    void Function(CatalogLeaf leaf, LongPressMoveUpdateDetails details)?
    onLeafLongPressMove,
    void Function(CatalogLeaf leaf, LongPressEndDetails details)?
    onLeafLongPressEnd,
  }) : _dataSource = dataSource,
       _controller = controller,
       _spanCount = spanCount,
       _cellExtent = cellExtent,
       _headerExtent = headerExtent,
       _padding = padding,
       _onLeafTap = onLeafTap,
       _onLeafLongPressStart = onLeafLongPressStart,
       _onLeafLongPressMove = onLeafLongPressMove,
       _onLeafLongPressEnd = onLeafLongPressEnd,
       _painter = CatalogLeafPainter(placeholderColor: placeholderColor) {
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

  /// Attach size class for leaf bindings. Replacing detaches then reprojects.
  set cacheType(CatalogAssetCacheType value) {
    _pool.replaceCacheType(value);
    markCatalogNeedsUpdate();
  }

  /// Fill for circle / related stand-in placeholders. Paint-only — no layout.
  set placeholderColor(Color value) {
    _painter.placeholderColor = value;
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

  // --- Runtime state --------------------------------------------------------

  late CatalogLeafBindingPool _pool;
  final CatalogLeafPainter _painter;
  late final CatalogLeafPointer _leafPointer;

  /// Ballistic scroll simulation and tick integration in content offset space.
  final CatalogScrollPhysics _physics = CatalogScrollPhysics();

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
  /// Unbound-but-projected leaves still return a loading placeholder from the
  /// pool (not `null`). `null` means the key is absent from the current
  /// projection entirely.
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

  /// Whether a ballistic fling is currently driving [PanelCatalogController.offset].
  bool get isFlinging => _physics.isFlinging;

  /// Leaf currently receiving press-scale feedback, or `null` when idle.
  ///
  /// Test / debug seam for paint press — not a second write model for
  /// shell pick state.
  CatalogLeaf? get pressedLeaf => _press?.pressedLeaf;

  /// Press amount for [pressedLeaf]: `0` idle … `1` fully pressed; may be
  /// slightly negative during overshoot release.
  double get pressProgress => _press?.progress ?? 0;

  /// Resolves the [CatalogLeaf] under [localPosition], or `null` when the
  /// point lies on a header, padding, or empty band.
  ///
  /// [localPosition] is viewport-local (post-hit-test). Content y adds the
  /// current scroll [PanelCatalogController.offset]. Requires [hasSize] and
  /// a prior project — returns `null` before the first layout.
  CatalogLeaf? leafAt(Offset localPosition) {
    if (!hasSize) return null;
    final contentX = localPosition.dx;
    final contentY = localPosition.dy + _controller.offset;
    for (final slot in _slots) {
      if (slot case final CatalogLeafSlot leaf) {
        if (contentX >= leaf.left &&
            contentX < leaf.left + leaf.width &&
            contentY >= leaf.top &&
            contentY < leaf.bottom) {
          return leaf.leaf;
        }
      }
    }
    return null;
  }

  /// Content-space slot for [leaf] from the last project, or `null` when
  /// absent from the current [_slots] snapshot.
  CatalogLeafSlot? _slotOf(CatalogLeaf leaf) {
    for (final slot in _slots) {
      if (slot case final CatalogLeafSlot candidate
          when candidate.leaf.assetKey == leaf.assetKey) {
        return candidate;
      }
    }
    return null;
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

  void _onDataChanged() => markCatalogNeedsUpdate();

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
      ..addScrollByListener(_onScrollBy);
  }

  void _unbindController(PanelCatalogController controller) {
    controller
      ..removeJumpListener(_onJump)
      ..removeScrollByListener(_onScrollBy);
  }

  /// Cancels fling then runs the navigation path (clamp + bind + paint).
  void _onJump(double pixels) {
    _cancelFling();
    _onNavigation();
  }

  void _onScrollBy(double delta) => _onNavigation();

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
    _drag = VerticalDragGestureRecognizer()
      ..onStart = _onDragStart
      ..onUpdate = _onDragUpdate
      ..onEnd = _onDragEnd
      ..dragStartBehavior = DragStartBehavior.down;
  }

  @override
  void detach() {
    _dataSource.removeDataListener(_onDataChanged);
    _unbindController(_controller);
    _clearPressPointerRoute();
    _cancelFling();
    _flingTicker = null;
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
    _cancelFling();
    _flingTicker = null;
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

  /// Content-y window used for binding sync and paint culling.
  ///
  /// When sized: `[offset − cellExtent, offset + height + cellExtent]`
  /// clamped to `[0, contentExtent]`. Before [hasSize], returns the full
  /// content band so a pre-layout sync (rare) does not attach nothing then
  /// thrash on first paint.
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

  /// Reconciles [CatalogLeafBindingPool] attaches to the current [_visibleWindow].
  void _syncVisibleBindings() {
    final (top, bottom) = _visibleWindow();
    _pool.syncVisible(slots: _slots, top: top, bottom: bottom);
  }

  // --- Scroll — drag --------------------------------------------------------

  /// Cancels fling and press before a new drag gesture owns the pointer.
  void _onDragStart(DragStartDetails details) {
    _cancelFling();
    _clearPressPointerRoute();
    _press?.pressOut();
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
    if (!hasSize || maxOffset <= 0) return;
    final fingerVelocity = details.primaryVelocity ?? 0;
    // Finger up (negative primaryVelocity) → positive content-offset velocity.
    final contentVelocity = -fingerVelocity;
    if (contentVelocity.abs() < 50) return;
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
    _physics.cancelFling();
    _flingTicker?.stop();
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
      if (!_physics.isFlinging) _flingTicker?.stop();
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
  /// Stores viewport-local leaf rect derived from the projected slot. No-op
  /// when [leaf] is absent from the current [_slots] snapshot.
  void _beginLeafPress(PointerDownEvent event, CatalogLeaf leaf) {
    final slot = _slotOf(leaf);
    if (slot == null) return;
    _pressPointer = event.pointer;
    _pressLeafOrigin = Offset(slot.left, slot.top - _controller.offset);
    _pressLeafSize = Size(slot.width, slot.height);
    _press?.pressIn(leaf);
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
  @override
  void performLayout() {
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
        final leaf = leafAt(event.localPosition);
        if (leaf != null) {
          // Fling-cancel taps stop the coast only — no press chrome / pick.
          if (!suppressLeafActions) {
            _beginLeafPress(event, leaf);
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
  /// Paint culling uses the same visible window as binding sync (including
  /// overscan). A slot may be bound but still skipped here if it sits only
  /// in the overscan fringe and the cull band is evaluated equivalently —
  /// both use [_visibleWindow], so bound ⇒ eligible to paint.
  ///
  /// The leaf under [pressedLeaf] is drawn with [CatalogLeafPress.scale].
  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);

    final scroll = _controller.offset;
    // Shift content so content-y `scroll` aligns with viewport top.
    final contentOrigin = offset.translate(0, -scroll);
    final (top, bottom) = _visibleWindow();
    final pressed = _press?.pressedLeaf;
    final pressScale = _press?.scale ?? 1.0;

    for (final slot in _slots) {
      if (slot.bottom < top || slot.top > bottom) continue;
      switch (slot) {
        case final CatalogHeaderSlot header:
          _painter.paintHeader(
            canvas: canvas,
            origin: contentOrigin,
            header: header,
            contentWidth: size.width,
            padding: _padding,
          );
        case final CatalogLeafSlot leaf:
          final scale = switch (pressed) {
            final p? when leaf.leaf.assetKey == p.assetKey => pressScale,
            _ => 1.0,
          };
          _painter.paintLeaf(
            canvas: canvas,
            origin: contentOrigin,
            slot: leaf,
            presentation: _pool.presentationFor(leaf.leaf),
            pressScale: scale,
          );
      }
    }

    canvas.restore();
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
      ..add(FlagProperty('isFlinging', value: isFlinging, ifTrue: 'flinging'));
  }
}
