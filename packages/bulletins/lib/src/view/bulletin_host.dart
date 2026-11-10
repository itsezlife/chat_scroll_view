import 'dart:async';
import 'dart:math' as math;

import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:bulletins/src/controller/bulletin_controller.dart';
import 'package:bulletins/src/policy/bulletin_policy.dart';
import 'package:bulletins/src/view/bulletin_builders.dart';
import 'package:bulletins/src/view/bulletin_card.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Speaks [message] to assistive technology for the view at [context].
typedef BulletinAnnounce = void Function(BuildContext context, String message);

/// The **bulletin host**: mounts a [BulletinController] over a surface's
/// content.
///
/// Lays the bulletin in the slot out in the area [obstruction] leaves,
/// according to the controller's policy (placement, margin, width, clipping);
/// plays its enter and exit (a replaced bulletin finishes leaving while the
/// new one enters) and reports the enter finished to its handle, which starts
/// its timer; runs the policy's gestures (a press holds the timer, a
/// horizontal swipe throws it away); announces it; and closes it as
/// [BulletinExit.surfaceGone] when it unmounts.
///
/// Requires a `ChromeThemeScope` and a `ChromeStringsScope` above it;
/// motion follows the enclosing `ChromeMotionScope`, and an instant speed
/// makes every transition a jump.
///
/// Pointer events outside the card reach [child].
class BulletinHost extends StatefulWidget {
  /// A host of [controller] over [child].
  const BulletinHost({
    required this.controller,
    required this.child,
    this.obstruction,
    this.tracksObstruction = false,
    this.builders = const BulletinBuilders(),
    this.announce,
    super.key,
  });

  /// The surface's slot.
  final BulletinController controller;

  /// The **bottom obstruction**: what covers the surface's edges (at the
  /// bottom the composer and its safe inset and the keyboard, at the top a
  /// bar). The bulletin stays inside what it leaves and follows it on the
  /// policy's follow spring. Null uses the `MediaQuery` view padding and,
  /// at the bottom, the keyboard inset.
  final ValueListenable<EdgeInsets>? obstruction;

  /// Whether the bulletin sits at [obstruction]'s value on the frame it
  /// changes instead of following it on the policy's follow spring.
  ///
  /// For an obstruction that already moves frame by frame, such as the
  /// inset a surface lays its own content out against while the keyboard or
  /// a panel slides: the bulletin then moves with that content rather than
  /// trailing it. False follows on the spring, which smooths an obstruction
  /// that jumps. Without an [obstruction] the `MediaQuery` fallback is
  /// tracked the same way when true.
  final bool tracksObstruction;

  /// How the card is drawn.
  final BulletinBuilders builders;

  /// Speaks a bulletin when it shows; null uses the platform accessibility
  /// service.
  final BulletinAnnounce? announce;

  /// The surface's content.
  final Widget child;

  @override
  State<BulletinHost> createState() => _BulletinHostState();
}

