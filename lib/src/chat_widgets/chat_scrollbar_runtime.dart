import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_activity.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Where the press that started a grab landed.
@internal
enum ChatScrollbarPress {
  /// On the thumb, or on a touch target around it: the grab keeps the
  /// pointer's offset from the thumb's top, and nothing moves until the
  /// pointer does.
  thumb,

  /// On the track beside the thumb, under
  /// [ChatScrollbarTrackPress.centerThumb]: the thumb centres on the
  /// pointer at once and the grab continues from there.
  track,
}

/// Where a grab puts the thumb: [progress] in `[0, 1]` along the track, and
/// [spanShare], the visible band's share of the known span frozen when the
/// grab started. The render object inverts its thumb-progress mapping with
/// both to find the band position under the pointer.
typedef ChatScrollbarGrabPosition = ({double progress, double spanShare});

/// Per-viewport scrollbar state: the frame resolved at the last paint, the
/// thumb's motion — at rest, grabbed by a pointer, or settling after a
/// grab — which presses and hovers the [grab] rules claim, and the
/// scrollbar's visibility.
///
/// Knows nothing of the data source, the controller, anchor math, or which
/// other pointers are down — the render object computes the band's thumb
/// progress and span share and hands them to [resolve], maps a
/// [ChatScrollbarGrabPosition] back to a band position, offers
/// [tryStartGrab] only fresh presses, adds [stripTarget] to its hit tests,
/// and reports list motion to the visibility calls. Paint and grab
/// hit-testing both read [frame], so a press lands on exactly what was last
/// painted; between a layout and its paint no pointer event is dispatched,
/// so [frame] is never staler than the pixels on screen.
///
/// ## Grab targets
///
/// Measured on [frame] with the preset's [grab] targets; both reach at
/// least to the track's far edge from the trailing side, so a wide painter
/// stays grabbable and a thin one never shrinks them:
///
/// - **Strip** (mouse and trackpad) — [ChatScrollbarGrab$Targets.stripWidth]
///   in from the trailing edge over the track's vertical span, live at any
///   visibility. [stripContains] tests it; [stripTarget] carries its hover
///   and cursor.
/// - **Touch target** (touch, stylus, unknown kinds) —
///   [ChatScrollbarGrab$Targets.touchTargetWidth] in from the trailing edge,
///   over the thumb grown to [ChatScrollbarGrab$Targets.touchTargetMinHeight],
///   live only while [visibility] is above `0`.
///
/// Under [ChatScrollbarGrab$None] there is neither: [stripContains] is
/// always `false` and [tryStartGrab] declines every press.
///
/// ## Frame and thumb motion
///
/// - **Rest** — the thumb shows the band: position and length from
///   [resolve]'s progress and span share.
/// - **Grab** — the thumb follows the pointer, keeping the offset at which
///   the press met it. Its length and the span share are frozen at the
///   press, so the travel the pointer moves through, and so the
///   pointer-to-band mapping, stay fixed for the whole grab.
/// - **Settle** — after [endGrab], the thumb eases from where the pointer
///   left it to the band's thumb over [settleDuration] along [settleCurve],
///   advanced by [tick]. The band keeps moving the target while it
///   settles.
///
/// ## Hover and grab factors
///
/// The frame's [ChatScrollbarFrame.hoverFactor] and
/// [ChatScrollbarFrame.grabFactor] ease toward `1` while the strip is
/// hovered or a grab is held, and toward `0` after: over the visibility's
/// fade-in when rising and its fade-out when falling, along its curve (the
/// settle's 250 ms [Curves.easeOut] under always). Each ease starts on the
/// first [tick] after the change, so the first frame still shows the old
/// value; a zero fade jumps straight to the target. A reversal mid-ease
/// runs from the current value.
///
/// The settle and the factors are not `AnimationController`s: the owner is
/// a render object with no `TickerProvider`; the render object's own ticker
/// drives them through [tick] while [isAnimating].
///
/// ## Visibility
///
/// [visibility] follows the [ChatScrollbarVisibility] handed to
/// [configureVisibility]: constant `1` for always, a
/// [ChatScrollActivityClock] of its own for auto-hide — never the viewport's
/// scroll-activity clock, so nothing that pins scroll activity reaches it.
/// Three holders keep an auto-hide clock held, and none releases another's
/// hold:
///
/// - **List motion** — [holdVisibility] while a tick moves the list,
///   [releaseVisibility] once nothing does.
/// - **The grab** — from [tryStartGrab] until [endGrab] or [reset].
/// - **Strip hover** — while a mouse rests on the strip, from
///   [stripTarget]'s enter to its exit or [reset].
///
/// [pulseVisibility] reports a discrete move and is ignored while a grab
/// holds: the grab's own jumps are part of the grab, and its release starts
/// the idle delay, not the navigation delay.
///
/// Under [ChatScrollbarVisibility$AutoHide.followsPointer], the owner also
/// adds [viewportTarget] to its hit tests: a mouse entering the viewport
/// pulses with the idle delay unless something already holds, and leaving
/// it drops the strip hover and starts the fade-out at once unless another
/// holder still holds.
@internal
final class ChatScrollbarRuntime {
  /// A runtime that calls [onChanged] whenever what the next frame shows
  /// changes outside a paint: an auto-hide fade moves [visibility] (inside
  /// ticker frames), or a mouse enters or leaves the strip (inside pointer
  /// dispatch or the mouse tracker's post-frame update). The owner
  /// repaints, and keeps its ticker running while [isAnimating].
  ChatScrollbarRuntime({required VoidCallback onChanged})
    : _onChanged = onChanged;

