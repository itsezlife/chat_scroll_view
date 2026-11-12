import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:swipe_pager/src/swipe_drag_recognizer.dart';
import 'package:swipe_pager/src/swipe_pager_keep_alive.dart';
import 'package:swipe_pager/src/swipe_pager_physics.dart';

// --- Controller ---------------------------------------------------------

/// The page of a [SwipePager], and the way a host moves it.
///
/// The pager shows at most two pages at a time: the page it is on, and the
/// page coming in while a swipe or a slide runs. A slide to a page further
/// away brings that page in next to the current one, so the pages between
/// are never built or shown.
///
/// [page] is the page the pager rests on or is settling to: a release that
/// goes on to the next page sets it at once, before the settle ends.
/// [position] is the continuous page, for chrome that follows the motion (a
/// tab indicator): during a slide to a page further away it runs through
/// the pages between, though they are not shown.
///
/// Listeners are typed: [addPositionListener] for every change of
/// [position], [addPageListener] for every change of [page], whatever moved
/// it (a swipe, [animateTo], [jumpTo], a key or a semantics action).
/// Registering a callback twice is a no-op; a listener may add or remove
/// listeners while it is called. A move that changes nothing notifies
/// nobody.
///
/// One controller serves one pager at a time. Detached, [animateTo] jumps.
/// After [dispose], every call is a silent no-op.
class SwipePagerController {
  /// A controller whose pager starts on [initialPage].
  SwipePagerController({int initialPage = 0})
    : assert(initialPage >= 0, 'a page index is never negative'),
      _page = initialPage,
      _view = _PagerView(from: initialPage);

  /// The duration of [animateTo] when none is given: 540 ms.
  static const Duration slideDuration = Duration(milliseconds: 540);

  /// The curve of [animateTo] when none is given: an ease out quint, cubic
  /// (0.23, 1, 0.32, 1).
  static const Curve slideCurve = Curves.easeOutQuint;

  int _page;
  _PagerView _view;
  _Phase _phase = _Phase.idle;
  final _positionListeners = <ValueChanged<double>>[];
  final _pageListeners = <ValueChanged<int>>[];
  final _viewListeners = <VoidCallback>[];
  _SwipePagerState? _host;
  AnimationController? _ticker;
  double _settleFrom = 0;
  double _settleTo = 0;
  Curve _settleCurve = Curves.linear;
  Completer<void>? _settled;
  bool _isDisposed = false;

  /// The page the pager rests on or is settling to.
  int get page => _page;

  /// The continuous page.
  double get position => _view.position;

  /// Whether a drag holds the pager.
  bool get isDragging => _phase == _Phase.dragging;

  /// Whether the pager is settling after a release, or sliding to a page.
  bool get isSettling => _phase == _Phase.settling || _phase == _Phase.sliding;

  /// Whether [dispose] was called.
  bool get isDisposed => _isDisposed;

  /// Calls [listener] with [position] on every change of it.
  void addPositionListener(ValueChanged<double> listener) {
    if (_isDisposed || _positionListeners.contains(listener)) return;
    _positionListeners.add(listener);
  }

  /// Stops calling a listener added with [addPositionListener].
  void removePositionListener(ValueChanged<double> listener) =>
      _positionListeners.remove(listener);

  /// Calls [listener] with [page] on every change of it.
  void addPageListener(ValueChanged<int> listener) {
    if (_isDisposed || _pageListeners.contains(listener)) return;
    _pageListeners.add(listener);
  }

  /// Stops calling a listener added with [addPageListener].
  void removePageListener(ValueChanged<int> listener) =>
      _pageListeners.remove(listener);

