import 'dart:async';
import 'dart:math' as math;

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/host/attach_sheet_host.dart';
import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:attach_sheet/src/sheet/attach_outcome.dart';
import 'package:attach_sheet/src/sheet/attach_sheet_scroll_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Builds the sheet's content: the page, over the sheet's [scrollController]
/// (also the `PrimaryScrollController` below the sheet).
typedef AttachSheetContentBuilder =
    Widget Function(BuildContext context, ScrollController scrollController);

/// The **attach sheet**: the mobile container a user picks media and files
/// to send from.
///
/// Owns the window: the scrim, the sheet's geometry and its motion (open,
/// close, drag, expand, collapse, dismiss), the discard guard and the
/// keyboard hand-off, each by its [policy]. The content is the page's: it
/// scrolls on the sheet's scroll controller, so one drag both moves the
/// sheet and scrolls the page. A [bottomBar] stays at the bottom edge while
/// the sheet moves above it.
///
/// Open one with [AttachSheet.show]; it closes with an [AttachOutcome].
class AttachSheet extends StatefulWidget {
  /// A sheet over [selection], laid out and moved by [policy].
  const AttachSheet({
    required this.policy,
    required this.selection,
    required this.builder,
    required this.onClosed,
    this.host = const AttachSheetHost(),
    this.opening = const AttachSheetOpening(),
    this.header,
    this.bottomBar,
    super.key,
  });

  /// Geometry, motion, gestures and the discard rule.
  final AttachSheetPolicy policy;

  /// The open's attach selection; a non-empty one asks before closing.
  final AttachSelection selection;

  /// The content: the page.
  final AttachSheetContentBuilder builder;

  /// Called once the sheet has finished closing.
  final ValueChanged<AttachOutcome> onClosed;

  /// What the sheet tells its host and asks of it.
  final AttachSheetHost host;

  /// What the host knew at open.
  final AttachSheetOpening opening;

  /// The header that fades in while the sheet is pinned at the top (on a
  /// policy with a header fade); null for none.
  final Widget? header;

  /// The bar at the bottom edge (tabs, caption and send).
  final Widget? bottomBar;

  /// Pushes a sheet over [context]'s navigator and completes with its
  /// outcome; [AttachOutcome.cancelled] when it is removed some other way.
  static Future<AttachOutcome> show(
    BuildContext context, {
    required AttachSheetPolicy policy,
    required AttachSelection selection,
    required AttachSheetContentBuilder builder,
    AttachSheetHost host = const AttachSheetHost(),
    AttachSheetOpening opening = const AttachSheetOpening(),
    Widget? header,
    Widget? bottomBar,
  }) async {
    final navigator = Navigator.of(context);
    final outcome = await navigator.push(
      _AttachSheetRoute(
        builder: (context) => AttachSheet(
          policy: policy,
          selection: selection,
          builder: builder,
          host: host,
          opening: opening,
          header: header,
          bottomBar: bottomBar,
          onClosed: (outcome) => Navigator.of(context).pop(outcome),
        ),
      ),
    );
    return outcome ?? const AttachOutcome.cancelled();
  }

  @override
  State<AttachSheet> createState() => _AttachSheetState();
}

/// The handle to a showing sheet, for its content and bars:
/// `AttachSheetController.of(context)`.
abstract interface class AttachSheetController {
  /// The controller of the sheet above [context].
  static AttachSheetController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_AttachSheetScope>();
    assert(scope != null, 'No AttachSheet above this context.');
    return scope!.controller;
  }

  /// The sheet's top edge from the top of the screen, as it moves.
  ValueListenable<double> get top;

  /// Whether the sheet is at its top.
  bool get isExpanded;

  /// Whether a tap on the scrim above the sheet dismisses it (a page turns
  /// it off while its camera is open).
  bool get dismissesOnTapAbove;
  set dismissesOnTapAbove(bool value);

  /// Whether drags move the sheet (a page turns it off for a gesture of its
  /// own).
  bool get panEnabled;
  set panEnabled(bool value);

  /// Raises the sheet to its top.
  Future<void> expand();

  /// Lowers the sheet to its resting height.
  Future<void> collapse();

  /// Closes the sheet, asking the discard question first when the
  /// selection is not empty.
  Future<void> requestDismiss();

  /// Closes the sheet with [outcome], without asking.
  Future<void> close(AttachOutcome outcome);
}