  /// The preset's grab rules, read by every strip and touch-target test.
  /// A change reaches a resting mouse at the mouse tracker's next update.
  ChatScrollbarGrab grab = const ChatScrollbarGrab();

  /// Settle and factor timing under [ChatScrollbarVisibility.always], which
  /// has no fade to take it from.
  static const Duration _alwaysFadeDuration = Duration(milliseconds: 250);
  static const Curve _alwaysCurve = Curves.easeOut;

  // --- Frame and thumb motion ------------------------------------------------

  ChatScrollbarFrame? _frame;
  double _viewportWidth = 0;
  double _spanShare = 0;
  _ThumbMotion? _motion;

  /// The frame resolved at the last paint, or `null` when no scrollbar was
  /// painted: no preset painter, nothing to scroll, or overlay mode.
  ChatScrollbarFrame? get frame => _frame;

  /// Whether a pointer currently holds a grab.
  bool get isGrabbing => switch (_motion) {
    _Grab() => true,
    _ => false,
  };

  /// Whether the thumb is easing back to the band after a grab.
  bool get isSettling => switch (_motion) {
    _Settle() => true,
    _ => false,
  };

  /// Whether the settle or a hover or grab factor is still easing; the
  /// render object keeps its ticker alive and calls [tick] until it is not.
  bool get isAnimating =>
      isSettling || _hoverFactor.isEasing || _grabFactor.isEasing;