  /// Slides to [page] over [duration] along [curve], bringing it in next to
  /// the current page, and completes when it lands or is interrupted.
  ///
  /// With animations disabled (`MediaQuery.disableAnimations`), or detached,
  /// it jumps. A slide holds off swipes until it lands. Called during a drag, it drops the drag; during a settle or a
  /// slide, it starts from the page that shows more.
  Future<void> animateTo(
    int page, {
    Duration duration = slideDuration,
    Curve curve = slideCurve,
  }) {
    if (_isDisposed) return Future.value();
    final host = _host;
    final target = _clampPage(page);
    if (host == null ||
        duration == Duration.zero ||
        host.animationsDisabled ||
        target == null) {
      jumpTo(page);
      return Future.value();
    }
    if (_phase == _Phase.sliding && _view.to == target) {
      return _settled?.future ?? Future.value();
    }
    if (_phase == _Phase.idle && target == _page) return Future.value();
    final from = switch (_view) {
      _PagerView(:final to?, :final fraction) when fraction >= 0.5 => to,
      _PagerView(:final from) => from,
    };
    _stopTicker();
    if (from == target) {
      _rest(on: target);
      return Future.value();
    }
    _setView(_PagerView(from: from, to: target));
    _setPage(target);
    return _settle(
      phase: _Phase.sliding,
      to: 1,
      duration: duration,
      curve: curve,
    );
  }

  /// Puts the pager on [page] at once, stopping a drag, a settle or a slide.
  void jumpTo(int page) {
    if (_isDisposed) return;
    final target = _clampPage(page) ?? page;
    _stopTicker();
    _rest(on: target);
  }

  /// Releases the listeners; the controller's pager must be gone first.
  void dispose() {
    if (_isDisposed) return;
    assert(_host == null, 'a controller is disposed after its pager');
    _stopTicker();
    _isDisposed = true;
    _positionListeners.clear();
    _pageListeners.clear();
    _viewListeners.clear();
  }

  // --- Pager-only ------------------------------------------------------

  void _attach(_SwipePagerState host) {
    assert(_host == null, 'a SwipePagerController serves one pager at a time');
    _host = host;
    _ticker = AnimationController(vsync: host)
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
    final clamped = _clampPage(_page);
    if (clamped != null && clamped != _page) jumpTo(clamped);
  }

  void _detach(_SwipePagerState host) {
    if (!identical(_host, host)) return;
    _stopTicker();
    if (_phase != _Phase.idle) _rest(on: _page);
    _ticker?.dispose();
    _ticker = null;
    _host = null;
  }

  int? _clampPage(int page) {
    final count = _host?.pageCount;
    if (count == null || count == 0) return null;
    return page.clamp(0, count - 1);
  }

  bool _canMove({required int forward}) {
    if (_phase == _Phase.sliding) return false;
    final count = _host?.pageCount ?? 0;
    final from = _view.from;
    return forward > 0 ? from < count - 1 : from > 0;
  }

  bool _catchesOnDown() {
    if (_phase != _Phase.settling) return false;
    final extent = _host?.extent ?? 0;
    // A settle within a pixel of its end is finished, not caught.
    if ((_settleTo - _view.fraction).abs() * extent < 1) {
      _stopTicker();
      _finishSettle();
      return false;
    }
    return true;
  }

  void _dragStart({required bool caught}) {
    _stopTicker();
    _phase = _Phase.dragging;
    _caught = caught;
    if (!caught) _setView(_PagerView(from: _view.from));
  }

  bool _caught = false;

  /// [forward] is the drag in pixels toward the next page.
  void _dragUpdate(double forward) {
    if (_phase != _Phase.dragging) return;
    final extent = _host?.extent ?? 0;
    if (extent <= 0) return;
    final view = _view;
    final count = _host?.pageCount ?? 0;
    var signed = view.signedFraction + forward / extent;
    var to = view.to;
    if (signed > 0) {
      if (to == null || to < view.from) to = view.from + 1;
      if (to >= count) signed = 0;
    } else if (signed < 0) {
      if (to == null || to > view.from) to = view.from - 1;
      if (to < 0) signed = 0;
    }
    signed = signed.clamp(-1.0, 1.0);
    _setView(
      signed == 0
          ? _PagerView(from: view.from)
          : _PagerView(from: view.from, to: to, fraction: signed.abs()),
    );
  }