class _BulletinHostState extends State<BulletinHost>
    with TickerProviderStateMixin {
  final List<_Entry> _$entries = [];
  late final AnimationController _$follow = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  EdgeInsets _$followFrom = EdgeInsets.zero;
  EdgeInsets? _$followTo;

  BulletinPolicy get _policy => widget.controller.policy;

  ChromeMotionData get _motion => ChromeMotionScope.of(context);

  /// The insets the bulletin is laid out in this frame: the obstruction
  /// itself when tracked, else where the follow spring has come to.
  EdgeInsets get _insets => widget.tracksObstruction
      ? _targetInsets()
      : EdgeInsets.lerp(
          _$followFrom,
          _$followTo ?? EdgeInsets.zero,
          _$follow.value,
        )!;

  @override
  void initState() {
    super.initState();
    widget.controller.current.addListener(_onCurrent);
    widget.obstruction?.addListener(_onObstruction);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followTo(_targetInsets(), jump: _$followTo == null);
    // A bulletin shown before the host mounted enters now.
    if (_$entries.isEmpty) _onCurrent();
  }

  @override
  void didUpdateWidget(BulletinHost old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.current.removeListener(_onCurrent);
      old.controller.detach();
      widget.controller.current.addListener(_onCurrent);
      _onCurrent();
    }
    if (!identical(old.obstruction, widget.obstruction)) {
      old.obstruction?.removeListener(_onObstruction);
      widget.obstruction?.addListener(_onObstruction);
      _onObstruction();
    }
  }

  @override
  void dispose() {
    widget.controller.current.removeListener(_onCurrent);
    widget.obstruction?.removeListener(_onObstruction);
    widget.controller.detach();
    for (final entry in _$entries) {
      entry.dispose();
    }
    _$follow.dispose();
    super.dispose();
  }

  // --- Obstruction ---

  EdgeInsets _targetInsets() {
    if (widget.obstruction case final obstruction?) return obstruction.value;
    final padding = MediaQuery.viewPaddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return padding.copyWith(bottom: math.max(padding.bottom, keyboard));
  }

  void _onObstruction() => _followTo(_targetInsets());

  void _followTo(EdgeInsets target, {bool jump = false}) {
    if (target == _$followTo) return;
    final spring = _policy.followSpring;
    if (jump ||
        widget.tracksObstruction ||
        spring == null ||
        _motion.speed.isInstant) {
      _$followFrom = target;
      _$followTo = target;
      _$follow.value = 1;
      return;
    }
    _$followFrom = _insets;
    _$followTo = target;
    _$follow.value = 0;
    // A spring settles within its tolerance of the target; land on it.
    unawaited(
      _$follow
          .animateWith(SpringSimulation(spring, 0, 1, 0))
          .orCancel
          .then((_) => _$follow.value = 1, onError: (_) {}),
    );
  }

  // --- Slot ---

  void _onCurrent() {
    for (final entry in _$entries) {
      if (entry.handle.isClosed && !entry.isLeaving) _leave(entry);
    }
    final handle = widget.controller.current.value;
    if (handle == null || _$entries.any((e) => identical(e.handle, handle))) {
      return;
    }
    final entry = _Entry(handle, this);
    setState(() => _$entries.add(entry));
    _enter(entry);
    final message = handle.bulletin.spokenLabel;
    (widget.announce ?? _systemAnnounce)(context, message);
  }

  static void _systemAnnounce(BuildContext context, String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        message,
        Directionality.of(context),
      ),
    );
  }

  void _enter(_Entry entry) {
    final presence = entry.presence;
    if (_motion.speed.isInstant) {
      presence.value = 1;
      entry.handle.markEntered();
      return;
    }
    final TickerFuture run;
    switch (_policy.transitionAt(entry.placementIn(_policy))) {
      case BulletinTransition$Slide(:final spring):
        run = presence.animateWith(SpringSimulation(spring, 0, 1, 0));
      case BulletinTransition$TimedSlide(enter: final given) ||
          BulletinTransition$Fade(enter: final given?):
        final spec = given.withSpeed(_motion.speed);
        run = presence.animateTo(1, duration: spec.duration, curve: spec.curve);
      case BulletinTransition$FadeScale(:final enter?):
        // Presence runs as linear time; each channel reads its own curve.
        run = presence.animateTo(
          1,
          duration: _motion.speed.scale(enter.length),
        );
      case BulletinTransition$FadeScale() || BulletinTransition$Fade():
        final spec = _motion.specOf(MotionRole.bulletinShow);
        run = presence.animateTo(1, duration: spec.duration, curve: spec.curve);
    }
    unawaited(
      run.orCancel.then((_) {
        // A spring settles within its tolerance of the target; land on it.
        entry.presence.value = 1;
        entry.handle.markEntered();
      }, onError: (_) {}),
    );
  }

  void _leave(_Entry entry) {
    entry.isLeaving = true;
    if (_motion.speed.isInstant) {
      _remove(entry);
      return;
    }
    final TickerFuture run;
    if (entry.swipeDirection != 0) {
      final width = entry.width ?? 400;
      run = switch (entry.flingVelocity) {
        // A fling springs towards twice the width from the release speed
        // and is gone once past the width.
        final velocity? => entry.flingDrag(
          _PastLimit(
            SpringSimulation(
              _flingSpring,
              entry.drag.value,
              entry.swipeDirection * width * 2,
              velocity,
            ),
            width,
          ),
        ),
        // A drag released past the threshold accelerates to the width in
        // 200 ms.
        null => entry.animateDragTo(
          entry.swipeDirection * width,
          const Duration(milliseconds: 200),
          Curves.easeInQuad,
        ),
      };
    } else {
      switch (_policy.transitionAt(entry.placementIn(_policy))) {
        case BulletinTransition$Slide(:final spring):
          run = entry.presence.animateWith(
            SpringSimulation(spring, entry.presence.value, 0, 0),
          );
        case BulletinTransition$TimedSlide(exit: final given) ||
            BulletinTransition$Fade(exit: final given?):
          final spec = given.withSpeed(_motion.speed);
          run = entry.presence.animateTo(
            0,
            duration: spec.duration,
            curve: spec.curve,
          );
        case final BulletinTransition$FadeScale transition &&
            BulletinTransition$FadeScale(:final exit?):
          // The exit starts from what is drawn now, which mid-enter is not
          // the resting card; without this the card would jump to the exit
          // curve's start.
          final from = _fadeScaleLook(entry, transition);
          entry
            ..leaveFrom = from
            ..presence.value = 1;
          run = entry.presence.animateTo(
            0,
            duration: _motion.speed.scale(exit.opacity.duration),
          );
        case BulletinTransition$FadeScale() || BulletinTransition$Fade():
          final spec = _motion.specOf(MotionRole.bulletinHide);
          run = entry.presence.animateTo(
            0,
            duration: spec.duration,
            curve: spec.curve,
          );
      }
    }
    unawaited(run.orCancel.then((_) => _remove(entry), onError: (_) {}));
  }

  void _remove(_Entry entry) {
    if (!mounted) return;
    setState(() => _$entries.remove(entry));
    entry.dispose();
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    final view = (
      tokens: ChromeThemeScope.bulletinOf(context),
      strings: ChromeStringsScope.bulletinOf(context),
    );
    return Stack(
      children: [
        widget.child,
        if (_$entries.isNotEmpty)
          Positioned.fill(
            child: AnimatedBuilder(
              // A tracked obstruction rebuilds the padding on the frame it
              // changes, in the build that precedes the content's layout.
              animation: Listenable.merge([_$follow, ?widget.obstruction]),
              builder: (context, child) => Padding(
                padding: _insets,
                child: policy.clipsAtObstruction
                    ? ClipRect(child: child)
                    : child,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final entry in _$entries)
                    _EntryView(
                      key: entry.key,
                      entry: entry,
                      policy: policy,
                      builders: widget.builders,
                      view: BulletinView(
                        handle: entry.handle,
                        policy: policy,
                        tokens: view.tokens,
                        strings: view.strings,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One bulletin on the host: its presence (0 hidden, 1 shown; a spring may
/// pass 1), its horizontal drag, and whether it is leaving.
final class _Entry {
  _Entry(this.handle, TickerProvider vsync)
    : presence = AnimationController.unbounded(vsync: vsync),
      _drag = AnimationController.unbounded(vsync: vsync);

  final BulletinHandle handle;
  final AnimationController presence;
  final AnimationController _drag;
  final GlobalKey key = GlobalKey();
  bool isLeaving = false;
  bool isPressed = false;

  /// -1 or 1 once thrown away by a swipe, else 0.
  double swipeDirection = 0;

  /// The release speed when a fling threw it away; null for a drag past the
  /// threshold.
  double? flingVelocity;

  /// The card's width at the last layout, for the swipe threshold.
  double? width;

  /// Whether the card is narrower than the area it sits in (a wide window),
  /// so a drag fades it as well as moving it.
  bool fadesOnDrag = false;

  /// Where the card sits under [policy]: the bulletin's own placement, or
  /// the policy's.
  BulletinPlacement placementIn(BulletinPolicy policy) =>
      handle.bulletin.placement ?? policy.placement;

  /// The look a fade-scale exit with its own timing started from.
  ({double opacity, double scale})? leaveFrom;

  Animation<double> get drag => _drag;

  TickerFuture flingDrag(Simulation simulation) =>
      _drag.animateWith(simulation);

  set dragOffset(double value) {
    _drag
      ..stop()
      ..value = value;
  }

  TickerFuture animateDragTo(double target, Duration duration, Curve curve) =>
      _drag.animateTo(target, duration: duration, curve: curve);

  void dispose() {
    presence.dispose();
    _drag.dispose();
  }
}

class _EntryView extends StatefulWidget {
  const _EntryView({
    required this.entry,
    required this.policy,
    required this.builders,
    required this.view,
    super.key,
  });

  final _Entry entry;
  final BulletinPolicy policy;
  final BulletinBuilders builders;
  final BulletinView view;

  @override
  State<_EntryView> createState() => _EntryViewState();
}

class _EntryViewState extends State<_EntryView> {
  _Entry get _entry => widget.entry;

  BulletinPlacement get _placement => _entry.placementIn(widget.policy);

  /// Whether the card has nothing to press: no action, no body tap, no link.
  bool get _isInert {
    final bulletin = widget.view.bulletin;
    return bulletin.action == null &&
        bulletin.onTap == null &&
        bulletin.links.isEmpty;
  }

  void _press(bool down) {
    if (_entry.isLeaving) return;
    if (widget.policy.pauseOnPress) {
      down ? _entry.handle.pause() : _entry.handle.resume();
    }
    if (widget.policy.pressScale != 1) {
      setState(() => _entry.isPressed = down);
    }
  }

  /// Whether a drag may move the card: only once it has entered, since only
  /// a bulletin that can hide is swiped, and it can hide from the end of its
  /// enter.
  bool get _canDrag => _entry.handle.isEntered && !_entry.isLeaving;

  void _dragUpdate(DragUpdateDetails details) {
    if (!_canDrag) return;
    _entry.dragOffset = _entry.drag.value + details.delta.dx;
  }

  void _dragEnd(DragEndDetails details) {
    if (!_canDrag) return;
    final policy = widget.policy;
    final dx = _entry.drag.value;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final width = _entry.width ?? 0;
    final thrown =
        dx.abs() > width * policy.swipeDismissFraction ||
        velocity.abs() > policy.swipeFlingVelocity;
    if (thrown) {
      final flung = velocity.abs() > policy.swipeFlingVelocity;
      final direction = (flung ? velocity : dx).sign;
      _entry
        ..swipeDirection = direction == 0 ? 1 : direction
        ..flingVelocity = flung ? velocity : null;
      _entry.handle.swipeAway();
    } else {
      // Back in 200 ms on the platform's default accelerate-decelerate.
      unawaited(
        _entry
            .animateDragTo(
              0,
              const Duration(milliseconds: 200),
              Curves.easeInOutSine,
            )
            .orCancel
            .then((_) {}, onError: (_) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy;
    final placement = _placement;
    final motion = ChromeMotionScope.of(context);
    final still = BulletinCard(view: widget.view, builders: widget.builders);
    final minWidth = policy.minWidth;
    Widget card = LayoutBuilder(
      builder: (context, constraints) {
        _entry.width = constraints.maxWidth;
        return switch (minWidth) {
          null => still,
          // A card as wide as its content: the content's widest line, held
          // between the policy's bounds and the room the surface leaves.
          final minWidth => ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: math.min(minWidth, constraints.maxWidth),
            ),
            child: IntrinsicWidth(child: still),
          ),
        };
      },
    );
    final bulletin = widget.view.bulletin;
    // Only a tappable card shows its press. It shrinks in 80 ms and returns
    // in 350 ms with an overshoot of tension 1.5.
    final pressed = _entry.isPressed && bulletin.onTap != null;
    card = AnimatedScale(
      scale: pressed ? policy.pressScale : 1,
      duration: motion.speed.isInstant
          ? Duration.zero
          : Duration(milliseconds: pressed ? 80 : 350),
      curve: pressed ? Curves.easeInOutSine : const _Overshoot(1.5),
      child: card,
    );
    card = Listener(
      onPointerDown: (_) => _press(true),
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: bulletin.onTap,
        onHorizontalDragUpdate: policy.swipeToDismiss ? _dragUpdate : null,
        onHorizontalDragEnd: policy.swipeToDismiss ? _dragEnd : null,
        child: card,
      ),
    );
    card = AnimatedBuilder(
      animation: Listenable.merge([_entry.presence, _entry.drag]),
      child: card,
      builder: (context, child) {
        final dx = _entry.drag.value;
        final width = _entry.width ?? 0;
        Widget moved = Transform.translate(offset: Offset(dx, 0), child: child);
        if (_entry.fadesOnDrag && dx != 0 && width > 0) {
          moved = Opacity(
            opacity: (1 - dx.abs() / width).clamp(0.0, 1.0),
            child: moved,
          );
        }
        return _transition(_entry.presence.value, placement, moved);
      },
    );
    final maxWidth = policy.maxWidth ?? double.infinity;
    final placed = Align(
      alignment: switch (placement) {
        BulletinPlacement.bottom => Alignment.bottomCenter,
        BulletinPlacement.top => Alignment.topCenter,
        BulletinPlacement.center => Alignment.center,
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: switch (minWidth) {
          null => SizedBox(width: double.infinity, child: card),
          _ => card,
        },
      ),
    );
    return IgnorePointer(
      ignoring: _entry.isLeaving || (policy.passesThroughWhenInert && _isInert),
      child: Padding(
        padding: policy.margin,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _entry.fadesOnDrag =
                minWidth != null || constraints.maxWidth > maxWidth;
            return placed;
          },
        ),
      ),
    );
  }

  Widget _transition(double p, BulletinPlacement placement, Widget child) {
    final margin = widget.policy.margin;
    final transition = widget.policy.transitionAt(placement);
    // Off by its own height and a margin past the edge it sits on. The
    // spring slide goes both vertical margins: the offset is the height of the
    // card and the padding around it, so the hidden card sits a margin past
    // the edge it clips at.
    final beyond = switch ((transition, placement)) {
      (BulletinTransition$Slide(), _) => margin.vertical,
      (_, BulletinPlacement.top) => margin.top,
      (_, _) => margin.bottom,
    };
    return switch (transition) {
      BulletinTransition$Slide() ||
      BulletinTransition$TimedSlide() => switch (placement) {
        BulletinPlacement.top => Transform.translate(
          offset: Offset(0, -(1 - p) * beyond),
          child: FractionalTranslation(
            translation: Offset(0, -(1 - p)),
            child: child,
          ),
        ),
        BulletinPlacement.bottom ||
        BulletinPlacement.center => Transform.translate(
          offset: Offset(0, (1 - p) * beyond),
          child: FractionalTranslation(
            translation: Offset(0, 1 - p),
            child: child,
          ),
        ),
      },
      final BulletinTransition$FadeScale transition => switch (_fadeScaleLook(
        _entry,
        transition,
      )) {
        (:final opacity, :final scale) => Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        ),
      },
      BulletinTransition$Fade() => Opacity(
        opacity: p.clamp(0, 1),
        child: child,
      ),
    };
  }
}

// --- Swipe and press motion ---

/// The spring a flung card leaves on: stiffness 100, no bounce.
final SpringDescription _flingSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 100,
);

/// [simulation], done once its position passes [limit] either way: the fling
/// spring is cancelled past the card's width, long before the spring would
/// settle at twice the width.
final class _PastLimit extends Simulation {
  _PastLimit(this.simulation, this.limit);

  final Simulation simulation;
  final double limit;

  @override
  double x(double time) => simulation.x(time);

  @override
  double dx(double time) => simulation.dx(time);

  @override
  bool isDone(double time) => x(time).abs() >= limit || simulation.isDone(time);
}

/// Android's `OvershootInterpolator` of [tension]: passes 1 and settles back.
final class _Overshoot extends Curve {
  const _Overshoot(this.tension);

  final double tension;

  @override
  double transformInternal(double t) {
    final s = t - 1;
    return s * s * ((tension + 1) * s + tension) + 1;
  }
}

// --- Fade and scale ---

/// The opacity and scale [entry] is drawn with under [transition].
///
/// Without split timing the presence is the eased progress of both
/// channels. With it, the presence is linear time and each channel reads its
/// own duration and curve: entering, 0 to 1 over the longer channel;
/// leaving, 1 to 0 over the fade, from the look the exit started at.
({double opacity, double scale}) _fadeScaleLook(
  _Entry entry,
  BulletinTransition$FadeScale transition,
) {
  final p = entry.presence.value;
  final rest = transition.fromScale;
  switch ((transition.enter, transition.exit, entry.leaveFrom)) {
    case (_, final exit?, final from?):
      final elapsed = 1 - p;
      final total = exit.opacity.duration;
      final fade = _channel(exit.opacity, elapsed, total);
      final shrink = _channel(exit.scale, elapsed, total);
      return (
        opacity: from.opacity * (1 - fade),
        scale: from.scale + (rest - from.scale) * shrink,
      );
    case (final enter?, _, null):
      final total = enter.length;
      return (
        opacity: _channel(enter.opacity, p, total),
        scale: rest + (1 - rest) * _channel(enter.scale, p, total),
      );
    case _:
      return (opacity: p.clamp(0, 1), scale: rest + (1 - rest) * p);
  }
}

/// How far [spec]'s channel has come, by its curve, when [elapsed] of
/// [total] has passed.
double _channel(MotionSpec spec, double elapsed, Duration total) {
  if (spec.duration <= Duration.zero) return 1;
  final t = elapsed * total.inMicroseconds / spec.duration.inMicroseconds;
  return spec.curve.transform(t.clamp(0, 1));
}

extension on BulletinFadeScaleMotion {
  /// The time both channels take together.
  Duration get length =>
      opacity.duration > scale.duration ? opacity.duration : scale.duration;
}