  /// Resolves this paint's frame for [painter] and stores it as [frame].
  ///
  /// [progress] in `[0, 1]` places the band's thumb along the track;
  /// [thumbFraction] is the visible band's share of the known span. At rest
  /// the thumb shows exactly that. While grabbed it shows the pointer's
  /// position with the frozen length; while settling, a blend of the two.
  /// The frame carries the current [visibility]; it is resolved, and grab
  /// hit-testing reads it, even at visibility `0`, when the owner skips the
  /// painter. Returns `null` (and clears [frame]) when the track has no
  /// length or the thumb, floored at the painter's minimum, would leave
  /// nothing to travel.
  ChatScrollbarFrame? resolve({
    required ChatScrollbarPainter painter,
    required Size size,
    required double topInset,
    required double bottomInset,
    required TextDirection textDirection,
    required double progress,
    required double thumbFraction,
  }) {
    final margin = painter.mainAxisMargin;
    final trackTop = topInset + margin;
    final trackBottom = size.height - bottomInset - margin;
    final trackLength = trackBottom - trackTop;
    final bandLength = math.min(
      math.max(trackLength * thumbFraction, painter.minThumbLength),
      trackLength,
    );
    _spanShare = thumbFraction;
    final bandOffset = (trackLength - bandLength) * progress.clamp(0.0, 1.0);
    final (thumbLength, thumbOffset) = switch (_motion) {
      null => (bandLength, bandOffset),
      final _Grab grab => (
        grab.lengthOn(trackLength),
        grab.offsetOn(trackTop, trackLength),
      ),
      final _Settle settle => (
        lerpDouble(settle.fromLength, bandLength, settle.eased)!,
        lerpDouble(settle.fromOffset, bandOffset, settle.eased)!,
      ),
    };
    if (trackLength <= 0 || trackLength - thumbLength <= 0) {
      clear();
      return null;
    }

    final thickness = painter.trackThickness;
    final (left, right) = switch (textDirection) {
      TextDirection.ltr => (
        size.width - painter.crossAxisMargin - thickness,
        size.width - painter.crossAxisMargin,
      ),
      TextDirection.rtl => (
        painter.crossAxisMargin,
        painter.crossAxisMargin + thickness,
      ),
    };
    final thumbTop =
        trackTop + thumbOffset.clamp(0.0, trackLength - thumbLength);
    _viewportWidth = size.width;
    return _frame = ChatScrollbarFrame(
      trackRect: Rect.fromLTRB(left, trackTop, right, trackBottom),
      thumbRect: Rect.fromLTRB(left, thumbTop, right, thumbTop + thumbLength),
      textDirection: textDirection,
      visibility: visibility,
      hoverFactor: _hoverFactor.value,
      grabFactor: _grabFactor.value,
    );
  }

  /// Drops [frame] and any settle — with no scrollbar painted there is
  /// nothing to ease. A grab survives: its pointer stays owned until it
  /// lifts.
  void clear() {
    _frame = null;
    if (isSettling) _motion = null;
  }

  /// Drops [frame], all motion (a grab included), and the visibility state:
  /// the motion and grab holds are forgotten and an auto-hide clock is
  /// disposed, its pending hide cancelled. For a render object leaving the
  /// tree, where the grabbing pointer's remaining events never arrive, and
  /// whose ticker goes with it: the grab factor drops to `0` and the hover
  /// factor jumps to where the hover is. Strip hover survives: the mouse
  /// tracker still reports its exit, so a pointer resting on the strip
  /// across a same-frame re-parent keeps holding. The owner calls
  /// [configureVisibility] again on re-attach, which starts auto-hide
  /// hidden unless the hover holds.
  void reset() {
    _frame = null;
    _motion = null;
    _motionHeld = false;
    _grabFactor.snap(0);
    _hoverFactor.snap(_hovered ? 1 : 0);
    configureVisibility(null);
  }

  // --- Grab targets ----------------------------------------------------------

  /// Whether [dx] lies within [width] of [frame]'s trailing edge, or between
  /// that edge and the track's far side when the track reaches further in.
  /// Inclusive.
  bool _nearTrailingEdge(ChatScrollbarFrame frame, double dx, double width) {
    final track = frame.trackRect;
    return switch (frame.textDirection) {
      TextDirection.ltr => dx >= math.min(_viewportWidth - width, track.left),
      TextDirection.rtl => dx <= math.max(width, track.right),
    };
  }

  /// Whether a mouse or trackpad pointer at viewport-local [local] is over
  /// the strip of the last resolved [frame] — at any visibility, `false`
  /// with no frame or under [ChatScrollbarGrab$None]. Bounds are inclusive;
  /// vertically the strip spans the track.
  bool stripContains(Offset local) => switch ((_frame, grab)) {
    (final frame?, final ChatScrollbarGrab$Targets targets) => _stripContains(
      frame,
      targets,
      local,
    ),
    _ => false,
  };

  bool _stripContains(
    ChatScrollbarFrame frame,
    ChatScrollbarGrab$Targets targets,
    Offset local,
  ) {
    final track = frame.trackRect;
    return _nearTrailingEdge(frame, local.dx, targets.stripWidth) &&
        local.dy >= track.top &&
        local.dy <= track.bottom;
  }