  /// [forward] and [cross] are the release velocity in logical pixels per
  /// second, toward the next page and across the axis.
  void _dragEnd({required double forward, required double cross}) {
    if (_phase != _Phase.dragging) return;
    final host = _host;
    if (host == null) return;
    var view = _view;
    if (view.to == null) {
      // A fling that never moved the pager: it goes the way it is flung.
      final to = view.from + (forward > 0 ? 1 : -1);
      if (forward == 0 || to < 0 || to >= host.pageCount) {
        _rest(on: view.from);
        return;
      }
      view = _PagerView(from: view.from, to: to);
      _setView(view);
    }
    final toward = (view.to! - view.from).sign * forward;
    final commits = host.physics.commits(
      fraction: view.fraction,
      velocity: toward,
      crossVelocity: cross,
      caught: _caught,
      devicePixelRatio: host.devicePixelRatio,
    );
    final settleTo = commits ? 1.0 : 0.0;
    _setPage(commits ? view.to! : view.from);
    final duration = host.physics.settleDuration(
      remaining: (settleTo - view.fraction).abs() * host.extent,
      extent: host.extent,
      velocity: forward,
    );
    unawaited(
      _settle(
        phase: _Phase.settling,
        to: settleTo,
        duration: host.animationsDisabled ? Duration.zero : duration,
        curve: host.physics.settleCurve,
      ),
    );
  }

  Future<void> _settle({
    required _Phase phase,
    required double to,
    required Duration duration,
    required Curve curve,
  }) {
    final ticker = _ticker;
    _settled?.complete();
    final settled = _settled = Completer<void>();
    if (ticker == null || duration == Duration.zero) {
      _settleTo = to;
      _finishSettle();
      return settled.future;
    }
    _phase = phase;
    _settleFrom = _view.fraction;
    _settleTo = to;
    _settleCurve = curve;
    ticker
      ..duration = duration
      ..forward(from: 0);
    return settled.future;
  }

  void _onTick() {
    if (_phase != _Phase.settling && _phase != _Phase.sliding) return;
    final ticker = _ticker;
    if (ticker == null || !ticker.isAnimating) return;
    final t = _settleCurve.transform(ticker.value);
    final fraction = _settleFrom + (_settleTo - _settleFrom) * t;
    _setView(_view.withFraction(fraction));
  }

  void _onStatus(AnimationStatus status) {
    if (status.isCompleted &&
        (_phase == _Phase.settling || _phase == _Phase.sliding)) {
      _finishSettle();
    }
  }

  void _finishSettle() {
    final view = _view;
    final on = _settleTo >= 1 ? (view.to ?? view.from) : view.from;
    _rest(on: on);
  }

  void _rest({required int on}) {
    _phase = _Phase.idle;
    _caught = false;
    _setView(_PagerView(from: on));
    _setPage(on);
    final settled = _settled;
    _settled = null;
    settled?.complete();
    for (final listener in List.of(_viewListeners, growable: false)) {
      listener();
    }
  }

  void _stopTicker() {
    final ticker = _ticker;
    if (ticker != null && ticker.isAnimating) ticker.stop();
  }

  void _setView(_PagerView view) {
    if (view == _view) return;
    final before = _view.position;
    _view = view;
    for (final listener in List.of(_viewListeners, growable: false)) {
      listener();
    }
    if (view.position != before) {
      for (final listener in List.of(_positionListeners, growable: false)) {
        listener(view.position);
      }
    }
  }

  void _setPage(int page) {
    if (page == _page) return;
    _page = page;
    for (final listener in List.of(_pageListeners, growable: false)) {
      listener(page);
    }
  }
}

enum _Phase { idle, dragging, settling, sliding }

