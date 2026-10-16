import 'dart:async' show Completer, Future, unawaited;
import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show
        MouseTrackerAnnotation,
        PointerEnterEventListener,
        PointerExitEventListener;
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/src/data/catalog_snapshot.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';
import 'package:panel_catalog/src/util/constants.dart';
import 'package:panel_catalog/src/util/logger.dart';
import 'package:panel_catalog/src/viewport/catalog_action_pointer.dart';
import 'package:panel_catalog/src/viewport/catalog_bake_activity.dart';
import 'package:panel_catalog/src/viewport/catalog_far_stitch.dart';
import 'package:panel_catalog/src/viewport/catalog_focus.dart';
import 'package:panel_catalog/src/viewport/catalog_focus_navigation.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_binding_pool.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_painter.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_pointer.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_press.dart';
import 'package:panel_catalog/src/viewport/catalog_near_scroll.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_physics.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_position.dart';
import 'package:panel_catalog/src/viewport/catalog_section_navigation.dart';
import 'package:panel_catalog/src/viewport/catalog_section_proximity.dart';
import 'package:panel_catalog/src/viewport/catalog_semantics.dart';
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
/// asset fetch/decode (the host's [AssetCacheScope] does), or catalog fetch
/// (the owner of the snapshot observable does). Hosts wire those; this object
/// only listens and projects.
///
/// ## Layout model
///
/// Catalog geometry is a known content height ([contentExtent]), not an
/// id-relative anchor. [projectCatalogSlots] flattens
/// [CatalogSnapshot.sections] into absolute header/leaf slots in content
/// coordinates (y increases downward from the catalog top), each section by
/// its own [CatalogSection.layout] resolved against the viewport defaults.
/// The slots of all sections stay in one ascending list, so the lookups below
/// are one binary search whatever mix of layouts the catalog holds. Scroll
/// range is:
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
/// Leaves paint what their asset binding has reached and never decode
/// anything. Geometry changes (span, pitch, padding, data notify) call
/// [markCatalogNeedsUpdate] so the next layout reprojects slots.
///
/// ## Binding recycle
///
/// [CatalogLeafBindingPool] attaches [AssetCacheScope] bindings only for
/// leaf slots intersecting the visible window (viewport band plus one
/// [cellExtent] of overscan above and below). Leaves that leave that band
/// are detached unless their key is listed in the stitch pin set during
/// far-path flight ([CatalogFarStitch]) so outgoing strip bindings survive
/// the teleport. A better stage on an attached binding marks paint dirty so
/// placeholders flip to content without a full catalog reproject.
///
/// The visible window is resolved to a slot index range by binary search over
/// the ascending projection, in both binding sync and paint, so scroll-time
/// cost follows the visible band rather than the catalogue size.
///
/// Overscan is intentionally one cell row: enough that a short drag does not
/// thrash attach/detach every frame, not a second viewport of prefetched
/// bindings. Empty / short catalogs still project headers; unbound leaves
/// paint the placeholder their descriptor facts name.
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
/// near scroll or stitch. Motion writes publish [PanelCatalogOffsetChanged]
/// only, never a jump or scroll-by event; [PanelCatalogController.isSectionJumpActive]
/// gates host strip sync for both paths.
///
/// A pointer-down that cancels an in-flight fling suppresses leaf tap /
/// long-press for that pointer so stopping the coast does not insert a leaf.
/// Press scale is also skipped for that pointer; suppress clears post-frame
/// after pointer-up so arena tap resolution still sees the flag.
///
/// After every navigation, this object clamps the offset silently (no event).
/// Until that correction runs, [pixels] MAY briefly sit outside
/// `[0, maxOffset]` (e.g. jump past the end before layout knows
/// [contentExtent]).
///
/// ## Hit-test and press
///
/// The entire viewport is the hit target ([hitTestSelf]). On pointer-down,
/// [leafAt] maps viewport-local coordinates through scroll offset into a
/// [CatalogLeafHit] (or `null` on headers / padding). [CatalogLeafPointer]
/// registers tap / long-press for leaf downs when wired;
/// [CatalogLeafPointer.leafLongPressEligible] skips the long-press recognizer
/// on ineligible leaves. Drag always receives the pointer so scroll still wins
/// the arena when the finger moves. Press scale starts on leaf-down via
/// [CatalogLeafPress], keyed by [CatalogLeafSlotKey] (content position), not
/// the leaf's content key, so duplicate glyphs in different sections animate
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
/// ## Baked glyphs
///
/// Where the scope's glyphs are baked, each unicode leaf resolves to a sprite
/// through its binding and the painter queues it; one pass draws the sprites of
/// each atlas page in a single batched draw ([CatalogLeafPainter.endPass], at
/// the end of [paint]). An unbaked glyph is the circle placeholder and flips to
/// its sprite when the atlas page lands (the binding listener marks paint
/// dirty, never layout). Where the scope draws glyphs as text the leaf's
/// paintable paints itself; this object cannot tell the two apart.
/// [CatalogBakeActivity] publishes whether the catalogue is moving and what is
/// on screen as scroll events; whoever owns the bake listens to them, so the
/// bake stays out of the way of motion.
///
/// ## Lifecycle
///
/// - [attach]: register the snapshot listener and become the controller's
///   position; create drag, leaf pointer, press tickers, and press controller.
/// - [detach]: leave the controller (it keeps the offset reached) and
///   unregister listeners; dispose recognizers / press / fling;
///   [CatalogLeafBindingPool.detachAll].
/// - [dispose]: same binding/painter teardown; safe if already detached.
///
/// Listeners are only live while attached. Swapping [snapshots] /
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
/// ## Repaint boundary
///
/// [isRepaintBoundary] is `true`: paint runs against a layer of its own with
/// the viewport at the origin. Scroll / press / readiness `markNeedsPaint`
/// stops at this object instead of dirtying the host chrome's layer.
///
/// Constructed by [PanelCatalogViewport]; not exported from the public barrel.
class RenderPanelCatalog extends RenderBox
    implements
        CatalogScrollPosition,
        CatalogSemanticsTarget,
        MouseTrackerAnnotation {
  /// Creates a panel catalog render body.
  ///
  /// [spanCount] MUST be ≥ 1. [cellExtent] / [headerExtent] SHOULD be > 0;
  /// zero collapses rows/headers to empty bands but does not assert.
  /// Negative [padding] is undefined.
  ///
  /// Leaf callbacks are forwarded to [CatalogLeafPointer] while attached;
  /// null long-press start disables the long-press recognizer.
  RenderPanelCatalog({
    required listen.ValueListenable<CatalogSnapshot> snapshots,
    required AssetCacheScope assets,
    required double devicePixelRatio,
    required PanelCatalogController controller,
    required int spanCount,
    required double cellExtent,
    required double headerExtent,
    required EdgeInsets padding,
    required CatalogLeafPaintTheme paintTheme,
    TextDirection textDirection = TextDirection.ltr,
    double? headerLandingInset,
    ValueChanged<CatalogLeafHit>? onLeafTap,
    void Function(CatalogLeafHit hit, Offset globalPosition)?
    onLeafSecondaryTap,
    void Function(CatalogLeafHit hit, LongPressStartDetails details)?
    onLeafLongPressStart,
    void Function(CatalogLeafHit hit, LongPressMoveUpdateDetails details)?
    onLeafLongPressMove,
    void Function(CatalogLeafHit hit, LongPressEndDetails details)?
    onLeafLongPressEnd,
    bool Function(CatalogLeafHit hit)? leafLongPressEligible,
    Duration? Function(CatalogLeafHit hit, PointerDeviceKind kind)?
    leafLongPressDelay,
    CatalogLeafHit? pinnedLeaf,
    void Function(String sectionId, String actionId)? onSectionAction,
    double? sectionNearExtent,
  }) : _snapshots = snapshots,
       _controller = controller,
       _pixels = controller.offset,
       _spanCount = spanCount,
       _cellExtent = cellExtent,
       _headerExtent = headerExtent,
       _padding = padding,
       _textDirection = textDirection,
       _headerLandingInset = headerLandingInset,
       _onLeafTap = onLeafTap,
       _onLeafSecondaryTap = onLeafSecondaryTap,
       _pinnedLeaf = pinnedLeaf,
       _onLeafLongPressStart = onLeafLongPressStart,
       _onLeafLongPressMove = onLeafLongPressMove,
       _onLeafLongPressEnd = onLeafLongPressEnd,
       _leafLongPressEligible = leafLongPressEligible,
       _onSectionAction = onSectionAction,
       _sectionNearExtent = sectionNearExtent,
       _paintTheme = paintTheme,
       _devicePixelRatio = devicePixelRatio,
       _painter = CatalogLeafPainter(theme: paintTheme) {
    _assets = assets;
    _pool = CatalogLeafBindingPool(
      scope: assets,
      devicePixelRatio: devicePixelRatio,
      onChanged: markNeedsPaint,
    );
    _leafPointer = CatalogLeafPointer(debugOwner: this)
      ..leafAt = leafAt
      ..onLeafTap = onLeafTap
      ..onLeafSecondaryTap = onLeafSecondaryTap
      ..onLeafLongPressStart = onLeafLongPressStart
      ..onLeafLongPressMove = onLeafLongPressMove
      ..onLeafLongPressEnd = onLeafLongPressEnd
      ..leafLongPressEligible = leafLongPressEligible
      ..leafLongPressDelay = leafLongPressDelay
      ..onGestureCancel = _onLeafGestureCancel
      ..flingCancelSuppresses = () => _flingCancelSuppressesLeaf;
    _actionPointer = CatalogActionPointer(debugOwner: this)
      ..actionAt = actionAt
      ..onSectionAction = onSectionAction
      ..flingCancelSuppresses = () => _flingCancelSuppressesLeaf;
  }

  // --- Configuration --------------------------------------------------------

  /// Authoritative catalog contents. Reprojected when the snapshot
  /// [listen.ValueListenable] signals while attached.
  ///
  /// Swapping while attached moves the listener to the new source and marks
  /// layout+paint dirty. The previous source is unsubscribed first.
  listen.ValueListenable<CatalogSnapshot> _snapshots;
  set snapshots(listen.ValueListenable<CatalogSnapshot> value) {
    if (_snapshots == value) return;
    if (attached) {
      _snapshots.removeListener(_onDataChanged);
    }
    _snapshots = value;
    if (attached) {
      _snapshots.addListener(_onDataChanged);
    }
    _validateFocus();
    markCatalogNeedsUpdate();
  }

  /// Command and event hub. While attached this render object is the
  /// controller's one [CatalogScrollPosition]: the controller forwards host
  /// commands to it and it publishes scroll events through the controller.
  ///
  /// Swapping while attached detaches from the old controller (which keeps
  /// the offset reached), adopts the new controller's offset, reclamps, and
  /// re-syncs the visible band.
  PanelCatalogController _controller;
  set controller(PanelCatalogController value) {
    if (_controller == value) return;
    if (attached) {
      _stopBakeActivity();
      _controller.detach(this);
    }
    _controller = value;
    if (attached) {
      _pixels = value.offset;
      value.attach(this);
      _startBakeActivity();
    }
    _clampOffset();
    _syncVisibleBindings();
    markNeedsPaint();
  }

  /// The host's asset cache. Replacing it detaches every binding first
  /// ([CatalogLeafBindingPool.replaceScope]) then reprojects; the same scope on
  /// a widget update changes nothing, so a drag or a bake in progress is not
  /// disturbed.
  late AssetCacheScope _assets;
  set assets(AssetCacheScope value) {
    if (identical(_assets, value)) return;
    _assets = value;
    _pool.replaceScope(value);
    markCatalogNeedsUpdate();
  }

  /// Density of the view this body sits in. Bindings are asked for pixels at
  /// it, so a change swaps every attached binding for one at the new size.
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    _pool.devicePixelRatio = value;
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

  /// The direction of a section whose layout states none. Changing it moves
  /// the cells of those sections to the other side of their rows and mirrors
  /// their headers; rows and offsets stay.
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markCatalogNeedsUpdate();
  }

  /// Section-jump landing inset; null → [padding.top].
  double? _headerLandingInset;
  set headerLandingInset(double? value) {
    if (_headerLandingInset == value) return;
    _headerLandingInset = value;
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
  ValueChanged<CatalogLeafHit>? _onLeafTap;
  set onLeafTap(ValueChanged<CatalogLeafHit>? value) {
    if (_onLeafTap == value) return;
    // A node offers an action by whether the shell has one; the action itself
    // reads the callback when performed.
    if ((_onLeafTap == null) != (value == null)) _markSemanticsStale();
    _onLeafTap = value;
    _leafPointer.onLeafTap = value;
  }

  /// Shell secondary tap (mouse right click). Null leaves the button
  /// unrecognised.
  void Function(CatalogLeafHit hit, Offset globalPosition)? _onLeafSecondaryTap;
  set onLeafSecondaryTap(
    void Function(CatalogLeafHit hit, Offset globalPosition)? value,
  ) {
    if (_onLeafSecondaryTap == value) return;
    _onLeafSecondaryTap = value;
    _leafPointer.onLeafSecondaryTap = value;
  }

  /// Per-cell, per-pointer-kind long-press delay. Null = the platform's.
  set leafLongPressDelay(
    Duration? Function(CatalogLeafHit hit, PointerDeviceKind kind)? value,
  ) => _leafPointer.leafLongPressDelay = value;

  /// The cell a transient surface is open over: its hover wash stays and the
  /// wheel is ignored until it is released.
  CatalogLeafHit? _pinnedLeaf;
  set pinnedLeaf(CatalogLeafHit? value) {
    if (_pinnedLeaf == value) return;
    _pinnedLeaf = value;
    markNeedsPaint();
  }

  /// Shell long-press start. Null disables the long-press recognizer.
  void Function(CatalogLeafHit hit, LongPressStartDetails details)?
  _onLeafLongPressStart;
  set onLeafLongPressStart(
    void Function(CatalogLeafHit hit, LongPressStartDetails details)? value,
  ) {
    if (_onLeafLongPressStart == value) return;
    if ((_onLeafLongPressStart == null) != (value == null)) {
      _markSemanticsStale();
    }
    _onLeafLongPressStart = value;
    _leafPointer.onLeafLongPressStart = value;
  }

  /// Shell long-press move. Ignored when start is null.
  void Function(CatalogLeafHit hit, LongPressMoveUpdateDetails details)?
  _onLeafLongPressMove;
  set onLeafLongPressMove(
    void Function(CatalogLeafHit hit, LongPressMoveUpdateDetails details)?
    value,
  ) {
    if (_onLeafLongPressMove == value) return;
    _onLeafLongPressMove = value;
    _leafPointer.onLeafLongPressMove = value;
  }

  /// Shell long-press end. Ignored when start is null.
  void Function(CatalogLeafHit hit, LongPressEndDetails details)?
  _onLeafLongPressEnd;
  set onLeafLongPressEnd(
    void Function(CatalogLeafHit hit, LongPressEndDetails details)? value,
  ) {
    if (_onLeafLongPressEnd == value) return;
    _onLeafLongPressEnd = value;
    _leafPointer.onLeafLongPressEnd = value;
  }

  /// Per-leaf long-press registration gate. Null = all leaves eligible.
  bool Function(CatalogLeafHit hit)? _leafLongPressEligible;
  set leafLongPressEligible(bool Function(CatalogLeafHit hit)? value) {
    if (_leafLongPressEligible == value) return;
    if ((_leafLongPressEligible == null) != (value == null)) {
      _markSemanticsStale();
    }
    _leafLongPressEligible = value;
    _leafPointer.leafLongPressEligible = value;
  }

  /// Shell reaction to a tapped header action. Null disables recognition.
  void Function(String sectionId, String actionId)? _onSectionAction;
  set onSectionAction(void Function(String sectionId, String actionId)? value) {
    if (_onSectionAction == value) return;
    if ((_onSectionAction == null) != (value == null)) {
      _markSemanticsStale();
    }
    _onSectionAction = value;
    _actionPointer.onSectionAction = value;
  }

  /// Distance beyond the viewport at which a section edge is near; null is
  /// one viewport height.
  double? _sectionNearExtent;
  set sectionNearExtent(double? value) {
    if (_sectionNearExtent == value) return;
    _sectionNearExtent = value;
    _proximity.invalidate();
    _scheduleSectionProximity();
  }

  // --- Runtime state --------------------------------------------------------

  late CatalogLeafBindingPool _pool;
  final CatalogLeafPainter _painter;

  /// Derives scrolling / settled events from the motion events; null while
  /// detached.
  CatalogBakeActivity? _bakeActivity;

  /// Frame time of the paint pass, from the scheduler unless a test fixes it.
  Duration Function() _frameTime = _schedulerFrameTime;
  // The raw timestamp rather than `currentFrameTimeStamp`, which is null
  // outside a frame: a paint inside a frame reads the same value, and a paint
  // driven by hand (a golden, a test) still has a time.
  static Duration _schedulerFrameTime() =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp;

  /// Fixes the frame time the placeholders' motion and the content fade read,
  /// so a test or a golden paints at a chosen instant. Null restores the
  /// scheduler's.
  @visibleForTesting
  set debugFrameTime(Duration Function()? value) =>
      _frameTime = value ?? _schedulerFrameTime;

  /// Whether a frame request for placeholder motion or a fade is pending.
  var _motionFrameRequested = false;

  /// Absolute content offset. This render object owns it while attached; the
  /// controller keeps the committed value while no viewport is attached.
  double _pixels;

  /// Whether a section jump owns scroll motion (see
  /// [PanelCatalogController.isSectionJumpActive]).
  var _sectionJumpActive = false;

  /// The [jumpToSection] request in flight and its future.
  (int sectionIndex, Completer<void> completer)? _pendingSectionJump;

  /// The [animateTo] request in flight and its future. Cleared when the
  /// motion ends, is superseded, or is cancelled.
  (double target, Duration duration, Curve curve, Completer<void> completer)?
  _pendingAnimateTo;
  late final CatalogLeafPointer _leafPointer;
  late final CatalogActionPointer _actionPointer;

  /// Which section edges are near the viewport.
  final CatalogSectionProximity _proximity = CatalogSectionProximity();

  /// The sections and bands of the last projection, aligned.
  List<CatalogSection> _projectedSections = const [];
  List<CatalogSectionBand> _bands = const [];
  double _projectedWidth = -1;
  var _proximityScheduled = false;

  /// The section last published as current, by index and id.
  (int, String)? _currentSection;

  /// Ballistic scroll simulation and tick integration in content offset space.
  final CatalogScrollPhysics _physics = CatalogScrollPhysics();

  /// Near-path section jump animation; null after [detach] / [dispose].
  CatalogNearScroll? _nearScroll;

  /// Far-path stitch animation; null after [detach] / [dispose].
  CatalogFarStitch? _farStitch;

  /// Outgoing strip captured before stitch teleport (viewport-local geometry).
  List<CatalogStitchCapturedSlot> _stitchOutgoing = const [];

  /// Outgoing leaf bindings pinned for the stitch flight.
  Set<ContentKey> _stitchPinnedKeys = const {};

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

  /// Whether a drag started and has not ended, so its end can be told apart
  /// from the cancel the recognizer reports for a tap.
  var _userDragging = false;

  // --- Diagnostics (filter DevTools / logcat by logger name) ----------------

  int _layoutFrame = 0;
  int _paintFrame = 0;

  double? _layoutLogLastExtent;
  int? _layoutLogLastSlotCount;

  // --- Observability --------------------------------------------------------

  @override
  double get pixels => _pixels;

  @override
  double get viewportExtent => hasSize ? size.height : 0;

  /// Total catalog content height after the last project (padding included).
  ///
  /// `0` before the first layout. Short catalogs may be smaller than
  /// [size].height — then [maxOffset] is `0` and scroll input is a no-op after
  /// clamp.
  @override
  double get contentExtent => _contentExtent;

  @override
  double get maxScrollExtent => hasSize ? maxOffset : 0;

  @override
  bool get isSectionJumpActive => _sectionJumpActive;

  /// Maximum scroll offset for the current viewport height.
  ///
  /// Requires [hasSize]; callers MUST NOT read this before the first layout.
  /// Equals `max(0, contentExtent − size.height)`.
  double get maxOffset => math.max(0, _contentExtent - size.height);

  /// Flat leaves in projection order (headers omitted).
  ///
  /// Reflects the last project — empty before layout, or when every section
  /// has no leaves.
  List<CatalogLeaf> get projectedLeaves => [
    for (final slot in _slots)
      if (slot case final CatalogLeafSlot leaf) leaf.leaf,
  ];

  /// Count of bindings currently attached in the scope's cache.
  ///
  /// Bounded by the visible window + overscan, not by total catalog size.
  int get attachedLeafCount => _pool.attachedCount;

  /// Test seam: drops every pool binding without disposing this render object.
  ///
  /// Models pager keep-alive leave (`detachAll` while the page [State] and
  /// the scope survive).
  @visibleForTesting
  void debugDetachBindings() => _pool.detachAll();

  /// Whether a ballistic fling is currently driving [PanelCatalogController.offset].
  bool get isFlinging => _physics.isFlinging;

  /// Cell currently receiving press-scale feedback, or `null` when idle.
  ///
  /// Test / debug seam for paint press — keyed by content slot, not by the
  /// leaf's content key, so duplicate glyphs animate independently.
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

  /// Resolves the [CatalogLeafHit] under [localPosition], or `null` when the
  /// point lies on a header, padding, or empty band.
  ///
  /// [localPosition] is viewport-local (post-hit-test). Content y adds the
  /// current scroll [PanelCatalogController.offset]. Requires [hasSize] and
  /// a prior project — returns `null` before the first layout.
  CatalogLeafHit? leafAt(Offset localPosition) =>
      leafSlotAt(localPosition)?.hit;

  /// Resolves the leaf [CatalogLeafSlot] under [localPosition], or `null`.
  ///
  /// Used for press feedback and pointer routing so a leaf shown in several
  /// cells stays one independent cell per hit. Binary search to the row under
  /// the point, then a scan of that row: the cost follows the row, not the
  /// catalogue, whatever layouts its sections use.
  CatalogLeafSlot? leafSlotAt(Offset localPosition) {
    if (!hasSize) return null;
    final contentX = localPosition.dx;
    final contentY = localPosition.dy + _pixels;
    final slots = _slots;
    for (var i = _firstSlotIndexAtOrBelow(contentY); i < slots.length; i++) {
      final slot = slots[i];
      if (slot.top > contentY) break;
      if (slot case final CatalogLeafSlot leaf) {
        if (contentX >= leaf.left &&
            contentX < leaf.left + leaf.width &&
            contentY < leaf.bottom) {
          return leaf;
        }
      }
    }
    return null;
  }

  /// Resolves the header action under [localPosition] as `(sectionId,
  /// actionId)`, or `null` when the point is on no action's hit area.
  ///
  /// Binary search to the slots at the point's content y, then a scan of the
  /// few that share it: the cost follows the row, not the catalogue.
  (String sectionId, String actionId)? actionAt(Offset localPosition) {
    if (!hasSize) return null;
    final contentX = localPosition.dx;
    final contentY = localPosition.dy + _pixels;
    final slots = _slots;
    for (var i = _firstSlotIndexAtOrBelow(contentY); i < slots.length; i++) {
      final slot = slots[i];
      if (slot.top > contentY) break;
      if (slot case final CatalogHeaderSlot header when header.action != null) {
        final bounds = _painter.sectionActionBounds(header);
        if (bounds != null && bounds.contains(Offset(contentX, contentY))) {
          return (header.sectionId, header.action!.id);
        }
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

  void _onDataChanged() {
    if (LogCategory.layout.enabled) {
      fine(.layout, 'data.notify', {
        'sections': _snapshots.value.sections.length,
        'leaves': _snapshots.value.sections.fold<int>(
          0,
          (n, s) => n + s.leaves.length,
        ),
      });
    }
    _validateFocus();
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
    _noteSections();
  }

  /// Moves to [pixels] at once: publishes the jump, cancels programmatic
  /// motion and any fling, then clamps, recycles bindings and paints.
  @override
  void jumpTo(double pixels) {
    if (_pixels == pixels) return;
    final delta = pixels - _pixels;
    _pixels = pixels;
    _controller
      ..publish(PanelCatalogProgrammaticJump(pixels))
      ..publish(PanelCatalogOffsetChanged(pixels, delta));
    _cancelSectionJumpMotion();
    _cancelFling();
    _onNavigation();
    if (LogCategory.scroll.enabled) {
      fine(.scroll, 'jump', {'offset': LogFormat.f(_pixels)});
    }
  }

  /// Moves by [delta]: publishes the scroll, cancels programmatic motion, then
  /// clamps, recycles bindings and paints. Drag, fling ticks and the wheel
  /// take this path.
  @override
  void scrollBy(double delta) {
    if (delta == 0) return;
    _pixels += delta;
    _controller
      ..publish(PanelCatalogViewportScrolled(delta))
      ..publish(PanelCatalogOffsetChanged(_pixels, delta));
    _cancelSectionJumpMotion();
    _onNavigation();
    if (LogCategory.scroll.enabled) {
      fine(.scroll, 'scrollBy', {
        'delta': LogFormat.f(delta),
        'offset': LogFormat.f(_pixels),
      });
    }
  }

  /// Writes [target] and publishes [PanelCatalogOffsetChanged]; used by the
  /// motion that owns the offset (animate, near section ticks, stitch
  /// teleports). Does not cancel anything and is not a jump.
  void _applyOffset(double target) {
    if (_pixels == target) return;
    final delta = target - _pixels;
    _pixels = target;
    _controller.publish(PanelCatalogOffsetChanged(target, delta));
  }

  @override
  Future<void> animateTo(
    double pixels, {
    required Duration duration,
    required Curve curve,
  }) {
    if ((_pixels - pixels).abs() < 0.5) return Future.value();
    _completePendingAnimateTo();
    final completer = Completer<void>();
    _pendingAnimateTo = (pixels, duration, curve, completer);
    unawaited(_handleAnimateTo());
    return completer.future;
  }

  @override
  Future<void> jumpToSection(int sectionIndex) {
    if (_sectionJumpActive) {
      return _pendingSectionJump?.$2.future ?? Future.value();
    }
    // A request that never started (no size yet) is superseded, not leaked.
    _completePendingSectionJump();
    final completer = Completer<void>();
    _pendingSectionJump = (sectionIndex, completer);
    unawaited(_handleSectionJump(sectionIndex));
    return completer.future;
  }

  /// Completes the pending animate future, if any.
  void _completePendingAnimateTo() {
    final pending = _pendingAnimateTo;
    if (pending == null) return;
    _pendingAnimateTo = null;
    if (!pending.$4.isCompleted) pending.$4.complete();
  }

  /// Completes the pending section-jump future when [sectionIndex] matches
  /// the pending request (or any pending request when it is null).
  void _completePendingSectionJump({int? sectionIndex}) {
    final pending = _pendingSectionJump;
    if (pending == null) return;
    if (sectionIndex != null && pending.$1 != sectionIndex) return;
    _pendingSectionJump = null;
    if (!pending.$2.isCompleted) pending.$2.complete();
  }

  /// Runs a host-requested [PanelCatalogController.animateTo].
  Future<void> _handleAnimateTo() async {
    final pending = _pendingAnimateTo;
    if (pending == null) return;
    final (target, duration, curve, completer) = pending;

    if (!attached) {
      _completePendingAnimateTo();
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
      if (!attached || _pendingAnimateTo == null) return;
    }

    _cancelSectionJumpMotion();
    _cancelFling();

    if ((_pixels - target).abs() < 1) {
      _applyOffset(target);
      _onNavigation();
      _completePendingAnimateTo();
      return;
    }

    final nearScroll = _nearScroll;
    if (nearScroll == null || !hasSize) {
      jumpTo(target);
      _onNavigation();
      _clampOffset();
      _completePendingAnimateTo();
      return;
    }

    markNeedsLayout();
    _controller.publish(PanelCatalogAnimateStart(target, duration));
    try {
      final from = _pixels;
      await nearScroll.animate(
        from: from,
        to: target,
        duration: duration,
        curve: curve,
        applyOffset: _applyOffset,
      );
      _clampOffset();
      _syncVisibleBindings();
      markNeedsPaint();
    } finally {
      _controller.publish(PanelCatalogAnimateEnd(_pixels));
      _completePendingAnimateTo();
    }
  }

  // --- Section jump (near-path animate; far-path stitch) --------------------

  /// Path-selects near smooth scroll vs far stitch, then completes the pending
  /// [PanelCatalogController.jumpToSection] future.
  Future<void> _handleSectionJump(int sectionIndex) async {
    final sections = _snapshots.value.sections;
    if (sectionIndex < 0 || sectionIndex >= sections.length) {
      _sectionJumpActive = false;
      _completePendingSectionJump(sectionIndex: sectionIndex);
      return;
    }
    if (!hasSize) {
      // Requested before the first layout (a jump committed while unbound
      // lands here): apply it once the frame that lays this object out is
      // done, unless it was retargeted or cancelled meanwhile.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_pendingSectionJump?.$1 != sectionIndex) return;
        if (attached && hasSize) {
          unawaited(_handleSectionJump(sectionIndex));
        } else {
          _completePendingSectionJump(sectionIndex: sectionIndex);
        }
      });
      return;
    }

    _cancelFling();
    _cancelSectionJumpMotion();

    // From the live sections, not the last projection: a snapshot published
    // since the last layout is the catalog the jump is about.
    final bands = projectCatalogSectionBands(
      sections: sections,
      spanCount: _spanCount,
      cellExtent: _cellExtent,
      headerExtent: _headerExtent,
      padding: _padding,
      maxWidth: size.width,
      textDirection: _textDirection,
    ).bands;
    final targetOffset = scrollOffsetForBand(
      bands[sectionIndex],
      landingInset: _headerLandingInset ?? _padding.top,
    ).clamp(0.0, maxOffset);

    if ((targetOffset - _pixels).abs() < 1) {
      _applyOffset(targetOffset);
      _onNavigation();
      _sectionJumpActive = false;
      _completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.publish(PanelCatalogSectionJumpEnd(sectionIndex));
      return;
    }

    final near = isNearPathSectionJump(
      targetSectionIndex: sectionIndex,
      bands: bands,
      scrollOffset: _pixels,
      viewportHeight: size.height,
    );

    if (LogCategory.scroll.enabled) {
      fine(.scroll, 'sectionJump.begin', {
        'section': sectionIndex,
        'from': LogFormat.f(_pixels),
        'to': LogFormat.f(targetOffset),
        'near': near,
        'sectionId': sections[sectionIndex].id,
      });
    }

    _sectionJumpActive = true;

    if (!near) {
      await _runFarStitch(
        sectionIndex: sectionIndex,
        targetOffset: targetOffset,
      );
      return;
    }

    _controller.publish(
      PanelCatalogSectionJumpStart(sectionIndex, targetOffset, farPath: false),
    );

    final nearScroll = _nearScroll;
    if (nearScroll == null) {
      jumpTo(targetOffset);
      _onNavigation();
      _sectionJumpActive = false;
      _completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.publish(PanelCatalogSectionJumpEnd(sectionIndex));
      return;
    }

    try {
      final from = _pixels;
      await nearScroll.animate(
        from: from,
        to: targetOffset,
        applyOffset: _applyOffset,
      );
      _clampOffset();
      _syncVisibleBindings();
      markNeedsPaint();
    } finally {
      _sectionJumpActive = false;
      _completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.publish(PanelCatalogSectionJumpEnd(sectionIndex));
      if (LogCategory.scroll.enabled) {
        fine(.scroll, 'sectionJump.end', {
          'section': sectionIndex,
          'offset': LogFormat.f(_pixels),
          'path': 'near',
        });
      }
    }
  }

  void _cancelNearScroll({int? forSectionIndex}) {
    final wasActive = _nearScroll?.isActive ?? false;
    _nearScroll?.cancel();
    if (!wasActive) return;
    if (_pendingAnimateTo != null) {
      _completePendingAnimateTo();
      return;
    }
    _sectionJumpActive = false;
    _completePendingSectionJump(sectionIndex: forSectionIndex);
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
      _sectionJumpActive = false;
      _completePendingSectionJump(sectionIndex: forSectionIndex);
    }
  }

  /// Cancels near-path scroll and far-path stitch programmatic motion.
  void _cancelSectionJumpMotion({int? forSectionIndex}) {
    _cancelNearScroll(forSectionIndex: forSectionIndex);
    _cancelFarStitch(forSectionIndex: forSectionIndex);
    _completePendingAnimateTo();
  }

  /// Runs far-path stitch: capture → teleport → measure → dual-translate.
  ///
  /// When [_farStitch] is null (detached tickers), falls back to a plain
  /// offset write and navigation. When the outgoing capture
  /// is empty, still runs an incoming-only stitch flight (destination band
  /// slides in from off-screen) rather than showing the teleported catalog
  /// at rest for one frame.
  Future<void> _runFarStitch({
    required int sectionIndex,
    required double targetOffset,
  }) async {
    final farStitch = _farStitch;
    if (farStitch == null) {
      _applyOffset(targetOffset);
      _clampOffset();
      _onNavigation();
      _controller.publish(
        PanelCatalogSectionJumpStart(sectionIndex, targetOffset, farPath: true),
      );
      _sectionJumpActive = false;
      _completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.publish(PanelCatalogSectionJumpEnd(sectionIndex));
      return;
    }

    final fromOffset = _pixels;
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
    _applyOffset(targetOffset);
    _clampOffset();
    _syncVisibleBindings();
    _noteSections();
    _controller.publish(
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
      if (_sectionJumpActive) {
        _sectionJumpActive = false;
      }
      _completePendingSectionJump(sectionIndex: sectionIndex);
      _controller.publish(PanelCatalogSectionJumpEnd(sectionIndex));
      if (identical(_stitchFlightCompleter, flight)) {
        _stitchFlightCompleter = null;
      }
      if (LogCategory.scroll.enabled) {
        fine(.scroll, 'sectionJump.end', {
          'section': sectionIndex,
          'offset': LogFormat.f(_pixels),
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
      scrollOffset: _pixels,
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

  /// Silently writes [pixels] into `[0, maxOffset]`.
  ///
  /// No-op before [hasSize] (cannot know viewport height). Publishes no event,
  /// so listeners are not re-entered during clamp.
  void _clampOffset() {
    if (!hasSize) return;
    final clamped = _pixels.clamp(0.0, maxOffset).toDouble();
    if (clamped == _pixels) return;
    _pixels = clamped;
  }

  // --- Lifecycle ------------------------------------------------------------

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _snapshots.addListener(_onDataChanged);
    _pressTickers = CatalogPressTickerProvider();
    _press = CatalogLeafPress(vsync: _pressTickers!, onChanged: markNeedsPaint);
    _nearScroll = CatalogNearScroll(
      vsync: _pressTickers!,
      onTick: () {
        _clampOffset();
        _syncVisibleBindings();
        markNeedsPaint();
        _noteSections();
      },
    );
    _farStitch = CatalogFarStitch(
      vsync: _pressTickers!,
      onTick: markNeedsPaint,
    );
    _drag = VerticalDragGestureRecognizer()
      ..onStart = _onDragStart
      ..onUpdate = _onDragUpdate
      ..onEnd = _onDragEnd
      ..onCancel = _onDragCancel;
    _startBakeActivity();
    // Start from the offset the controller committed, then become its one
    // position. A section jump committed while unbound is handed over here.
    _pixels = _controller.offset;
    _controller.attach(this);
    // Keep-alive pager leave/return reattaches without a constraint change —
    // force layout so [syncVisible] re-binds before the first paint.
    markNeedsLayout();
  }

  @override
  void detach() {
    _snapshots.removeListener(_onDataChanged);
    _controller.detach(this);
    _setFocus(null);
    _clearPressPointerRoute();
    _cancelSectionJumpMotion();
    _endSectionJump();
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
    _userDragging = false;
    _stopBakeActivity();
    // Back in a tree the same edges are near again and are announced again.
    _proximity.reset();
    _currentSection = null;
    _projectedWidth = -1;
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
    _endSectionJump();
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
    _userDragging = false;
    _leafPointer.dispose();
    _actionPointer.dispose();
    _stopBakeActivity();
    _press?.dispose();
    _press = null;
    _pressTickers?.dispose();
    _pressTickers = null;
    _pool.detachAll();
    _painter.dispose();
    super.dispose();
  }

  // --- Scroll activity ------------------------------------------------------

  /// Ends any section-jump state that detach or dispose interrupted.
  void _endSectionJump() {
    _sectionJumpActive = false;
    _completePendingSectionJump();
  }

  void _startBakeActivity() {
    if (!attached || _bakeActivity != null) return;
    _bakeActivity = CatalogBakeActivity(
      events: _controller.events,
      publish: _controller.publish,
      isAnimating: () =>
          _physics.isFlinging || isSectionJumpAnimating || isFarStitchActive,
      visibleKeys: _visibleLeafKeys,
    );
  }

  void _stopBakeActivity() {
    // Publishes "not moving" before it goes.
    _bakeActivity?.dispose();
    _bakeActivity = null;
  }

  /// Keys of the leaves in the paint window, top first: what a settled
  /// listener should prioritise. Walks the visible band only.
  List<ContentKey> _visibleLeafKeys() {
    final (top, bottom) = _paintWindow();
    final start = _firstSlotIndexAtOrBelow(top);
    final end = _slotIndexAfter(bottom);
    final keys = <ContentKey>[];
    for (var i = start; i < end; i++) {
      final slot = _slots[i];
      if (slot.bottom < top || slot.top > bottom) continue;
      if (slot case CatalogLeafSlot(:final leaf)) {
        keys.add(leaf.key);
      }
    }
    return keys;
  }

  // --- Layout projection ----------------------------------------------------

  /// Rebuilds [_slots] / [_contentExtent] from the current data + geometry.
  ///
  /// Pure projection + store; does not touch the asset cache. Binding sync
  /// runs separately after size/offset are known.
  void _project(double maxWidth) {
    final projection = projectCatalogSlots(
      sections: _snapshots.value.sections,
      spanCount: _spanCount,
      cellExtent: _cellExtent,
      headerExtent: _headerExtent,
      padding: _padding,
      maxWidth: maxWidth,
      textDirection: _textDirection,
    );
    final sections = _snapshots.value.sections;
    // A relayout that changes neither the sections nor the geometry (a forced
    // layout, a parent's pass) has nothing new to announce.
    final changed = !identical(sections, _projectedSections);
    final moved =
        changed ||
        projection.contentExtent != _contentExtent ||
        maxWidth != _projectedWidth;
    _slots = projection.slots;
    _contentExtent = projection.contentExtent;
    _projectedSections = sections;
    _projectedWidth = maxWidth;
    _bands = projection.bands;
    if (changed) _proximity.invalidate();
    if (moved) _scheduleSectionProximity();
    _bakeActivity?.visibleBandChanged();
  }

  // --- Section proximity ------------------------------------------------------

  /// Evaluates proximity after this frame: a layout must not publish events,
  /// because a listener that answers with a snapshot would mark this object for
  /// layout while it is laying out and the request would be lost.
  void _scheduleSectionProximity() {
    if (_proximityScheduled) return;
    _proximityScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback(_runScheduledProximity);
  }

  void _runScheduledProximity(Duration _) {
    _proximityScheduled = false;
    _noteSections();
  }

  /// What the viewport tells the page about its sections after a change of
  /// offset or layout: which edges are near, and which section it is in.
  void _noteSections() {
    _noteSectionProximity();
    _noteCurrentSection();
  }

  /// Publishes [PanelCatalogCurrentSectionChanged] when the section the
  /// viewport is in, or its index, is not the one last published.
  ///
  /// Like proximity it waits for the first layout, and it is only ever called
  /// outside layout (a post-frame callback or an offset write).
  void _noteCurrentSection() {
    if (!attached || !hasSize) return;
    final index = currentSectionIndex(
      _bands,
      offset: _pixels,
      landingInset: _headerLandingInset ?? _padding.top,
      viewportHeight: size.height,
      maxScrollExtent: math.max(0, _contentExtent - size.height),
    );
    if (index == null) {
      _currentSection = null;
      _controller.clearCurrentSection();
      return;
    }
    final id = _projectedSections[index].id;
    final current = _currentSection;
    if (current != null && current.$1 == index && current.$2 == id) return;
    _currentSection = (index, id);
    _controller.publish(PanelCatalogCurrentSectionChanged(index, id));
  }

  /// Publishes [PanelCatalogSectionNearViewport] for the edges that entered the
  /// window around the viewport since the last call.
  ///
  /// Cheap when no edge moved ([CatalogSectionProximity.update]). Does nothing
  /// until the first layout has sized the viewport and projected the sections.
  void _noteSectionProximity() {
    if (!attached || !hasSize) return;
    final extent = _sectionNearExtent ?? size.height;
    _proximity.update(
      bands: _bands,
      sections: _projectedSections,
      windowTop: _pixels - extent,
      windowBottom: _pixels + size.height + extent,
      onNear: (sectionId, edge) =>
          _controller.publish(PanelCatalogSectionNearViewport(sectionId, edge)),
    );
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
    final pixels = _pixels;
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
    final pixels = _pixels;
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
    // Binary-searched band, not a walk over every slot: scroll-time sync cost
    // follows the visible window, not the catalogue size.
    final (paintTop, paintBottom) = _paintWindow();
    _pool.syncVisible(
      slots: _slots,
      start: _firstSlotIndexAtOrBelow(top),
      end: _slotIndexAfter(bottom),
      paintTop: paintTop,
      paintBottom: paintBottom,
      animate: !_physics.isFlinging,
      top: top,
      bottom: bottom,
      pinnedKeys: _stitchPinnedKeys.isEmpty ? null : _stitchPinnedKeys,
    );
  }

  // --- Scroll — drag --------------------------------------------------------

  /// Cancels fling and press before a new drag gesture owns the pointer.
  void _onDragStart(DragStartDetails details) {
    _userDragging = true;
    _cancelSectionJumpMotion();
    _cancelFling();
    _clearPressPointerRoute();
    _press?.pressOut();
    _controller.publish(const PanelCatalogUserDragStart());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? details.delta.dy;
    // Drag up (negative dy) reveals content below → increase offset.
    scrollBy(-dy);
  }

  /// Starts a fling when release velocity exceeds the physics threshold.
  ///
  /// No-op when [maxOffset] is `0` (nothing to scroll) or velocity is below
  /// the minimum. Finger-up velocity is negated into content-offset space.
  void _onDragEnd(DragEndDetails details) {
    _userDragging = false;
    final fingerVelocity = details.primaryVelocity ?? 0;
    // Finger up (negative primaryVelocity) → positive content-offset velocity.
    final contentVelocity = -fingerVelocity;
    _controller.publish(PanelCatalogUserDragEnd(contentVelocity));
    if (!hasSize || maxOffset <= 0) return;
    if (contentVelocity.abs() < 50) return;
    _controller.publish(PanelCatalogFlingStart(contentVelocity));
    _startFling(contentVelocity);
  }

  /// A drag that began and ended without a release. The recognizer also
  /// cancels for every tap that never became a drag; those are not events.
  void _onDragCancel() {
    if (!_userDragging) return;
    _userDragging = false;
    _controller.publish(const PanelCatalogUserDragCancel());
  }

  // --- Scroll — fling -------------------------------------------------------

  /// Arms [_physics] and ensures the fling ticker is running.
  void _startFling(double contentVelocity) {
    _physics.startFling(contentVelocity);
    _ensureFlingTicker();
    // Animated leaves stop playing while the coast runs.
    _syncVisibleBindings();
  }

  /// Stops simulation and ticker; safe when already idle.
  void _cancelFling() {
    final wasFlinging = _physics.isFlinging;
    _physics.cancelFling();
    _flingTicker?.stop();
    if (wasFlinging) {
      _syncVisibleBindings();
      _controller.publish(const PanelCatalogFlingEnd());
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
        _syncVisibleBindings();
        _controller.publish(const PanelCatalogFlingEnd());
      }
      return;
    }
    final before = _pixels;
    final target = (before + delta).clamp(0.0, maxOffset);
    final applied = target - before;
    if (applied == 0) {
      _cancelFling();
      return;
    }
    scrollBy(applied);
    if (target <= 0 || target >= maxOffset) {
      _cancelFling();
    }
  }

  // --- Hover ----------------------------------------------------------------

  /// Where the mouse is over the viewport (viewport-local), or null when it is
  /// not. Only a mouse hovers: a stylus or finger in contact is a press.
  Offset? _hoverPosition;

  /// The cell the hover wash was last painted on, so a mouse move asks for a
  /// repaint only when it changed cell.
  CatalogLeafSlotKey? _hoveredKey;

  // The cell is found again at every paint, not remembered: a wheel step or a
  // fling moves the content under a mouse that never moves, and the wash must
  // follow the cell that arrives under it.
  CatalogLeafSlotKey? _hoverSlotKey() {
    final position = _hoverPosition;
    if (position == null || _paintTheme.leafHoverHighlightColor == null) {
      return null;
    }
    return leafSlotAt(position)?.key;
  }

  bool _isHovered(CatalogLeafSlot leaf) {
    if (_paintTheme.leafHoverHighlightColor == null) return false;
    if (_pinnedLeaf case final pinned?) {
      return pinned.sectionId == leaf.sectionId && pinned.index == leaf.index;
    }
    return _hoveredKey != null && leaf.key == _hoveredKey;
  }

  void _hoverAt(Offset? position) {
    if (_hoverPosition == position) return;
    _hoverPosition = position;
    // A pinned cell holds the wash wherever the mouse goes.
    if (_pinnedLeaf == null && _hoverSlotKey() != _hoveredKey) markNeedsPaint();
  }

  // A mouse that was already there when the viewport appeared (or came back
  // under it) sends no hover until it moves; entering carries its position.
  void _handleHoverEnter(PointerEnterEvent event) => _hoverAt(
    event.kind == PointerDeviceKind.mouse ? event.localPosition : null,
  );

  void _handleHoverExit(PointerExitEvent event) => _hoverAt(null);

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
    _pressLeafOrigin = Offset(slot.left, slot.top - _pixels);
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

  /// Preferred width: horizontal padding + the default [spanCount] ×
  /// [cellExtent] (sections with a layout of their own divide the width they
  /// are given).
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
  double computeMinIntrinsicHeight(double width) => 0;

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
    _markSemanticsStale();
    debugLastLayoutDuration = sw.elapsed;
    _logLayoutEnd(constraints);
  }

  void _logLayoutEnd(BoxConstraints constraints) {
    if (!LogCategory.layout.enabled) return;
    final frame = ++_layoutFrame;
    final slotCount = _slots.length;
    final leafSlots = _slots.whereType<CatalogLeafSlot>().length;
    final changed =
        _layoutLogLastExtent != _contentExtent ||
        _layoutLogLastSlotCount != slotCount;
    _layoutLogLastExtent = _contentExtent;
    _layoutLogLastSlotCount = slotCount;
    if (!changed && frame > 1 && frame % 30 != 0) return;
    final (winTop, winBottom) = _visibleWindow();
    fine(.layout, 'layout.end', {
      'frame': frame,
      'cw': LogFormat.f(constraints.maxWidth),
      'ch': LogFormat.f(constraints.maxHeight),
      'vw': LogFormat.f(size.width),
      'vh': LogFormat.f(size.height),
      'span': _spanCount,
      'cell': LogFormat.f(_cellExtent),
      'header': LogFormat.f(_headerExtent),
      'padT': LogFormat.f(_padding.top),
      'padB': LogFormat.f(_padding.bottom),
      'padH': LogFormat.f(_padding.horizontal),
      'extent': LogFormat.f(_contentExtent),
      'maxOff': LogFormat.f(maxOffset),
      'offset': LogFormat.f(_pixels),
      'slots': slotCount,
      'leaves': leafSlots,
      'attached': _pool.attachedCount,
      'winTop': LogFormat.f(winTop),
      'winBot': LogFormat.f(winBottom),
      'sections': _snapshots.value.sections.length,
    });
  }

  // --- Hit-test and pointer routing -----------------------------------------

  /// The entire viewport is a hit target so drag / wheel / leaf gestures
  /// reach [handleEvent].
  @override
  bool hitTestSelf(Offset position) => size.contains(position);

  /// Where the last hit test landed, for [cursor]. The mouse tracker hit-tests
  /// the pointer before it reads the cursor of what it found, on every pointer
  /// event and again after each frame, so this is where the mouse is when the
  /// cursor is asked for.
  Offset? _hitPosition;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    _hitPosition = position;
    return super.hitTest(result, position: position);
  }

  /// The click cursor over a leaf the shell can tap or long-press and over a
  /// header action it listens to; the cursor of whatever is behind everywhere
  /// else.
  @override
  MouseCursor get cursor {
    final position = _hitPosition;
    if (position == null || !hasSize) return MouseCursor.defer;
    if ((_onLeafTap != null || _onLeafLongPressStart != null) &&
        leafSlotAt(position) != null) {
      return SystemMouseCursors.click;
    }
    if (_onSectionAction != null && actionAt(position) != null) {
      return SystemMouseCursors.click;
    }
    return MouseCursor.defer;
  }

  @override
  PointerEnterEventListener? get onEnter => _handleHoverEnter;

  @override
  PointerExitEventListener? get onExit => _handleHoverExit;

  @override
  bool get validForMouseTracker => attached;

  /// Routes pointer-down to drag, leaf press/pointer, and fling-cancel logic;
  /// wheel scroll cancels fling and scrolls by delta.
  ///
  /// Fling-cancel pointer-down suppresses [_beginLeafPress] and relies on
  /// [_flingCancelSuppressesLeaf] for [CatalogLeafPointer]. Post-frame clear
  /// on pointer-up preserves suppress through arena tap resolution.
  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    assert(
      debugHandleEvent(event, entry),
      'debugHandleEvent always answers true',
    );
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
          // Only the primary button presses a cell: a right click is the
          // host's menu, not a press, and animating it would read as one.
          if (!suppressLeafActions && event.buttons & kPrimaryButton != 0) {
            _beginLeafPress(event, slot);
          }
          _leafPointer.addPointer(event);
        } else {
          _actionPointer.addPointer(event);
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
        if (_pinnedLeaf != null) return;
        _cancelFling();
        scrollBy(scrollDelta.dy);
      case PointerHoverEvent(
        kind: PointerDeviceKind.mouse,
        :final localPosition,
      ):
        _hoverAt(localPosition);
      default:
        break;
    }
  }

  // --- Paint ----------------------------------------------------------------

  /// The viewport owns its own compositing layer.
  ///
  /// Hosts stack the category strip and search field over this body. Without a
  /// boundary an overlay repaint (typing, strip highlight) re-records every
  /// visible leaf, and every scroll frame re-records the overlays. With one,
  /// each side repaints into its own layer and the other is reused as is.
  @override
  bool get isRepaintBoundary => true;

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

    final scroll = _pixels;
    if (_semanticsPixels != scroll) {
      _semanticsPixels = scroll;
      markNeedsSemanticsUpdate();
    }
    _bakeActivity?.notePaint();
    _painter.beginPass(
      frameTime: _frameTime(),
      viewport: offset & size,
      animateWash: !_assets.clock.isPaused,
    );
    final contentOrigin = offset.translate(0, -scroll);
    final (top, bottom) = _paintWindow();
    final pressedSlotKey = _press?.pressedSlotKey;
    _hoveredKey = _hoverSlotKey();
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
        _endPaintPass(canvas);
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

    _endPaintPass(canvas);
    _logPaintSummary(top, bottom);

    canvas.restore();
    debugLastPaintDuration = sw.elapsed;
  }

  /// Draws what the pass queued and, when something painted moves with time (a
  /// fade, a wash), asks for the next frame after this one.
  ///
  /// The request is one post-frame callback at most; a viewport that paints no
  /// motion asks for none, so an idle catalogue keeps the engine asleep.
  void _endPaintPass(Canvas canvas) {
    final needsFrame = _painter.endPass(canvas);
    if (!needsFrame || _motionFrameRequested) return;
    _motionFrameRequested = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _motionFrameRequested = false;
      if (attached) markNeedsPaint();
    });
  }

  void _logPaintSummary(double visibleTop, double visibleBottom) {
    if (!LogCategory.paint.enabled) return;
    final frame = ++_paintFrame;
    if (frame % 15 != 0) return;
    var leaves = 0;
    var bound = 0;
    for (final slot in _slots) {
      if (slot is! CatalogLeafSlot) continue;
      if (slot.bottom < visibleTop || slot.top > visibleBottom) continue;
      leaves++;
      if (_pool.boundFor(slot) != null) bound++;
    }
    fine(.paint, 'paint.summary', {
      'frame': frame,
      'offset': LogFormat.f(_pixels),
      'leaves': leaves,
      'bound': bound,
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
        _painter.paintHeader(canvas: canvas, origin: origin, header: header);
      case final CatalogLeafSlot leaf:
        final isPressed = pressedSlotKey != null && leaf.key == pressedSlotKey;
        final focus = _focus;
        _painter.paintLeaf(
          canvas: canvas,
          origin: origin,
          slot: leaf,
          bound: _pool.boundFor(leaf),
          pressScale: isPressed ? pressScale : 1.0,
          pressProgress: isPressed ? pressProgress : 0,
          focused:
              focus != null &&
              focus.index == leaf.index &&
              focus.sectionId == leaf.sectionId,
          hovered: _isHovered(leaf),
        );
      case final CatalogSkeletonSlot skeleton:
        _painter.paintSkeleton(canvas: canvas, origin: origin, slot: skeleton);
      case final CatalogMessageSlot message:
        _painter.paintMessage(canvas: canvas, origin: origin, slot: message);
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
        case CatalogStitchCapturedHeader(
          :final title,
          :final height,
          :final left,
          :final width,
          :final sectionId,
          :final action,
          :final textDirection,
        ):
          _paintLayoutSlot(
            canvas: canvas,
            origin: bandOrigin,
            slot: CatalogHeaderSlot(
              top: 0,
              height: height,
              left: left,
              width: width,
              title: title,
              sectionId: sectionId,
              action: action,
              textDirection: textDirection,
            ),
            pressedSlotKey: pressedSlotKey,
            pressScale: pressScale,
            pressProgress: pressProgress,
          );
        case CatalogStitchCapturedLeaf(
          :final left,
          :final width,
          :final height,
          :final sectionId,
          :final index,
          :final leaf,
          :final contentBox,
          :final placeholderStyle,
        ):
          _paintLayoutSlot(
            canvas: canvas,
            origin: bandOrigin,
            slot: CatalogLeafSlot(
              top: 0,
              height: height,
              left: left,
              width: width,
              sectionId: sectionId,
              index: index,
              leaf: leaf,
              contentBox: contentBox,
              placeholderStyle: placeholderStyle,
            ),
            pressedSlotKey: pressedSlotKey,
            pressScale: pressScale,
            pressProgress: pressProgress,
          );
        case CatalogStitchCapturedSkeleton(
          :final left,
          :final width,
          :final height,
          :final contentBox,
          :final style,
        ):
          _paintLayoutSlot(
            canvas: canvas,
            origin: bandOrigin,
            slot: CatalogSkeletonSlot(
              top: 0,
              height: height,
              left: left,
              width: width,
              contentBox: contentBox,
              style: style,
            ),
            pressedSlotKey: pressedSlotKey,
            pressScale: pressScale,
            pressProgress: pressProgress,
          );
        case CatalogStitchCapturedMessage(
          :final left,
          :final width,
          :final height,
          :final text,
        ):
          _paintLayoutSlot(
            canvas: canvas,
            origin: bandOrigin,
            slot: CatalogMessageSlot(
              top: 0,
              height: height,
              left: left,
              width: width,
              text: text,
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

  // --- Semantics ------------------------------------------------------------

  /// The nodes of the window handed to the platform; empty while no assistive
  /// technology asks.
  final CatalogSemanticNodes _semanticNodes = CatalogSemanticNodes();

  /// The offset the semantics were last built for. Painting notices a move and
  /// asks for new nodes, which covers every motion (drag, fling, jump, near and
  /// far section jumps) without a call at each; with no assistive technology
  /// running, asking is a no-op.
  double _semanticsPixels = double.nan;

  /// Whether the nodes must be described again even if the window is the same
  /// one: the cells moved, the shell's actions or the focus changed. Without
  /// it a scroll only moves the nodes already built.
  var _semanticsStale = true;

  /// The slot range the nodes were last assembled for.
  (int, int)? _semanticsWindow;

  void _markSemanticsStale() {
    _semanticsStale = true;
    markNeedsSemanticsUpdate();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..explicitChildNodes = true
      ..textDirection = _textDirection;
    if (!hasSize || maxOffset <= 0) return;
    final max = maxOffset;
    config
      ..hasImplicitScrolling = true
      ..scrollPosition = _pixels
      ..scrollExtentMin = 0
      ..scrollExtentMax = max;
    final page = size.height * 0.8;
    if (_pixels < max) {
      config.onScrollUp = () => scrollBy(math.min(page, max - _pixels));
    }
    if (_pixels > 0) {
      config.onScrollDown = () => scrollBy(-math.min(page, _pixels));
    }
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    // The window is the one the bindings use: a binary search to the visible
    // band and one cell of overscan, never a walk over the catalogue.
    final (top, bottom) = _visibleWindow();
    final start = _firstSlotIndexAtOrBelow(top);
    final end = _slotIndexAfter(bottom);
    if (!_semanticsStale &&
        _semanticNodes.hasWindow &&
        _semanticsWindow == (start, end)) {
      _semanticNodes.scrollTo(
        node: node,
        config: config,
        scrollOffset: _pixels,
      );
      return;
    }
    _semanticsStale = false;
    _semanticsWindow = (start, end);
    _semanticNodes.assemble(
      node: node,
      config: config,
      slots: _slots,
      start: start,
      end: end,
      scrollOffset: _pixels,
      width: size.width,
      textDirection: _textDirection,
      target: this,
    );
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _semanticNodes.clear();
    _semanticsStale = true;
    _semanticsWindow = null;
  }

  @override
  Rect? semanticActionBounds(CatalogHeaderSlot header) =>
      _painter.sectionActionBounds(header);

  @override
  VoidCallback? semanticTapOf(CatalogLeafHit hit) {
    if (_onLeafTap == null) return null;
    return () => _onLeafTap?.call(hit);
  }

  /// Reports the start of a long-press at the cell and nothing after it: there
  /// is no gesture to release, so the shell opens what it opens on start and
  /// the user goes on with the assistive technology.
  @override
  VoidCallback? semanticLongPressOf(CatalogLeafHit hit) {
    if (_onLeafLongPressStart == null) return null;
    final eligible = _leafLongPressEligible;
    if (eligible != null && !eligible(hit)) return null;
    return () {
      final cell = _cellRectOf(hit.sectionId, hit.index);
      final local = switch (cell) {
        final cell? => cell.center.translate(0, -_pixels),
        null => Offset.zero,
      };
      _onLeafLongPressStart?.call(
        hit,
        LongPressStartDetails(
          globalPosition: localToGlobal(local),
          localPosition: local,
        ),
      );
    };
  }

  @override
  VoidCallback? semanticActionOf(String sectionId, String actionId) {
    if (_onSectionAction == null) return null;
    return () => _onSectionAction?.call(sectionId, actionId);
  }

  @override
  VoidCallback semanticFocusOf(CatalogLeafHit hit) =>
      () => focusLeaf(hit.sectionId, hit.index, reveal: true);

  @override
  VoidCallback semanticRevealOf(String sectionId, int? index) =>
      () => _reveal(sectionId, index, withHeader: false);

  @override
  bool semanticIsFocused(String sectionId, int index) {
    final focus = _focus;
    return focus != null &&
        focus.index == index &&
        focus.sectionId == sectionId;
  }

  // --- Roving focus ---------------------------------------------------------

  /// The cell that holds roving focus; null when none does. Its leaf is the one
  /// the last snapshot holds at that cell.
  CatalogLeafHit? _focus;

  @override
  CatalogLeafHit? get focusedLeaf => _focus;

  @override
  Rect? get viewportBounds => hasSize
      ? MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size)
      : null;

  // A scan of the slots, once per call: asked when a surface opens, not per
  // frame.
  @override
  Rect? leafBounds(CatalogLeafHit hit) {
    if (!hasSize) return null;
    for (final slot in _slots) {
      if (slot is CatalogLeafSlot &&
          slot.sectionId == hit.sectionId &&
          slot.index == hit.index) {
        return MatrixUtils.transformRect(
          getTransformTo(null),
          Rect.fromLTWH(slot.left, slot.top - _pixels, slot.width, slot.height),
        );
      }
    }
    return null;
  }

  @override
  bool focusLeaf(String sectionId, int index, {required bool reveal}) {
    final cell = _cellById(sectionId, index);
    if (cell == null) return false;
    _setFocus(_hitOf(cell));
    if (reveal) _reveal(sectionId, index, withHeader: true);
    return true;
  }

  @override
  bool moveFocus(CatalogFocusMove move) {
    final sections = _projectedSections;
    if (sections.isEmpty || !hasSize) return false;
    final focus = _focus;
    final current = switch (focus) {
      final focus? => _cellById(focus.sectionId, focus.index),
      null => null,
    };
    final CatalogCell? target;
    if (current != null) {
      target = moveCatalogFocus(
        from: current,
        move: move,
        sections: sections,
        bands: _bands,
      );
    } else {
      // Nothing holds focus: a move enters the grid rather than stepping.
      target = switch (move) {
        CatalogFocusMove.first => firstCatalogCell(sections),
        CatalogFocusMove.last => lastCatalogCell(sections),
        _ => _firstCellInView() ?? firstCatalogCell(sections),
      };
    }
    if (target == null) return false;
    final hit = _hitOf(target);
    _setFocus(hit);
    _reveal(hit.sectionId, hit.index, withHeader: true);
    return true;
  }

  @override
  bool activateFocusedLeaf() {
    final focus = _focus;
    final tap = _onLeafTap;
    if (focus == null || tap == null) return false;
    tap(focus);
    return true;
  }

  @override
  void clearFocus() => _setFocus(null);

  /// The cell [index] of section [sectionId] in the last projection.
  CatalogCell? _cellById(String sectionId, int index) {
    final sections = _projectedSections;
    for (var s = 0; s < sections.length; s++) {
      if (sections[s].id != sectionId) continue;
      return index >= 0 && index < sections[s].leaves.length
          ? (section: s, index: index)
          : null;
    }
    return null;
  }

  CatalogLeafHit _hitOf(CatalogCell cell) {
    final section = _projectedSections[cell.section];
    return CatalogLeafHit(
      sectionId: section.id,
      index: cell.index,
      leaf: section.leaves[cell.index],
    );
  }

  /// The first leaf whose cell is wholly in view below the landing inset (the
  /// first one cut by it when none is whole), or null with no leaf in view.
  CatalogCell? _firstCellInView() {
    final limit = _pixels + (_headerLandingInset ?? _padding.top);
    final bottom = _pixels + size.height;
    CatalogLeafSlot? partial;
    for (var i = _firstSlotIndexAtOrBelow(limit); i < _slots.length; i++) {
      final slot = _slots[i];
      if (slot.top >= bottom) break;
      if (slot case final CatalogLeafSlot leaf) {
        if (leaf.top >= limit) return _cellById(leaf.sectionId, leaf.index);
        partial ??= leaf;
      }
    }
    return switch (partial) {
      final partial? => _cellById(partial.sectionId, partial.index),
      null => null,
    };
  }

  /// Makes [hit] the focused cell (null ends focus). The leaf is always taken
  /// from [hit]; listeners hear a change only when the cell is another one.
  void _setFocus(CatalogLeafHit? hit) {
    final previous = _focus;
    _focus = hit;
    markNeedsPaint();
    _markSemanticsStale();
    if (previous == hit) return;
    _controller.publish(PanelCatalogFocusChanged(hit));
  }

  /// Keeps [_focus] true to [snapshots]: the cell keeps focus with the leaf the
  /// snapshot now holds there, or loses it when the snapshot has no such cell.
  void _validateFocus() {
    final focus = _focus;
    if (focus == null) return;
    for (final section in _snapshots.value.sections) {
      if (section.id != focus.sectionId) continue;
      if (focus.index < section.leaves.length) {
        _focus = CatalogLeafHit(
          sectionId: focus.sectionId,
          index: focus.index,
          leaf: section.leaves[focus.index],
        );
        _markSemanticsStale();
        return;
      }
      break;
    }
    _setFocus(null);
  }

  // --- Cells by identity ----------------------------------------------------

  /// The band of the section [sectionId] in the last projection, or null.
  CatalogSectionBand? _bandOf(String sectionId) {
    final sections = _projectedSections;
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].id == sectionId) return _bands[i];
    }
    return null;
  }

  /// Content rect of the cell [index] of section [sectionId] in the last
  /// projection, or null when there is no such cell.
  Rect? _cellRectOf(String sectionId, int index) {
    final band = _bandOf(sectionId);
    if (band == null || index < 0) return null;
    final grid = band.grid;
    return Rect.fromLTWH(
      grid.cellLeft(index % grid.spanCount),
      band.rowsTop + (index ~/ grid.spanCount) * grid.cellHeight,
      grid.cellWidth,
      grid.cellHeight,
    );
  }

  /// Scrolls the cell [index] of [sectionId] (its header when [index] is null)
  /// into view below the landing inset, moving as little as possible. With
  /// [withHeader], a cell in the first row of its section brings its header
  /// too. Returns whether the cell exists.
  bool _reveal(String sectionId, int? index, {required bool withHeader}) {
    final band = _bandOf(sectionId);
    if (band == null || !hasSize) return false;
    double top;
    double bottom;
    if (index == null) {
      top = band.headerTop;
      bottom = top + band.headerExtent;
    } else {
      final cell = _cellRectOf(sectionId, index);
      if (cell == null) return false;
      top = withHeader && index < band.grid.spanCount
          ? band.headerTop
          : cell.top;
      bottom = cell.bottom;
    }
    final target = scrollOffsetToReveal(
      top: top,
      bottom: bottom,
      pixels: _pixels,
      viewportHeight: size.height,
      topInset: _headerLandingInset ?? _padding.top,
    ).clamp(0.0, maxOffset);
    if (target != _pixels) jumpTo(target);
    return true;
  }

  // --- Debug ----------------------------------------------------------------

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('contentExtent', contentExtent))
      ..add(DoubleProperty('offset', _pixels))
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