  /// Whether a touch at [local] lands on [frame]'s touch target: the thumb
  /// grown symmetrically to [ChatScrollbarGrab$Targets.touchTargetMinHeight],
  /// which may reach past the track's ends. Bounds are inclusive.
  bool _touchTargetContains(
    ChatScrollbarFrame frame,
    ChatScrollbarGrab$Targets targets,
    Offset local,
  ) {
    final thumb = frame.thumbRect;
    final grow = math.max(0, targets.touchTargetMinHeight - thumb.height) / 2;
    return _nearTrailingEdge(frame, local.dx, targets.touchTargetWidth) &&
        local.dy >= thumb.top - grow &&
        local.dy <= thumb.bottom + grow;
  }

  /// Where a mouse or trackpad press lands under [targets]: the thumb, the
  /// track under [ChatScrollbarTrackPress.centerThumb], or `null` — off the
  /// strip, a track press under [ChatScrollbarTrackPress.fallThrough], or
  /// any button but the primary one.
  ChatScrollbarPress? _stripPress(
    ChatScrollbarFrame frame,
    ChatScrollbarGrab$Targets targets,
    PointerDownEvent event,
  ) {
    if (event.buttons & kPrimaryButton == 0) return null;
    if (!_stripContains(frame, targets, event.localPosition)) return null;
    final dy = event.localPosition.dy;
    if (dy >= frame.thumbRect.top && dy <= frame.thumbRect.bottom) {
      return ChatScrollbarPress.thumb;
    }
    return switch (targets.trackPress) {
      ChatScrollbarTrackPress.centerThumb => ChatScrollbarPress.track,
      ChatScrollbarTrackPress.fallThrough => null,
    };
  }

  /// Starts a grab when [event] lands on a live target of the last resolved
  /// [frame] for its pointer kind — the strip for a mouse or trackpad, the
  /// touch target for anything else (see the type docs); never under
  /// [ChatScrollbarGrab$None]. Replaces a settle in flight, holds
  /// visibility until [endGrab], and starts the grab factor easing to `1`;
  /// the owner starts its ticker.
  ///
  /// The caller decides whether the press is fresh; this reads only the
  /// press itself, [frame], [grab], and [visibility]. Returns where the
  /// press landed, or `null` when it was declined and no grab started. On
  /// [ChatScrollbarPress.track] the thumb is centred on the pointer; read
  /// [grabPosition] for the band position that asks for.
  ChatScrollbarPress? tryStartGrab(PointerDownEvent event) {
    final frame = _frame;
    final targets = grab;
    if (frame == null || targets is! ChatScrollbarGrab$Targets) return null;
    final press = switch (event.kind) {
      PointerDeviceKind.mouse ||
      PointerDeviceKind.trackpad => _stripPress(frame, targets, event),
      PointerDeviceKind.touch ||
      PointerDeviceKind.stylus ||
      PointerDeviceKind.invertedStylus ||
      PointerDeviceKind.unknown =>
        visibility > 0 &&
                _touchTargetContains(frame, targets, event.localPosition)
            ? ChatScrollbarPress.thumb
            : null,
    };
    if (press == null) return null;
    final dy = event.localPosition.dy;
    final thumb = frame.thumbRect;
    _motion = _Grab(
      pointer: event.pointer,
      pointerY: dy,
      grabOffset: switch (press) {
        ChatScrollbarPress.thumb => dy - thumb.top,
        ChatScrollbarPress.track => thumb.height / 2,
      },
      thumbLength: thumb.height,
      spanShare: _spanShare,
    );
    _visibilityClock?.hold();
    _easeFactor(_grabFactor, 1);
    return press;
  }

  // --- Grab motion and settle ------------------------------------------------

  /// The grab's thumb position against the last resolved track, or `null`
  /// when no grab is held or no frame is resolved.
  ChatScrollbarGrabPosition? get grabPosition => switch ((_motion, _frame)) {
    (final _Grab grab, final frame?) => (
      progress: grab.progressOn(frame.trackRect.top, frame.trackRect.height),
      spanShare: grab.spanShare,
    ),
    _ => null,
  };

  /// Moves the grab to the pointer at [localY] and returns the new
  /// [grabPosition]. The next [resolve] paints the thumb there.
  ChatScrollbarGrabPosition? moveGrab(double localY) {
    if (_motion case final _Grab grab) grab.pointerY = localY;
    return grabPosition;
  }