/// What the pager shows: [from], and [to] coming in by [fraction] of a page.
@immutable
class _PagerView {
  const _PagerView({required this.from, this.to, this.fraction = 0});

  final int from;
  final int? to;
  final double fraction;

  double get position => switch (to) {
    final to? => from + (to - from) * fraction,
    null => from.toDouble(),
  };

  /// The fraction, negative when [to] is before [from].
  double get signedFraction => switch (to) {
    final to? => (to - from).sign * fraction,
    null => 0,
  };

  _PagerView withFraction(double fraction) =>
      _PagerView(from: from, to: to, fraction: fraction);

  bool shows(int page) => page == from || (page == to && fraction > 0);

  /// Where [page] is, in page widths toward the next page.
  double offsetOf(int page) {
    final to = this.to;
    if (to == null) return 0;
    final direction = (to - from).sign;
    return page == from ? -direction * fraction : direction * (1 - fraction);
  }

  @override
  bool operator ==(Object other) =>
      other is _PagerView &&
      other.from == from &&
      other.to == to &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(from, to, fraction);
}

// --- Widget -------------------------------------------------------------

/// A horizontal pager over [pageCount] pages, swiped with the gesture rules
/// of a mobile pager.
///
/// **The swipe.** A drag becomes a swipe only once it has moved
/// [SwipePagerPhysics.claimSlop] along the axis without first moving
/// [SwipePagerPhysics.crossAxisSlop] across: a vertical scrollable in a
/// page keeps every drag more than about 23 degrees off the horizontal, and
/// a nested horizontal scroller keeps the drags that start on it (its slop
/// is never above the pager's) unless it is at its edge that way: then the
/// pager takes the drag. A quick flick under the slop still swipes
/// when it is fast enough. The first and last page do not swipe outward and
/// there is no overscroll; a drag moves at most one page. A touch on a
/// settling pager catches it and drags it on.
///
/// **The release.** It goes on to the next page from a third of a page, or
/// on a fast enough fling, and settles along a quintic ease out in
/// 150..600 ms ([SwipePagerPhysics]). With animations disabled it
/// lands at once.
///
/// **Pages.** Pages are identified by index. [keepAlive] chooses which
/// pages stay built off screen ([SwipePagerKeepAlive]); a kept page is
/// offstage, out of focus traversal and semantics, under
/// `TickerMode(enabled: false)` and under an invisible [Visibility] that
/// keeps its state ([Visibility.of] is false in it), and so is every page
/// while it is not on screen. A host that reorders pages gives the pager a new key.
///
/// **Reading direction.** In a right-to-left [Directionality] the first page
/// is at the right and the swipes mirror.
///
/// **Devices.** Touch, stylus and trackpad pans swipe ([defaultDragDevices]);
/// a mouse drags only when the host adds `PointerDeviceKind.mouse` to
/// [dragDevices]. A mouse wheel goes to the page's scrollables.
///
/// **Keyboard and semantics.** When [focusable], the pager takes focus in
/// traversal and, while it holds the primary focus itself, the left and
/// right arrow keys page (mirrored right to left); arrows a focused page
/// child handles never reach it. The pager offers the scroll left and
/// scroll right semantics actions while there is a page that way. Both page
/// with [SwipePagerController.animateTo].
class SwipePager extends StatefulWidget {
  /// A pager over [pageCount] pages built by [pageBuilder].
  const SwipePager({
    required this.pageCount,
    required this.pageBuilder,
    this.controller,
    this.onPageChanged,
    this.keepAlive = const SwipePagerKeepAlive.all(),
    this.physics = const SwipePagerPhysics(),
    this.dragDevices = defaultDragDevices,
    this.focusNode,
    this.focusable = false,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  });

  /// The pointers that swipe unless the host chooses: touch, stylus,
  /// inverted stylus, trackpad and unknown; not the mouse.
  static const Set<PointerDeviceKind> defaultDragDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  /// How many pages there are.
  final int pageCount;

