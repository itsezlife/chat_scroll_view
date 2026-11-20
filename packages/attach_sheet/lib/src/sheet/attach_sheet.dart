import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/host/attach_sheet_host.dart';
import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/page/attach_pages_sheet.dart';
import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:attach_sheet/src/sheet/attach_outcome.dart';
import 'package:attach_sheet/src/sheet/attach_sheet_scroll_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/widgets.dart' hide RichText;
import 'package:viewport_scroll/engine.dart';

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
/// Open one with its pages and tab bar by [AttachSheet.show], or around
/// any content by [AttachSheet.showContent]; it closes with an
/// [AttachOutcome].
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

  /// Pushes a sheet of [pages] over [context]'s navigator, with the tab
  /// bar at the bottom (the attach panel in its place while something is
  /// selected) and each page's header items in the pinned header, and
  /// completes with its outcome; [AttachOutcome.cancelled] when it is
  /// removed some other way.
  ///
  /// [initialCaption] is the composer's text, moved into the caption; a
  /// cancel returns the caption as it is then. [optionStore] remembers the
  /// send options per the selection's attach policy.
  static Future<AttachOutcome> show(
    BuildContext context, {
    required AttachSheetPolicy policy,
    required AttachSelection selection,
    required AttachPageRegistry pages,
    AttachSheetHost host = const AttachSheetHost(),
    AttachSheetOpening opening = const AttachSheetOpening(),
    RichText initialCaption = RichText.empty,
    SendOptionStore? optionStore,
  }) async {
    final outcome = await Navigator.of(context).push(
      _attachSheetRoute(
        builder: (context) => AttachPagesSheet(
          policy: policy,
          selection: selection,
          pages: pages,
          host: host,
          opening: opening,
          initialCaption: initialCaption,
          optionStore: optionStore,
          onClosed: (outcome) => _closeRoute(context, outcome),
        ),
      ),
    );
    return outcome ?? const AttachOutcome.cancelled();
  }

  /// Pushes a sheet around [builder]'s content (no pages, no tabs) and
  /// completes with its outcome; [AttachOutcome.cancelled] when it is
  /// removed some other way.
  static Future<AttachOutcome> showContent(
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
      _attachSheetRoute(
        builder: (context) => AttachSheet(
          policy: policy,
          selection: selection,
          builder: builder,
          host: host,
          opening: opening,
          header: header,
          bottomBar: bottomBar,
          onClosed: (outcome) => _closeRoute(context, outcome),
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

  /// The controller of the sheet above [context], or null outside a sheet
  /// (a panel in a viewer or a confirm box).
  static AttachSheetController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_AttachSheetScope>()
      ?.controller;

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

  /// The resting top in place of the policy's (a page's top offset); null
  /// for the policy's. A sheet at rest moves to the new one.
  set restTop(double? value);

  /// Asked before the sheet closes, ahead of the discard guard; false keeps
  /// it open. Null for none.
  set dismissGuard(Future<bool> Function()? value);

  /// A new scroll controller sharing the sheet's drag, for one more page;
  /// the caller disposes it.
  ScrollController createScrollController();

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

  // The morph out of the attach button: 0 at the button, 1 at the sheet.
  late final AnimationController _$morphPosition =
      AnimationController.unbounded(vsync: this, value: 1);
  late final AnimationController _$morphBounds = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  late final AnimationController _$morphCorners = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  late final AnimationController _$morphContent = AnimationController(
    vsync: this,
    value: 1,
  );
  bool _morphing = false;

  // How tall the bottom bar is, safe area included: the content's bottom
  // padding, so a page's last row scrolls clear of it.
  final ValueNotifier<double> _$barExtent = ValueNotifier(0);
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

  double? _$restTop;

  @override
  set restTop(double? value) {
    if (_$restTop == value) return;
    final atRest =
        _opened && !_closing && (_$top.value - _collapsedTop).abs() < 0.5;
    _$restTop = value;
    if (!mounted) return;
    setState(() {});
    if (atRest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_moveTo(_collapsedTop, _policy.expandMotion));
      });
    }
  }

  Future<bool> Function()? _$dismissGuard;

  @override
  set dismissGuard(Future<bool> Function()? value) => _$dismissGuard = value;

  @override
  ScrollController createScrollController() =>
      AttachSheetScrollController(this);

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
    _$barExtent.dispose();
    _$top.dispose();
    _$dim.dispose();
    _$header.dispose();
    _$morphPosition.dispose();
    _$morphBounds.dispose();
    _$morphCorners.dispose();
    _$morphContent.dispose();
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
    if (_$dismissGuard case final guard?) {
      _asking = true;
      final leave = await guard();
      _asking = false;
      if (!mounted || !leave) return;
    }
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
    if (velocity == 0 && _morph != null && !_speed.isInstant) {
      await _morphBack(_morph!);
    } else {
      final end = _card == null ? _size.height + 10 : _size.height;
      final motion = velocity == 0
          ? _policy.closeMotion
          : _policy.settleMotion(AttachSheetRelease.dismiss);
      await _moveTo(end, motion, velocity: velocity);
    }
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
    if (_morph case final morph? when !_speed.isInstant) {
      _$top.value = _collapsedTop;
      unawaited(_morphOut(morph));
    } else {
      _$top.value = _size.height;
      unawaited(_moveTo(_collapsedTop, _policy.openMotion));
    }
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

  /// The morph to run: the policy's, when the host gave the attach button's
  /// rect.
  AttachSheetMorph? get _morph =>
      widget.opening.anchor == null ? null : _policy.morph;

  Future<void> _morphOut(AttachSheetMorph morph) async {
    setState(() => _morphing = true);
    _$morphPosition.value = 0;
    _$morphBounds.value = 0;
    _$morphCorners.value = 0;
    _$morphContent.value = 0;
    final corners = morph.openCorners.withSpeed(_speed);
    final content = morph.openContent.withSpeed(_speed);
    unawaited(
      _$morphCorners.animateTo(
        1,
        duration: corners.duration,
        curve: corners.curve,
      ),
    );
    unawaited(
      _$morphContent.animateTo(
        1,
        duration: content.duration,
        curve: content.curve,
      ),
    );
    await _settle([
      _$morphPosition.animateWith(
        SpringSimulation(morph.openPosition, 0, 1, morph.openPositionVelocity),
      ),
      _$morphBounds.animateWith(SpringSimulation(morph.openBounds, 0, 1, 0)),
    ]);
    if (!mounted || _closing) return;
    _$morphPosition.value = 1;
    _$morphBounds.value = 1;
    _$morphCorners.value = 1;
    setState(() => _morphing = false);
  }

  /// Shrinks the sheet back into the attach button from wherever its
  /// channels are, keeping their velocities, so a close that interrupts the
  /// open reverses it.
  Future<void> _morphBack(AttachSheetMorph morph) async {
    setState(() => _morphing = true);
    final content = morph.closeContent.withSpeed(_speed);
    unawaited(
      _$morphContent.animateTo(
        0,
        duration: content.duration,
        curve: content.curve,
      ),
    );
    SpringSimulation back(AnimationController c, SpringDescription spring) =>
        SpringSimulation(spring, c.value, 0, c.velocity);
    await _settle([
      _$morphPosition.animateWith(back(_$morphPosition, morph.closePosition)),
      _$morphBounds.animateWith(back(_$morphBounds, morph.closeBounds)),
      _$morphCorners.animateWith(back(_$morphCorners, morph.closeCorners)),
    ]);
  }

  /// Waits for every ticker; a cancelled one counts as settled.
  static Future<void> _settle(List<TickerFuture> tickers) async {
    for (final ticker in tickers) {
      try {
        await ticker.orCancel;
      } on TickerCanceled {
        continue;
      }
    }
  }

  /// [target] as the morph draws it now: between the attach button's rect
  /// and [target] by the position and bounds channels.
  Rect _morphed(Rect target) {
    final anchor = widget.opening.anchor;
    if (!_morphing || anchor == null) return target;
    final center = Offset.lerp(
      anchor.center,
      target.center,
      _$morphPosition.value,
    )!;
    final width = lerpDouble(anchor.width, target.width, _$morphBounds.value)!;
    final height = lerpDouble(
      anchor.height,
      target.height,
      _$morphBounds.value,
    )!;
    return Rect.fromCenter(
      center: center,
      width: math.max(0, width),
      height: math.max(0, height),
    );
  }

  /// [radius] as the morph draws it now: from the button's round end.
  double _morphedRadius(double radius) {
    final anchor = widget.opening.anchor;
    if (!_morphing || anchor == null) return radius;
    return math.max(
      0,
      lerpDouble(anchor.shortestSide / 2, radius, _$morphCorners.value)!,
    );
  }

  double get _contentOpacity =>
      _morphing ? _$morphContent.value.clamp(0.0, 1.0) : 1;

  Listenable get _morphChannels => Listenable.merge([
    _$morphPosition,
    _$morphBounds,
    _$morphCorners,
    _$morphContent,
  ]);

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
      !_morphing &&
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
        fling: ViewportSplineFlingSimulation(velocity: velocity),
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
      _collapsedTop = _$restTop ?? _policy.collapsedTop(_size, padding);
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
      animation: Listenable.merge([_$top, _$header, _morphChannels]),
      child: content,
      builder: (context, content) {
        final top = _shownTop;
        final pinned = _$header.value;
        final target = Rect.fromLTWH(
          0,
          top,
          _size.width,
          math.max(0, _size.height - top),
        );
        final rect = _morphed(target);
        // Below its rest (pulled down, closing) the sheet keeps its content
        // at the resting height and clips it, rather than squeezing it.
        final contentHeight = math.max(
          target.height,
          math.max<double>(0, _size.height - _collapsedTop),
        );
        final corner = _morphedRadius(squares ? radius * (1 - pinned) : radius);
        // Growing out of the button the sheet is round at every corner;
        // at rest only its top corners are.
        final radii = _morphing
            ? BorderRadius.circular(corner)
            : BorderRadius.vertical(top: Radius.circular(corner));
        return Positioned.fromRect(
          key: const ValueKey('attach-sheet'),
          rect: rect,
          child: ClipRRect(
            borderRadius: radii,
            child: ColoredBox(
              color: tokens.background,
              child: Stack(
                children: [
                  // The sheet starts below the status bar: its content
                  // takes no top inset. While it morphs the content keeps
                  // the sheet's size and fades in.
                  Positioned.fill(
                    child: Opacity(
                      opacity: _contentOpacity,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: target.width,
                        maxWidth: target.width,
                        minHeight: contentHeight,
                        maxHeight: contentHeight,
                        child: _ContentInsets(
                          barExtent: widget.bottomBar == null
                              ? null
                              : _$barExtent,
                          child: content!,
                        ),
                      ),
                    ),
                  ),
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
    animation: Listenable.merge([_$top, _morphChannels]),
    child: _MeasureHeight(extent: _$barExtent, child: bar),
    builder: (context, bar) => Positioned(
      key: const ValueKey('attach-sheet-bar'),
      left: 0,
      right: 0,
      bottom: 0,
      child: Opacity(
        opacity: _contentOpacity,
        child: Transform.translate(
          offset: Offset(0, math.max(0, _shownTop - _collapsedTop)),
          child: bar,
        ),
      ),
    ),
  );

  Widget _cardLayer(Rect card, AttachTokens tokens) {
    final radius = _policy.cornerRadius;
    return AnimatedBuilder(
      animation: Listenable.merge([_$top, _morphChannels]),
      child: PrimaryScrollController(
        controller: _$scroll,
        child: Builder(builder: (context) => widget.builder(context, _$scroll)),
      ),
      builder: (context, content) {
        // The card rises from the bottom edge on the sheet's motion; its
        // contents fade with the distance left.
        final travel = (_size.height - card.top).clamp(1, double.infinity);
        final risen = (1 - (_shownTop - card.top) / travel).clamp(0.0, 1.0);
        final rect = _morphed(card.shift(Offset(0, _shownTop - card.top)));
        final corner = _morphedRadius(radius);
        return Positioned.fromRect(
          key: const ValueKey('attach-sheet-card'),
          rect: rect,
          child: Opacity(
            opacity: _morphing ? 1 : risen,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(corner),
                boxShadow: const [
                  BoxShadow(color: Color(0x4D000000), blurRadius: 80),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(corner),
                child: ColoredBox(
                  color: tokens.background,
                  child: Opacity(
                    opacity: _contentOpacity,
                    child: OverflowBox(
                      minWidth: card.width,
                      maxWidth: card.width,
                      minHeight: card.height,
                      maxHeight: card.height,
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The sheet's content below the status bar: no top padding, and, under a
/// bottom bar, the bar's height as the bottom padding (it includes the safe
/// area), so a page's scrollable keeps its last row clear of the floating
/// bar as the bar grows and shrinks.
class _ContentInsets extends StatelessWidget {
  const _ContentInsets({required this.barExtent, required this.child});

  final ValueListenable<double>? barExtent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bar = barExtent;
    if (bar == null) {
      return MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: child,
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: bar,
      child: child,
      builder: (context, extent, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(top: 0, bottom: extent),
          ),
          child: child!,
        );
      },
    );
  }
}

/// Reports its child's height to [extent] after each layout that changes
/// it.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.extent, super.child});

  final ValueNotifier<double> extent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(extent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) => renderObject.extent = extent;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.extent);

  ValueNotifier<double> extent;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == extent.value) return;
    // Told after the frame: listeners rebuild, which a layout may not.
    final target = extent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Gone with the sheet meanwhile: its notifier went too.
      if (attached) target.value = height;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

/// The page's fling, the platform list's spline deceleration, carried by
/// the sheet's top from [start] and stopped at [min] (the top) or [max] (the
/// rest).
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
  final ViewportSplineFlingSimulation fling;

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

/// Pops the sheet's route with [outcome], and whatever a page pushed over it
/// (a viewer, a menu) first.
void _closeRoute(BuildContext context, AttachOutcome outcome) {
  final route = ModalRoute.of(context);
  final navigator = Navigator.of(context);
  if (route != null && !route.isCurrent) {
    navigator.popUntil((r) => identical(r, route));
  }
  navigator.pop(outcome);
}

/// The chrome bottom sheet opened by its content: the attach sheet runs its
/// own open and close (the springs to its rest and top, the morph out of
/// the attach button, its scrim's delayed dim), so the route shows and goes
/// at once, and the sheet places itself around the keyboard. The route's
/// root gives every page, the panel and the boxes over them the chrome text
/// style.
ChromeSheetRoute<AttachOutcome> _attachSheetRoute({
  required WidgetBuilder builder,
}) => ChromeSheetRoute<AttachOutcome>(
  builder: builder,
  opening: const ChromeSheetOpening.byContent(),
  barrierDismissible: false,
  avoidsKeyboard: false,
);