  /// Whether [event] belongs to the pointer holding the grab.
  bool ownsPointer(PointerEvent event) => switch (_motion) {
    _Grab(:final pointer) => pointer == event.pointer,
    _ => false,
  };

  /// Ends the grab, if any, and starts the settle from the thumb the grab
  /// last asked for. Without a resolved frame the thumb goes straight to
  /// rest. Releases the grab's visibility hold: the idle delay starts
  /// unless list motion or strip hover still holds. The grab factor starts
  /// easing to `0` alongside the settle.
  void endGrab() {
    if (_motion case final _Grab grab) {
      _motion = switch (_frame) {
        ChatScrollbarFrame(:final trackRect) => _Settle(
          fromOffset: grab.offsetOn(trackRect.top, trackRect.height),
          fromLength: grab.lengthOn(trackRect.height),
        ),
        null => null,
      };
      if (!_held) _visibilityClock?.release();
      _easeFactor(_grabFactor, 0);
    }
  }

  /// How long the release settle runs: the auto-hide fade-out, or 250 ms
  /// under always visibility and with no preset. A falling factor eases
  /// over the same span.
  Duration get settleDuration => switch (_visibilityMode) {
    ChatScrollbarVisibility$AutoHide(:final fadeOut) => fadeOut,
    ChatScrollbarVisibility$Always() || null => _alwaysFadeDuration,
  };

  /// How long a rising factor eases: the auto-hide fade-in, or 250 ms under
  /// always visibility and with no preset.
  Duration get _riseDuration => switch (_visibilityMode) {
    ChatScrollbarVisibility$AutoHide(:final fadeIn) => fadeIn,
    ChatScrollbarVisibility$Always() || null => _alwaysFadeDuration,
  };

  /// Curve applied to the settle's and the factors' linear time fractions;
  /// the thumb's top and length, and each factor, are lerped by its output.
  /// The auto-hide curve, or [Curves.easeOut] under always visibility and
  /// with no preset.
  Curve get settleCurve => switch (_visibilityMode) {
    ChatScrollbarVisibility$AutoHide(:final curve) => curve,
    ChatScrollbarVisibility$Always() || null => _alwaysCurve,
  };

  /// Advances the settle and both factors to the ticker time [elapsed] and
  /// returns whether any of them moved, so the owner repaints.
  bool tick(Duration elapsed) {
    final settled = _tickSettle(elapsed);
    final hovered = _tickFactor(_hoverFactor, elapsed);
    final grabbed = _tickFactor(_grabFactor, elapsed);
    return settled || hovered || grabbed;
  }

  /// Advances the settle to [elapsed]; `true` when the thumb moved. The
  /// first tick after [endGrab] starts the clock, so the first settle frame
  /// still shows the pointer's position; the tick past [settleDuration]
  /// returns the thumb to rest. A zero [settleDuration] rests on that first
  /// tick. A visibility change mid-settle retimes the rest of it.
  bool _tickSettle(Duration elapsed) {
    if (_motion case final _Settle settle) {
      final start = settle.start ??= elapsed;
      final duration = settleDuration;
      final t = duration <= Duration.zero
          ? 1.0
          : (elapsed - start).inMicroseconds / duration.inMicroseconds;
      if (t >= 1) {
        _motion = null;
      } else {
        settle.eased = settleCurve.transform(t);
      }
      return true;
    }
    return false;
  }

  // --- Hover and grab factors ------------------------------------------------

  final _Ease _hoverFactor = _Ease();
  final _Ease _grabFactor = _Ease();

  /// Points [factor] at [target], rising over [_riseDuration] or falling
  /// over [settleDuration]. A zero duration jumps there now: waiting a tick
  /// for a step would show one stale frame.
  void _easeFactor(_Ease factor, double target) {
    final duration = target > factor.value ? _riseDuration : settleDuration;
    factor.aim(target, instant: duration <= Duration.zero);
  }

  bool _tickFactor(_Ease factor, Duration elapsed) => factor.tick(
    elapsed,
    factor.rising ? _riseDuration : settleDuration,
    settleCurve,
  );

  // --- Strip hover -----------------------------------------------------------