  /// Builds the page at an index. Called when a page is first built and
  /// whenever the pager rebuilds, not on every step of a swipe.
  final IndexedWidgetBuilder pageBuilder;

  /// The controller to read and move the page with; the pager makes its own
  /// when null.
  final SwipePagerController? controller;

  /// Called with the new page whenever [SwipePagerController.page] changes.
  final ValueChanged<int>? onPageChanged;

  /// Which pages stay built off screen.
  final SwipePagerKeepAlive keepAlive;

  /// The swipe's slops, release rules and settle.
  final SwipePagerPhysics physics;

  /// The pointer kinds that swipe.
  final Set<PointerDeviceKind> dragDevices;

  /// The pager's own focus node, for a host that moves focus to it.
  final FocusNode? focusNode;

  /// Whether the pager takes focus and pages with the arrow keys.
  final bool focusable;

  /// How the pages are clipped to the pager.
  final Clip clipBehavior;

  @override
  State<SwipePager> createState() => _SwipePagerState();
}

class _SwipePagerState extends State<SwipePager>
    with SingleTickerProviderStateMixin {
  SwipePagerController? _own;
  late SwipePagerController _controller;
  late final SwipeDragRecognizer _recognizer = SwipeDragRecognizer(
    debugOwner: this,
    supportedDevices: widget.dragDevices,
  );

  /// The pages built, kept or on screen.
  final _built = <int>{};

  /// The pages settled on, most recent first.
  final _recency = <int>[];

  int get pageCount => widget.pageCount;
  SwipePagerPhysics get physics => widget.physics;
  bool get animationsDisabled =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  double get devicePixelRatio =>
      MediaQuery.maybeDevicePixelRatioOf(context) ??
      View.of(context).devicePixelRatio;
  double get extent => context.size?.width ?? 0;
  bool get _rtl => Directionality.maybeOf(context) == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller ?? (_own = SwipePagerController()));
  }

  @override
  void didUpdateWidget(SwipePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _unbind();
      _own?.dispose();
      _own = null;
      _bind(widget.controller ?? (_own = SwipePagerController()));
    }
    if (widget.pageCount != oldWidget.pageCount) {
      _built.removeWhere((page) => page >= widget.pageCount);
      _recency.removeWhere((page) => page >= widget.pageCount);
      if (widget.pageCount > 0 && _controller.page >= widget.pageCount) {
        _controller.jumpTo(widget.pageCount - 1);
      }
    }
    if (widget.keepAlive != oldWidget.keepAlive) _prune();
    _recognizer.supportedDevices = widget.dragDevices;
    _showVisible();
  }

  void _bind(SwipePagerController controller) {
    _controller = controller
      .._attach(this)
      .._viewListeners.add(_onView)
      ..addPageListener(_onPage);
    _built.clear();
    _recency
      ..clear()
      ..add(controller.page);
    _showVisible();
  }

  void _unbind() {
    _controller
      .._viewListeners.remove(_onView)
      ..removePageListener(_onPage)
      .._detach(this);
  }

  @override
  void dispose() {
    _unbind();
    _own?.dispose();
    _recognizer.dispose();
    super.dispose();
  }

  void _onPage(int page) {
    // The semantics actions depend on the page.
    _rebuild(() {});
    widget.onPageChanged?.call(page);
  }

  void _onView() {
    if (_controller._phase == _Phase.idle) {
      final page = _controller.page;
      if (_recency.isEmpty || _recency.first != page) {
        _recency
          ..remove(page)
          ..insert(0, page);
      }
      _prune();
    }
    _showVisible();
  }

  /// Builds the pages on screen that are not built yet.
  void _showVisible() {
    final view = _controller._view;
    final missing = [
      view.from,
      ?view.to,
    ].where((page) => page < pageCount && !_built.contains(page));
    if (missing.isEmpty) return;
    _rebuild(() => _built.addAll(missing));
  }

  /// Drops the pages the policy does not keep and that are not on screen.
  void _prune() {
    final view = _controller._view;
    final keep = <int>{
      for (var rank = 0; rank < _recency.length; rank++)
        if (widget.keepAlive.keeps(rank)) _recency[rank],
      view.from,
      ?view.to,
    };
    _recency.removeWhere((page) => !keep.contains(page));
    if (_built.every(keep.contains)) return;
    _rebuild(() => _built.retainAll(keep));
  }

  void _rebuild(VoidCallback change) {
    if (!mounted) {
      change();
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      // A jump made during a build or layout: rebuild after this frame.
      change();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(change);
  }

  // --- Gestures ----------------------------------------------------------

  /// A screen-space horizontal delta as pixels toward the next page.
  double _forward(double dx) => _rtl ? dx : -dx;

  void _configure(SwipeDragRecognizer recognizer) {
    final controller = _controller;
    recognizer
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
      ..physics = widget.physics
      ..devicePixelRatio = devicePixelRatio
      ..canMove = ((dx) =>
          controller._canMove(forward: _forward(dx).sign.toInt()))
      ..catchesOnDown = controller._catchesOnDown
      ..onStart = controller._dragStart
      ..onUpdate = ((dx) => controller._dragUpdate(_forward(dx)))
      ..onEnd = ((velocity) => controller._dragEnd(
        forward: _forward(velocity.dx),
        cross: velocity.dy,
      ));
  }

  // --- Keyboard and semantics -------------------------------------------

  void _page(int forward) {
    final target = _controller.page + forward;
    if (target < 0 || target >= pageCount) return;
    unawaited(_controller.animateTo(target));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final forward = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight => _rtl ? -1 : 1,
      LogicalKeyboardKey.arrowLeft => _rtl ? 1 : -1,
      _ => 0,
    };
    if (forward == 0) return KeyEventResult.ignored;
    _page(forward);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final page = _controller.page;
    // Scroll left moves the content left: the next page in left to right.
    final leftward = _rtl ? -1 : 1;
    final canLeft = page + leftward >= 0 && page + leftward < pageCount;
    final canRight = page - leftward >= 0 && page - leftward < pageCount;
    final pages = [..._built]..sort();
    _configure(_recognizer);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      onScrollLeft: canLeft ? () => _page(leftward) : null,
      onScrollRight: canRight ? () => _page(-leftward) : null,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: widget.focusable,
        skipTraversal: !widget.focusable,
        onKeyEvent: _onKey,
        child: _SwipeRegion(
          recognizer: _recognizer,
          child: ClipRect(
            clipBehavior: widget.clipBehavior,
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final index in pages)
                  _PageSlot(
                    key: ValueKey<int>(index),
                    index: index,
                    controller: _controller,
                    mirrored: _rtl,
                    child: widget.pageBuilder(context, index),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One built page: placed by the controller's view, and offstage, out of
/// focus, under `TickerMode(enabled: false)` and under an invisible
/// [Visibility] while not on screen.
///
/// Its wrappers keep one shape whatever the page's state, so a page that
/// leaves the screen and comes back keeps its element and state; only the
/// flags and the translation change, and the page itself is not rebuilt on
/// the steps of a swipe.
class _PageSlot extends StatefulWidget {
  const _PageSlot({
    required this.index,
    required this.controller,
    required this.mirrored,
    required this.child,
    super.key,
  });

  final int index;
  final SwipePagerController controller;
  final bool mirrored;
  final Widget child;

  @override
  State<_PageSlot> createState() => _PageSlotState();
}

class _PageSlotState extends State<_PageSlot> {
  @override
  void initState() {
    super.initState();
    widget.controller._viewListeners.add(_onView);
  }

  @override
  void didUpdateWidget(_PageSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._viewListeners.remove(_onView);
      widget.controller._viewListeners.add(_onView);
    }
  }

  @override
  void dispose() {
    widget.controller._viewListeners.remove(_onView);
    super.dispose();
  }

  void _onView() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.controller._view;
    final shown = view.shows(widget.index);
    final offset = view.offsetOf(widget.index);
    // Offstage, out of focus and with its tickers off while not shown, under
    // a [Visibility] rather than bare `Offstage` and `TickerMode`: content
    // that asks [Visibility.of] learns that nothing of the page is on
    // screen, so a catalogue in it gives back what its frames live on (a
    // platform texture) while keeping the frames, which tickers off alone
    // read as a surface held on screen.
    return Visibility(
      visible: shown,
      maintainState: true,
      child: FractionalTranslation(
        translation: Offset(widget.mirrored ? -offset : offset, 0),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

// --- Gesture region -----------------------------------------------------

/// Where the pager's drags start: it hands each down to the recognizer, and
/// shows it each move before any recognizer handles the move.
///
/// A `RawGestureDetector` would add the pointer the same way, but its
/// recognizers see a move only through the pointer router, after every
/// recognizer nested in the page; a nested horizontal scroller would claim
/// at its slop before the pager could learn it sits at its edge. Hit-test
/// targets get each event before the router, so the region looks first.
class _SwipeRegion extends SingleChildRenderObjectWidget {
  const _SwipeRegion({required this.recognizer, required super.child});

  final SwipeDragRecognizer recognizer;

  @override
  _RenderSwipeRegion createRenderObject(BuildContext context) =>
      _RenderSwipeRegion(recognizer);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSwipeRegion renderObject,
  ) => renderObject.recognizer = recognizer;
}

class _RenderSwipeRegion extends RenderProxyBoxWithHitTestBehavior {
  _RenderSwipeRegion(this.recognizer) : super(behavior: HitTestBehavior.opaque);

  SwipeDragRecognizer recognizer;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    switch (event) {
      case PointerDownEvent():
        recognizer.addPointer(event);
      case PointerPanZoomStartEvent():
        recognizer.addPointerPanZoom(event);
      case PointerMoveEvent() || PointerPanZoomUpdateEvent():
        recognizer.preview(event, nestedAtEdge: _nestedAtEdge);
      default:
    }
  }

  /// Whether a horizontal scroller that takes drags is under the global
  /// [position], and none of those there can scroll a drag by the
  /// screen-space horizontal [delta]: each is at its edge that way.
  ///
  /// A scroller is found by its viewport in a fresh hit test of the pages,
  /// so the scrollers need no registration; one whose content fits, or whose
  /// physics refuse the user, takes no drags and does not count. A scroller
  /// that is not a sliver viewport (a `SingleChildScrollView`) is not seen
  /// and keeps its drags.
  bool _nestedAtEdge(Offset position, double delta) {
    final child = this.child;
    if (child == null || !attached) return false;
    final result = BoxHitTestResult();
    child.hitTest(result, position: globalToLocal(position));
    var nested = false;
    for (final entry in result.path) {
      if (entry.target case RenderViewportBase(
        axis: Axis.horizontal,
        :final axisDirection,
        offset: final ScrollPosition scroll,
      ) when scroll.physics.shouldAcceptUserOffset(scroll)) {
        if (_scrolls(scroll, axisDirection, delta)) return false;
        nested = true;
      }
    }
    return nested;
  }

  /// Whether [scroll], laid out along [axisDirection], has content left to
  /// bring in by a drag of the screen-space horizontal [delta].
  static bool _scrolls(
    ScrollPosition scroll,
    AxisDirection axisDirection,
    double delta,
  ) {
    // A finger moving right drags the content right: toward the start of a
    // viewport laid out to the right, the end of one laid out to the left.
    final toward = switch (axisDirection) {
      AxisDirection.right => -delta,
      AxisDirection.left => delta,
      AxisDirection.up || AxisDirection.down => 0.0,
    };
    final room = toward > 0 ? scroll.extentAfter : scroll.extentBefore;
    return room > precisionErrorTolerance;
  }
}