class _AttachSheetScope extends InheritedWidget {
  const _AttachSheetScope({required this.controller, required super.child});

  final AttachSheetController controller;

  @override
  bool updateShouldNotify(_AttachSheetScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

class _AttachSheetState extends State<AttachSheet>
    with TickerProviderStateMixin
    implements AttachSheetDrive, AttachSheetController {
  late final AnimationController _$top = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _$dim = AnimationController(vsync: this);
  late final AnimationController _$header = AnimationController(vsync: this);
  late final AttachSheetScrollController _$scroll = AttachSheetScrollController(
    this,
  );

  // Geometry of the last layout.
  Size _size = Size.zero;
  double _collapsedTop = 0;
  double _expandedTop = 0;
  Rect? _card;
  bool _keyboardUp = false;
  double _devicePixelRatio = 1;
  ChromeMotionSpeed _speed = ChromeMotionSpeed.normal;

  // Lifecycle.
  bool _opened = false;
  bool _closing = false;
  bool _asking = false;
  Curve _dimCurve = Curves.linear;
  Timer? _$dimDelay;

  // The drag in progress.
  bool _$sheetMoved = false;
  bool _$startedExpanded = false;
  bool _$discardPending = false;

  @override
  bool dismissesOnTapAbove = true;

  @override
  bool panEnabled = true;

  AttachSheetPolicy get _policy => widget.policy;

  @override
  void initState() {
    super.initState();
    _$top.addListener(_syncHeader);
  }

  @override
  void dispose() {
    _$dimDelay?.cancel();
    _$scroll.dispose();
    _$top.dispose();
    _$dim.dispose();
    _$header.dispose();
    super.dispose();
  }

  // --- Controller ---

  @override
  ValueListenable<double> get top => _$top;

  @override
  bool get isExpanded => _$top.value <= _expandedTop + 0.5;

  @override
  Future<void> expand() => _moveTo(_expandedTop, _policy.expandMotion);

  @override
  Future<void> collapse() => _moveTo(_collapsedTop, _policy.expandMotion);

  @override
  Future<void> requestDismiss() async {
    if (_closing || _asking) return;
    if (widget.selection.isNotEmpty) {
      _asking = true;
      final drop = await widget.host.confirmDiscard(
        context,
        _policy.discardWording,
      );
      _asking = false;
      if (!mounted || !drop) return;
    }
    await close(const AttachOutcome.cancelled());
  }

  @override
  Future<void> close(AttachOutcome outcome, {double velocity = 0}) async {
    if (_closing) return;
    _closing = true;
    _$dimDelay?.cancel();
    final dimOut = _policy.dimOut.withSpeed(_speed);
    _dimCurve = dimOut.curve;
    unawaited(_$dim.animateBack(0, duration: dimOut.duration));
    final end = _card == null ? _size.height + 10 : _size.height;
    final motion = velocity == 0
        ? _policy.closeMotion
        : _policy.settleMotion(AttachSheetRelease.dismiss);
    await _moveTo(end, motion, velocity: velocity);
    if (!mounted) return;
    final opening = widget.opening;
    final host = widget.host;
    host.closed(opening);
    if ((_policy.keyboardReopenDelay, opening.keyboardWasUp) case (
      final delay?,
      true,
    )) {
      Timer(delay, host.restoreKeyboard);
    }
    widget.onClosed(outcome);
  }

  // --- Motion ---

  /// Moves the top to [target]; completes when it gets there, or when a
  /// drag or another motion takes over (a cancelled motion is not an
  /// error: the sheet is simply somewhere else now).
  Future<void> _moveTo(
    double target,
    AttachSheetMotion motion, {
    double velocity = 0,
  }) async {
    if (_speed.isInstant) {
      _$top.value = target;
      return;
    }
    final ticker = switch (motion) {
      AttachSheetMotion$Spring(:final spring) => _$top.animateWith(
        SpringSimulation(spring, _$top.value, target, velocity),
      ),
      AttachSheetMotion$Timed(:final spec) => _timed(target, spec),
    };
    try {
      await ticker.orCancel;
    } on TickerCanceled {
      return;
    }
    // A spring stops within its tolerance of the target; land on it.
    if (mounted) _$top.value = target;
  }

  TickerFuture _timed(double target, MotionSpec spec) {
    final scaled = spec.withSpeed(_speed);
    return _$top.animateTo(
      target,
      duration: scaled.duration,
      curve: scaled.curve,
    );
  }

  void _open() {
    _opened = true;
    widget.host.opened(widget.opening);
    _$top.value = _size.height;
    unawaited(_moveTo(_collapsedTop, _policy.openMotion));
    final dimIn = _policy.dimIn.withSpeed(_speed);
    _dimCurve = dimIn.curve;
    void fadeIn() => _$dim.animateTo(1, duration: dimIn.duration);
    final delay = _speed.scale(_policy.dimDelay);
    if (delay == Duration.zero) {
      fadeIn();
    } else {
      _$dimDelay = Timer(delay, fadeIn);
    }
  }

  void _syncHeader() {
    final fade = _policy.headerFade;
    if (fade == null || !_opened || _closing) return;
    final target = isExpanded ? 1.0 : 0.0;
    if (_headerTarget == target) return;
    _headerTarget = target;
    final spec = fade.withSpeed(_speed);
    _$header.animateTo(target, duration: spec.duration, curve: spec.curve);
  }

  double _headerTarget = 0;

  // --- Drive (the page's scroll hands drags here) ---

  @override
  bool get takesDrags =>
      _opened &&
      !_closing &&
      _card == null &&
      panEnabled &&
      !(_policy.panDisabledWithKeyboard && _keyboardUp);

  @override
  bool get isAtTop => isExpanded;

  @override
  bool get endsDrag => _$discardPending;

  @override
  void dragStarted() {
    _$sheetMoved = false;
    _$discardPending = false;
    _$startedExpanded = isExpanded;
    _$top.stop();
  }

  @override
  double dragSheet(double delta) {
    if (_$discardPending) return 0;
    _$sheetMoved = true;
    final next = _$top.value + delta;
    if (delta < 0) {
      final clamped = math.max(next, _expandedTop);
      _$top.value = clamped;
      return next - clamped;
    }
    _$top.value = next;
    final threshold = _policy.discardPanThreshold;
    if (threshold != null &&
        widget.selection.isNotEmpty &&
        next - _collapsedTop > threshold) {
      _$discardPending = true;
    }
    return 0;
  }

  @override
  bool release(double velocity, void Function(double) handBack) {
    if (!_$sheetMoved) return false;
    _$sheetMoved = false;
    if (_$discardPending) {
      _$discardPending = false;
      unawaited(_moveTo(_collapsedTop, _holdMotion()));
      unawaited(requestDismiss());
      return true;
    }
    final decision = _policy.release(
      AttachSheetReleaseInput(
        top: _$top.value,
        collapsedTop: _collapsedTop,
        expandedTop: _expandedTop,
        velocity: velocity,
        startedExpanded: _$startedExpanded,
        devicePixelRatio: _devicePixelRatio,
      ),
    );
    switch (decision) {
      case null:
        return false;
      case AttachSheetRelease.dismiss:
        if (widget.selection.isNotEmpty) {
          unawaited(_moveTo(_collapsedTop, _holdMotion()));
          unawaited(requestDismiss());
        } else {
          unawaited(close(const AttachOutcome.cancelled(), velocity: velocity));
        }
      case AttachSheetRelease.expand:
        unawaited(
          _moveTo(
            _expandedTop,
            _policy.settleMotion(decision),
            velocity: velocity,
          ),
        );
      case AttachSheetRelease.collapse:
        unawaited(
          _moveTo(
            _collapsedTop,
            _policy.settleMotion(decision),
            velocity: velocity,
          ),
        );
      case AttachSheetRelease.holdExpanded:
        unawaited(_moveTo(_expandedTop, _policy.settleMotion(decision)));
      case AttachSheetRelease.holdCollapsed:
        unawaited(_moveTo(_collapsedTop, _holdMotion()));
      case AttachSheetRelease.fling:
        unawaited(_fling(velocity, handBack));
    }
    return true;
  }

  AttachSheetMotion _holdMotion() => AttachSheetMotion.timed(
    _policy.holdMotion((_$top.value - _collapsedTop).abs()),
  );

  /// The page's fling carried by the sheet between its rest and its top:
  /// at the top the rest of the velocity scrolls the page; at the rest it
  /// stops. Where it stops, a sheet inside the snap zone goes to the top.
  Future<void> _fling(
    double velocity,
    void Function(double scrollVelocity) handBack,
  ) async {
    if (velocity != 0 && !_speed.isInstant) {
      final fling = _SheetFling(
        start: _$top.value,
        min: _expandedTop,
        max: _collapsedTop,
        fling: ClampingScrollSimulation(position: 0, velocity: velocity),
      );
      try {
        await _$top.animateWith(fling).orCancel;
      } on TickerCanceled {
        return;
      }
      if (!mounted) return;
      if (fling.hitMin && fling.lastVelocity < 0) {
        handBack(-fling.lastVelocity);
        return;
      }
    }
    await _snap();
  }

  Future<void> _snap() async {
    final zone = _policy.pinSnapZone;
    final above = _$top.value - _expandedTop;
    if (zone != null && above > 0.5 && above < zone) {
      await _moveTo(_expandedTop, _policy.expandMotion);
    }
  }

  /// The top drawn: off the bottom edge until the open starts.
  double get _shownTop => _opened ? _$top.value : _size.height;

  // --- Taps ---

  void _tapScrim() {
    if (!_policy.dismissesOnTapAbove || !dismissesOnTapAbove) return;
    unawaited(requestDismiss());
  }

  // --- Build ---

  void _measure(BoxConstraints constraints) {
    final media = MediaQuery.of(context);
    _size = constraints.biggest;
    final padding = media.padding;
    _keyboardUp = media.viewInsets.bottom > 0;
    _devicePixelRatio = media.devicePixelRatio;
    _speed = ChromeMotionScope.of(context).speed;
    final anchor =
        widget.opening.anchor ??
        Rect.fromLTWH(_size.width / 2, _size.height, 0, 0);
    _card = _policy.cardFor(_size, padding, anchor: anchor);
    final card = _card;
    if (card != null) {
      _collapsedTop = card.top;
      _expandedTop = card.top;
    } else {
      _collapsedTop = _policy.collapsedTop(_size, padding);
      _expandedTop = math.min(_policy.expandedTop(padding), _collapsedTop);
    }
    if (!_opened) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_opened) _open();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.attachOf(context);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(requestDismiss());
      },
      child: _AttachSheetScope(
        controller: this,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _measure(constraints);
            return Stack(
              children: [
                Positioned.fill(child: _scrim(tokens)),
                if (_card case final card?)
                  _cardLayer(card, tokens)
                else ...[
                  _sheetLayer(tokens),
                  if (widget.bottomBar case final bar?) _barLayer(bar),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _scrim(AttachTokens tokens) {
    final opacity = _card == null ? _policy.dimOpacity : _policy.cardDimOpacity;
    return GestureDetector(
      key: const ValueKey('attach-sheet-scrim'),
      behavior: HitTestBehavior.opaque,
      onTap: _tapScrim,
      child: AnimatedBuilder(
        animation: _$dim,
        builder: (context, _) {
          final t = _dimCurve.transform(_$dim.value.clamp(0, 1));
          final alpha = (opacity * t).clamp(0.0, 1.0);
          return ColoredBox(color: tokens.scrim.withValues(alpha: alpha));
        },
      ),
    );
  }

  Widget _sheetLayer(AttachTokens tokens) {
    final radius = _policy.cornerRadiusFor(_size);
    final grabber = _policy.grabber;
    final header = widget.header;
    final squares = _policy.squaresCornersWhenPinned;
    final content = PrimaryScrollController(
      controller: _$scroll,
      child: Builder(builder: (context) => widget.builder(context, _$scroll)),
    );
    return AnimatedBuilder(
      animation: Listenable.merge([_$top, _$header]),
      child: content,
      builder: (context, content) {
        final top = _shownTop;
        final pinned = _$header.value;
        final corner = squares ? radius * (1 - pinned) : radius;
        return Positioned(
          key: const ValueKey('attach-sheet'),
          left: 0,
          right: 0,
          top: top,
          height: math.max(0, _size.height - top),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(corner)),
            child: ColoredBox(
              color: tokens.background,
              child: Stack(
                children: [
                  Positioned.fill(child: content!),
                  if (grabber != null)
                    Positioned(
                      top: grabber.top,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: Opacity(
                            opacity: grabber.fadesWithHeader ? 1 - pinned : 1,
                            child: Container(
                              key: const ValueKey('attach-sheet-grabber'),
                              width: grabber.size.width,
                              height: grabber.size.height,
                              decoration: BoxDecoration(
                                color: tokens.grabber,
                                borderRadius: BorderRadius.circular(
                                  grabber.size.height / 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (header != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: _policy.headerFade != null && pinned == 0,
                        child: Opacity(
                          key: const ValueKey('attach-sheet-header'),
                          opacity: _policy.headerFade == null ? 1 : pinned,
                          child: ColoredBox(
                            color: tokens.header,
                            child: header,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _barLayer(Widget bar) => AnimatedBuilder(
    animation: _$top,
    child: bar,
    builder: (context, bar) => Positioned(
      key: const ValueKey('attach-sheet-bar'),
      left: 0,
      right: 0,
      bottom: 0,
      child: Transform.translate(
        offset: Offset(0, math.max(0, _shownTop - _collapsedTop)),
        child: bar,
      ),
    ),
  );

  Widget _cardLayer(Rect card, AttachTokens tokens) {
    final radius = _policy.cornerRadius;
    return AnimatedBuilder(
      animation: _$top,
      child: PrimaryScrollController(
        controller: _$scroll,
        child: Builder(builder: (context) => widget.builder(context, _$scroll)),
      ),
      builder: (context, content) {
        // The card rises from the bottom edge on the sheet's motion; its
        // contents fade with the distance left.
        final travel = (_size.height - card.top).clamp(1, double.infinity);
        final shown = (1 - (_shownTop - card.top) / travel).clamp(0.0, 1.0);
        return Positioned(
          key: const ValueKey('attach-sheet-card'),
          left: card.left,
          top: _shownTop,
          width: card.width,
          height: card.height,
          child: Opacity(
            opacity: shown,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: const [
                  BoxShadow(color: Color(0x4D000000), blurRadius: 80),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: ColoredBox(color: tokens.background, child: content),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A fling of the sheet's top (the page's own Android-style deceleration) from [start], stopped at [min] (the
/// top) or [max] (the rest).
class _SheetFling extends Simulation {
  _SheetFling({
    required this.start,
    required this.min,
    required this.max,
    required this.fling,
  });

  final double start;
  final double min;
  final double max;
  final ClampingScrollSimulation fling;

  bool hitMin = false;
  bool _hitMax = false;
  double lastVelocity = 0;

  @override
  double x(double time) {
    final raw = start + fling.x(time);
    lastVelocity = fling.dx(time);
    if (raw <= min) {
      hitMin = true;
      return min;
    }
    if (raw >= max) {
      _hitMax = true;
      return max;
    }
    return raw;
  }

  @override
  double dx(double time) => fling.dx(time);

  @override
  bool isDone(double time) => hitMin || _hitMax || fling.isDone(time);
}

class _AttachSheetRoute extends PopupRoute<AttachOutcome> {
  _AttachSheetRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);
}