  /// Hit-test target the owner adds ahead of its children wherever
  /// [stripContains] holds, so the mouse tracker sees the strip as the
  /// topmost region there: it shows [SystemMouseCursors.basic] over message
  /// cursors, and its enter and exit drive the hover hold. Ignores the
  /// pointer events it is dispatched; a press in the strip still reaches the
  /// owner and the messages below.
  late final HitTestTarget stripTarget = _StripTarget(this);

  bool _hovered = false;

  /// Enter and exit of [stripTarget]. Entering holds visibility (revealing
  /// a hidden scrollbar) unless another holder already does; leaving
  /// releases it unless another holder still holds. Either way the hover
  /// factor starts easing, so the owner repaints and runs its ticker.
  void _hoverStrip(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    if (hovered) {
      // A second hold would replace a live navigation hold's delay with the
      // idle delay.
      if (_visibilityClock case final clock? when !clock.isHolding) {
        clock.hold();
      }
    } else if (!_held) {
      _visibilityClock?.release();
    }
    _easeFactor(_hoverFactor, hovered ? 1 : 0);
    _onChanged();
  }

  // --- Pointer presence ------------------------------------------------------

  /// Whether the preset's visibility follows a mouse in and out of the
  /// viewport ([ChatScrollbarVisibility$AutoHide.followsPointer]).
  bool get followsPointer => switch (_visibilityMode) {
    ChatScrollbarVisibility$AutoHide(:final followsPointer) => followsPointer,
    ChatScrollbarVisibility$Always() || null => false,
  };

  /// Whether the owner adds [viewportTarget] to its hit tests: while
  /// [followsPointer] and a [frame] is resolved, so a viewport with nothing
  /// to scroll raises no visibility for a scrollbar it does not paint. A
  /// pointer resting inside is reported entering once a frame appears —
  /// the mouse tracker re-tests after each frame — and leaving once it
  /// goes.
  bool get tracksViewport => followsPointer && _frame != null;

  /// Hit-test target the owner adds for every position inside the viewport
  /// while [tracksViewport], so the mouse tracker reports a mouse or
  /// trackpad pointer entering and leaving the viewport as a whole —
  /// moving between messages inside it reports nothing. Defers the cursor
  /// to whatever lies beneath and ignores the pointer events it is
  /// dispatched.
  late final HitTestTarget viewportTarget = _ViewportTarget(this);

  /// A mouse entered the viewport: pulse with the idle delay — or with the
  /// navigation delay while a navigation's hide is pending, so entering
  /// never brings that hide forward. Skipped while a holder holds: the
  /// release that ends the hold schedules the hide.
  void _enterViewport() {
    if (!followsPointer) return;
    if (_visibilityClock case final clock? when !clock.isHolding) {
      clock.pulse(navigation: clock.isNavigationHidePending);
    }
  }

  /// A mouse left the viewport: the strip, inside it, is left too, whatever
  /// order the tracker reports the two exits in; then the fade starts at
  /// once unless list motion or a grab still holds.
  void _leaveViewport() {
    if (!followsPointer) return;
    _hoverStrip(false);
    if (!_held) _visibilityClock?.hide();
  }

  // --- Visibility ------------------------------------------------------------

  final VoidCallback _onChanged;

  /// The preset's visibility; `null` with no painted preset or while
  /// detached.
  ChatScrollbarVisibility? _visibilityMode;

  /// Live exactly while [_visibilityMode] is auto-hide.
  ChatScrollActivityClock? _visibilityClock;

  /// Whether list motion holds visibility, separately from the grab's and
  /// the hover's holds, so ending one never drops another.
  bool _motionHeld = false;

  /// Whether any holder still wants the scrollbar shown.
  bool get _held => _motionHeld || isGrabbing || _hovered;

  bool _visibilityMuted = false;

  /// **Scrollbar visibility** in `[0, 1]`: `1` under always, the auto-hide
  /// clock's value under auto-hide, `0` when unconfigured.
  double get visibility => switch (_visibilityMode) {
    ChatScrollbarVisibility$AutoHide() => _visibilityClock?.value ?? 0,
    ChatScrollbarVisibility$Always() => 1,
    null => 0,
  };

  /// Pauses auto-hide fades while the viewport's `TickerMode` is off. The
  /// idle delay still runs; a fade it starts waits for the ticker.
  set visibilityMuted(bool value) {
    _visibilityMuted = value;
    _visibilityClock?.muted = value;
  }

  /// Applies the preset's [value] — `null` for no painted preset, or on
  /// detach. An equal value changes nothing.
  ///
  /// Switching to auto-hide keeps the visibility currently shown: from
  /// always the scrollbar stays at `1` and the idle delay starts, unless a
  /// hold is live; from `null` it starts hidden. Auto-hide to auto-hide
  /// retimes the running clock, effective from its next fade, hold, or
  /// hide. Leaving auto-hide disposes the clock and cancels a pending hide.
  void configureVisibility(ChatScrollbarVisibility? value) {
    if (value == _visibilityMode) return;
    final shown = visibility;
    _visibilityMode = value;
    switch (value) {
      case final ChatScrollbarVisibility$AutoHide autoHide:
        final timing = ChatScrollActivityTiming(
          idleDelay: autoHide.idleDelay,
          navigationIdleDelay: autoHide.navigationIdleDelay,
          fadeIn: autoHide.fadeIn,
          fadeOut: autoHide.fadeOut,
          curve: autoHide.curve,
        );
        if (_visibilityClock case final clock?) {
          clock.timing = timing;
          return;
        }
        final clock = _visibilityClock = ChatScrollActivityClock(
          timing: timing,
          onChanged: _onChanged,
          initialValue: shown,
        )..muted = _visibilityMuted;
        if (_held) {
          clock.hold();
        } else if (shown > 0) {
          clock.pulse(navigation: false);
        }
      case ChatScrollbarVisibility$Always() || null:
        _visibilityClock?.dispose();
        _visibilityClock = null;
    }
  }

  /// List motion is moving the reader's position; [navigation] marks
  /// programmatic motion (an animated scroll), so the later release waits
  /// for the navigation delay. Called on every moving tick.
  void holdVisibility({bool navigation = false}) {
    _motionHeld = true;
    _visibilityClock?.hold(navigation: navigation);
  }

  /// Nothing moves the list any more. Starts the hide delay unless a grab or
  /// strip hover still holds; a no-op without a motion hold.
  void releaseVisibility() {
    if (!_motionHeld) return;
    _motionHeld = false;
    if (!_held) _visibilityClock?.release();
  }

  /// A discrete move of the reader's position: show, then hide after the
  /// navigation delay ([navigation]) or the idle delay, unless held.
  /// Ignored while a grab holds.
  void pulseVisibility({bool navigation = true}) {
    if (isGrabbing) return;
    _visibilityClock?.pulse(navigation: navigation);
  }
}

/// Whether [event]'s hover counts for the scrollbar: only a mouse or
/// trackpad. The mouse tracker also follows a hovering stylus, which grabs
/// by the touch rules and must not reveal a hidden scrollbar.
bool _hovers(PointerEvent event) => switch (event.kind) {
  PointerDeviceKind.mouse || PointerDeviceKind.trackpad => true,
  PointerDeviceKind.touch ||
  PointerDeviceKind.stylus ||
  PointerDeviceKind.invertedStylus ||
  PointerDeviceKind.unknown => false,
};

/// [ChatScrollbarRuntime.stripTarget]: a mouse-tracker region with the basic
/// cursor whose enter and exit report strip hover. Always valid — after the
/// owner detaches, a late exit lands on a runtime with no clock, and the
/// owner's repaint callback checks attachment.
final class _StripTarget extends MouseTrackerAnnotation
    implements HitTestTarget {
  _StripTarget(ChatScrollbarRuntime runtime)
    : super(
        cursor: SystemMouseCursors.basic,
        onEnter: (event) {
          if (_hovers(event)) runtime._hoverStrip(true);
        },
        onExit: (event) {
          if (_hovers(event)) runtime._hoverStrip(false);
        },
      );

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {}
}

/// [ChatScrollbarRuntime.viewportTarget]: a mouse-tracker region over the
/// whole viewport that defers the cursor and reports enter and exit. Always
/// valid, like [_StripTarget]; the runtime ignores both while it does not
/// follow the pointer, so a late exit after a preset change moves nothing.
final class _ViewportTarget extends MouseTrackerAnnotation
    implements HitTestTarget {
  _ViewportTarget(ChatScrollbarRuntime runtime)
    : super(
        onEnter: (event) {
          if (_hovers(event)) runtime._enterViewport();
        },
        onExit: (event) {
          if (_hovers(event)) runtime._leaveViewport();
        },
      );

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {}
}

/// The thumb's motion away from rest; `null` in [ChatScrollbarRuntime] is
/// rest.
sealed class _ThumbMotion {}

/// A pointer holding the thumb.
final class _Grab extends _ThumbMotion {
  _Grab({
    required this.pointer,
    required this.pointerY,
    required this.grabOffset,
    required this.thumbLength,
    required this.spanShare,
  });

  final int pointer;

  /// The pointer's latest viewport-local Y.
  double pointerY;

  /// Distance from the thumb's top to the pointer, kept for the whole grab.
  final double grabOffset;

  /// Thumb length at the press.
  final double thumbLength;

  /// The visible band's share of the known span at the press.
  final double spanShare;

  /// [thumbLength] fitted into a track of [trackLength].
  double lengthOn(double trackLength) => math.min(thumbLength, trackLength);

  /// Distance from the track's top at [trackTop] to the thumb's top, which
  /// sits [grabOffset] above the pointer, clamped to the thumb's travel.
  double offsetOn(double trackTop, double trackLength) =>
      (pointerY - grabOffset - trackTop).clamp(
        0.0,
        math.max<double>(0, trackLength - lengthOn(trackLength)),
      );

  /// [offsetOn] as a share of the thumb's travel, in `[0, 1]`; `0` when the
  /// thumb leaves no travel.
  double progressOn(double trackTop, double trackLength) {
    final travel = trackLength - lengthOn(trackLength);
    if (travel <= 0) return 0;
    return offsetOn(trackTop, trackLength) / travel;
  }
}

/// The thumb easing from where a grab left it back to the band: its top's
/// distance from the track top and its length both run from the grab's
/// values to the band's, so the painted rect moves in one piece.
final class _Settle extends _ThumbMotion {
  _Settle({required this.fromOffset, required this.fromLength});

  final double fromOffset;
  final double fromLength;

  /// Ticker time of the first tick after release.
  Duration? start;

  /// [ChatScrollbarRuntime.settleCurve] at the settle's current time, from
  /// `0` (the grab's thumb) to `1` (the band's).
  double eased = 0;
}

/// A hover or grab factor easing from its value when last aimed toward
/// `0` or `1`, timed by the owner's ticker. The runtime supplies duration
/// and curve on every tick, so a visibility change mid-ease retimes the
/// rest of it, as it does the settle.
final class _Ease {
  double value = 0;
  double _from = 0;
  double _target = 0;

  /// Ticker time of the first tick after the last [aim].
  Duration? _start;

  bool get isEasing => value != _target;

  /// Whether the current ease runs toward a larger value.
  bool get rising => _target > _from;

  /// Starts easing from [value] toward [target], or jumps there when
  /// [instant]. Re-aiming at the current target changes nothing.
  void aim(double target, {required bool instant}) {
    if (target == _target) return;
    _target = target;
    _from = value;
    _start = null;
    if (instant) value = target;
  }

  /// Jumps to [target] with no ease pending.
  void snap(double target) {
    value = _from = _target = target;
    _start = null;
  }

  /// Advances to the ticker time [elapsed]; `true` while easing. The first
  /// tick after [aim] starts the clock and still shows the aimed-from value.
  /// A ticker that restarted mid-ease reports an earlier [elapsed]; the ease
  /// restarts its clock there rather than running backwards.
  bool tick(Duration elapsed, Duration duration, Curve curve) {
    if (!isEasing) return false;
    var start = _start ??= elapsed;
    if (elapsed < start) start = _start = elapsed;
    final t = duration <= Duration.zero
        ? 1.0
        : (elapsed - start).inMicroseconds / duration.inMicroseconds;
    value = t >= 1 ? _target : lerpDouble(_from, _target, curve.transform(t))!;
    return true;
  }
}
