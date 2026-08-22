import 'dart:async';
import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_dev_log.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// Legacy constant retained for tests/callers. Path selection no longer uses a
/// pixel-distance gate: **built → close-path**, **not built → stitch**.
const double kCloseAnimateDistance = 2400;

/// Floor for travel-scaled [chatAnimateTravelDuration] (ms).
const int kAnimateTravelDurationMinMs = 300;

/// Cap for travel-scaled [chatAnimateTravelDuration] (ms).
const int kAnimateTravelDurationMaxMs = 1300;

/// Default solid hold after navigate-select settle (ms).
/// Mapped to [ChatAnimator.highlightDuration].
const int kHighlightHoldDurationMs = 1000;

/// Fade length after navigate-select hold ends.
const Duration kHighlightFadeDuration = Duration(milliseconds: 300);

/// Stitch geometry captured when [ChatAnimator.cancelAnimate] aborts a far path.
class StitchCancelSnapshot {
  /// Creates a snapshot of the stitch cancel state.
  const StitchCancelSnapshot({
    required this.targetId,
    required this.measured,
    required this.jumped,
    required this.progress,
    required this.scrollLength,
    required this.towardNewer,
  });

  /// The id of the target message that was being stitched.
  final int targetId;

  /// Whether the stitch was measured.
  final bool measured;

  /// Whether the stitch jumped.
  final bool jumped;

  /// The progress of the stitch.
  final double progress;

  /// The scroll length of the stitch.
  final double scrollLength;

  /// Whether the stitch was toward newer.
  final bool towardNewer;
}

/// Travel-scaled animate duration for close-path and stitch.
///
/// Formula: `((|travel| / viewportHeight) + 1) * 200` ms, clamped to
/// [[kAnimateTravelDurationMinMs], [kAnimateTravelDurationMaxMs]].
/// Longer hops feel deliberate; short hops stay snappy. Same curve family as
/// stitch so a tall on-screen close hop does not finish much faster than an
/// equivalent stitch.
Duration chatAnimateTravelDuration({
  required double travelPx,
  required double viewportHeight,
}) {
  final vh = viewportHeight <= 0 ? 1.0 : viewportHeight;
  final raw = ((travelPx.abs() / vh) + 1.0) * 200.0;
  final ms = raw
      .clamp(
        kAnimateTravelDurationMinMs.toDouble(),
        kAnimateTravelDurationMaxMs.toDouble(),
      )
      .round();
  return Duration(milliseconds: ms);
}

/// Phases of the navigate-select row wash.
enum ChatHighlightPhase {
  /// No overlay and no pending arm.
  idle,

  /// Full-strength wash (hold clock may still be deferred until settle).
  solid,

  /// Opacity declining toward clear after hold (or cancel).
  fading,
}

/// Owns `animateTo` motion and navigate-select highlight for
/// [RenderChatScrollView].
///
/// ## Paths
///
/// - **Close:** target is already built → continuous origin-offset
///   interpolation. Endpoint from [closePathEndOffsetFor] (band alignment, or
///   tail-pin for the known newest).
/// - **Stitch (far):** target not built → capture outgoing rows, teleport,
///   dual-translate paint. Runs only after the load-gate ([isDestinationReady]).
///   No whole-viewport opacity fade.
///
/// ## Timing
///
/// Both paths use [chatAnimateTravelDuration] + [Curves.easeOutQuint]. Caller
/// duration/curve are hints (`duration ≤ 0` ⇒ instant jump).
///
/// ## Highlight
///
/// When `highlight: true`: arm solid at navigate start; hold clock starts /
/// restarts at settle; then [kHighlightFadeDuration] fade. Drag/cancel fades;
/// host [jumpTo] / overlay hard-clear. See `docs/architecture/11-animation-integration.md`.
///
/// ## Tick integration
///
/// [tickAnimate] returns close-path scroll delta (stitch mutates
/// [stitchProgress] and returns 0). [tickHighlight] advances hold/fade.
class ChatAnimator implements ChatScrollAnimator {
  /// Creates an animator bound to [controller] and render-object callbacks.
  ChatAnimator({
    required ChatScrollController controller,
    required double? Function(int id) offsetToBuiltMessage,

    /// Whether built [id] intersects the paint band (used for logging / close
    /// path diagnostics — path selection itself is built vs not-built).
    required bool Function(int id) messageIntersectsPaintBand,

    /// Viewport height for travel-scaled duration.
    required double Function() viewportHeight,
    required double Function(
      int targetId,
      double messageHeight,
      double alignment,
    )
    closePathEndOffsetFor,
    required bool Function(int targetId) isTailClosePathTarget,
    required RenderBox? Function(int id) childForId,
    required double Function(RenderBox child) offsetOfChild,
    required double Function(RenderBox child) heightOfChild,
    required bool Function(int id) isHighlightReady,
    required bool Function(int id) shouldDropPendingHighlight,

    /// `true` when [id] is loaded enough for a real destination row (not an
    /// unresolved shimmer stand-in). Load-gate blocks path selection until
    /// this returns true.
    required bool Function(int id) isDestinationReady,

    /// Ask the host/viewport to fetch an around-target destination window
    /// for the navigation load-gate.
    required void Function(int targetId) requestDestinationWindow,

    /// Clear the load-gate destination-window fetch pin.
    required VoidCallback clearDestinationWindow,
    required VoidCallback markNeedsPaint,
    required VoidCallback markNeedsLayout,
    required VoidCallback ensureTicker,
    required VoidCallback cancelFling,
    required VoidCallback cancelBounceback,

    /// Capture visible outgoing rows before the stitch jump. Render-owned.
    required void Function(int targetId) prepareStitchCapture,

    /// Bake dual-translate into layout offsets when a stitch flight is cancelled.
    required void Function(StitchCancelSnapshot snapshot) onStitchCancelled,

    /// Bake dual-translate at final progress and clear stitch capture on normal
    /// stitch completion. Render-owned.
    required void Function(StitchCancelSnapshot snapshot) onStitchComplete,
    Duration highlightDuration = const Duration(
      milliseconds: kHighlightHoldDurationMs,
    ),
    Color highlightColor = const Color(0x280A90F0),
  }) : _controller = controller,
       _offsetToBuiltMessage = offsetToBuiltMessage,
       _messageIntersectsPaintBand = messageIntersectsPaintBand,
       _viewportHeight = viewportHeight,
       _closePathEndOffsetFor = closePathEndOffsetFor,
       _isTailClosePathTarget = isTailClosePathTarget,
       _childForId = childForId,
       _offsetOfChild = offsetOfChild,
       _heightOfChild = heightOfChild,
       _isHighlightReady = isHighlightReady,
       _shouldDropPendingHighlight = shouldDropPendingHighlight,
       _isDestinationReady = isDestinationReady,
       _requestDestinationWindow = requestDestinationWindow,
       _clearDestinationWindow = clearDestinationWindow,
       _markNeedsPaint = markNeedsPaint,
       _markNeedsLayout = markNeedsLayout,
       _ensureTicker = ensureTicker,
       _cancelFling = cancelFling,
       _cancelBounceback = cancelBounceback,
       _prepareStitchCapture = prepareStitchCapture,
       _onStitchCancelled = onStitchCancelled,
       _onStitchComplete = onStitchComplete,
       _highlightDuration = highlightDuration,
       _highlightColor = highlightColor;

  final ChatScrollController _controller;
  final double? Function(int id) _offsetToBuiltMessage;
  final bool Function(int id) _messageIntersectsPaintBand;
  final double Function() _viewportHeight;
  final double Function(int targetId, double messageHeight, double alignment)
  _closePathEndOffsetFor;
  final bool Function(int targetId) _isTailClosePathTarget;
  final RenderBox? Function(int id) _childForId;
  final double Function(RenderBox child) _offsetOfChild;
  final double Function(RenderBox child) _heightOfChild;
  final bool Function(int id) _isHighlightReady;
  final bool Function(int id) _shouldDropPendingHighlight;
  final bool Function(int id) _isDestinationReady;
  final void Function(int targetId) _requestDestinationWindow;
  final VoidCallback _clearDestinationWindow;
  final VoidCallback _markNeedsPaint;
  final VoidCallback _markNeedsLayout;
  final VoidCallback _ensureTicker;
  final VoidCallback _cancelFling;
  final VoidCallback _cancelBounceback;
  final void Function(int targetId) _prepareStitchCapture;
  final void Function(StitchCancelSnapshot snapshot) _onStitchCancelled;
  final void Function(StitchCancelSnapshot snapshot) _onStitchComplete;

  /// Animate / stitch diagnostics — filter console for `ChatScrollAnimate`.
  ///
  /// Enabled in debug so reproduce steps can be pasted back. Set
  /// [log.enabled] to `false` to silence.
  final ChatScrollDevLog log = ChatScrollDevLog(
    'ChatScrollAnimate',
    enabled: true,
  );

  /// Last logged progress bucket `0..10` for sparse tick lines.
  int _lastProgressBucket = -1;

  /// Active `animateTo`'s completer, or `null` when no animation is running.
  Completer<void>? animateCompleter;

  /// Target id for the in-flight animation; for the close-target branch the
  /// anchor has already been reassigned to this id at the start.
  @override
  int animateTargetId = 0;

  /// Viewport alignment (`0` = top, `1` = bottom) for the in-flight target.
  @override
  double animateAlignment = 0;

  /// Anchor pixel offset at animation start (close path).
  double animateStartOffset = 0;

  /// Target anchor offset (close path).
  double animateEndOffset = 0;

  /// Ticker timestamp when the current animation segment started.
  Duration? animateStartTime;

  /// Close-path settle deferred until after the render object applies the
  /// final tick delta and repositions children — avoids fighting
  /// [applyScrollDelta] with a stale [animateEndOffset].
  int? _pendingSettleTargetId;

  /// Total duration of the active `animateTo` (may be rewritten after stitch
  /// measure to scale with scroll length).
  Duration animateDuration = Duration.zero;

  /// Easing curve for the active `animateTo`.
  Curve animateCurve = Curves.linear;

  /// Caller load policy for the in-flight animate.
  AnimateToLoadPolicy loadPolicy = AnimateToLoadPolicy.immediate;

  /// `true` while the navigation load-gate is waiting for a ready destination
  /// (or [preferBuilt] is waiting one layout for a close-path chance).
  bool loadGateWaiting = false;

  /// Alias for [loadGateWaiting] kept for older call sites / debug readers.
  bool get preferBuiltWaiting => loadGateWaiting;
  set preferBuiltWaiting(bool value) => loadGateWaiting = value;

  /// Close or stitch path has been entered for the in-flight animate.
  bool _pathStarted = false;

  /// `true` after one deferred layout request for stitch measure.
  bool _stitchMeasureLayoutAsked = false;

  /// `true` while the far-path stitch is active.
  bool farAnimateActive = false;

  /// `true` after the stitch `jumpTo` has run (at stitch start).
  bool farAnimateJumped = false;

  /// `true` after layout measured [stitchScrollLength].
  bool stitchMeasured = false;

  /// Eased progress `0..1` for dual-translate paint (set each tick).
  double stitchProgress = 0;

  /// Pixel travel for outgoing/incoming translations.
  double stitchScrollLength = 0;

  /// When `true`, outgoing rows exit upward (toward older off top) and
  /// incoming enter from below — typical jump toward newer / tail.
  bool stitchTowardNewer = true;

  /// Viewport height used when scaling stitch duration (set by measure).
  double stitchViewportHeight = 1;

  /// Deprecated alias kept at 1.0 so cancel/paint cleanup that still
  /// references opacity does not flash. Far path no longer fades.
  double get fadeOpacity => 1;

  /// Per-call preference from the active `animateTo`: whether to keep / arm
  /// the navigate-select highlight for this flight.
  bool animateHighlight = true;

  /// Message id receiving the highlight overlay, or `null` when idle.
  int? highlightTargetId;

  /// Highlight waiting for [isHighlightReady] — set when navigate starts
  /// (or settles) before the target row is ready to paint.
  int? pendingHighlightTargetId;

  /// Current [ChatHighlightPhase] for the active overlay.
  ChatHighlightPhase highlightPhase = ChatHighlightPhase.idle;

  /// Ticker time when the solid **hold** clock started (null until settle /
  /// already-there / first tick after [startHighlightHold]).
  Duration? highlightHoldStartTime;

  /// Ticker time when the fade phase started.
  Duration? highlightFadeStartTime;

  /// When true, solid hold elapsed-time is advancing. False while animating
  /// (hold deferred until settle) or before arm.
  bool _holdClockActive = false;

  /// If settle requested hold while still pending arm, start hold on arm.
  bool _startHoldWhenArmed = false;

  /// Current opacity factor (0..1); 1 during solid, declining during fade.
  double highlightFactor = 0;

  /// Solid hold length after settle. Zero disables highlight entirely.
  /// Fade is always [kHighlightFadeDuration].
  Duration _highlightDuration;

  /// See [highlightDuration] setter.
  Duration get highlightDuration => _highlightDuration;
  set highlightDuration(Duration value) {
    if (_highlightDuration == value) return;
    _highlightDuration = value;
    // Drop in-flight highlight when hold length changes — do not reshape
    // an active fade retroactively. `Duration.zero` clears synchronously.
    if (highlightTargetId != null || pendingHighlightTargetId != null) {
      clearHighlight();
    }
  }

  /// Peak colour of the highlight underlay (alpha scaled by [highlightFactor]).
  Color _highlightColor;

  /// See [highlightColor] setter.
  Color get highlightColor => _highlightColor;
  set highlightColor(Color value) {
    if (_highlightColor == value) return;
    _highlightColor = value;
    if (highlightTargetId != null) _markNeedsPaint();
  }

  /// Whether an `animateTo` is in flight.
  @override
  bool get isAnimating => animateCompleter != null;

  /// Whether a highlight overlay or deferred arm is active.
  bool get hasHighlight =>
      highlightTargetId != null || pendingHighlightTargetId != null;

  /// Pixel epsilon: treat start/end (or current/desired) as already aligned.
  static const double _settleEpsilon = 1;

  @override
  Future<void> animate(
    int targetId, {
    required Duration duration,
    required Curve curve,
    double alignment = 0.0,
    bool highlight = true,
    AnimateToLoadPolicy loadPolicy = AnimateToLoadPolicy.immediate,
    AnimateToBusyPolicy busyPolicy = AnimateToBusyPolicy.ignore,
  }) {
    final align = alignment.clamp(0.0, 1.0);

    // Same destination → coalesce. Different target → ignore, or cancel and
    // restart immediately when [busyPolicy] is replace.
    final inFlight = animateCompleter;
    if (inFlight != null && !inFlight.isCompleted) {
      final sameTarget =
          animateTargetId == targetId &&
          (animateAlignment - align).abs() < 0.001;
      if (sameTarget && duration > Duration.zero) {
        log.event('animate.coalesce', {
          'target': targetId,
          'far': farAnimateActive,
          'measured': stitchMeasured,
          'stitchProgress': farAnimateActive
              ? DevLogFormat.ratio(stitchProgress)
              : null,
        });
        if (highlight) animateHighlight = true;
        return inFlight.future;
      }
      if (busyPolicy != AnimateToBusyPolicy.replace) {
        log.event('animate.ignored', {
          'requested': targetId,
          'running': animateTargetId,
          'far': farAnimateActive,
          'preferBuiltWaiting': preferBuiltWaiting,
          'stitchProgress': farAnimateActive
              ? DevLogFormat.ratio(stitchProgress)
              : null,
        });
        return Future<void>.value();
      }
      log.event('animate.replace', {
        'requested': targetId,
        'running': animateTargetId,
        'far': farAnimateActive,
        'loadGateWaiting': loadGateWaiting,
      });
      cancelAnimate(fadeHighlight: false);
      // Fall through to start the new animate.
    }

    // Already painted at the aligned seat — no teleport / scroll.
    if (duration > Duration.zero &&
        _isAlreadyAtAlignedTarget(targetId, align)) {
      log.event('animate.alreadyThere', {
        'target': targetId,
        'align': DevLogFormat.ratio(align),
        'anchorId': _controller.anchorMessageId,
        'anchorY': DevLogFormat.f(_controller.anchorPixelOffset),
      });
      clearHighlight();
      _cancelBounceback();
      _cancelFling();
      animateHighlight = highlight;
      // Already-on-screen targets still get navigate-select when requested.
      if (highlight && highlightDuration > Duration.zero) {
        _requestHighlight(targetId, startHold: true);
      }
      return Future<void>.value();
    }

    // Fresh animate owns attention: drop leftover highlight / spring-back.
    clearHighlight();
    _cancelBounceback();
    if (duration <= Duration.zero) {
      // Zero duration is instant jumpTo — no animation phase and no highlight.
      log.event('animate.jumpInstant', {
        'target': targetId,
        'align': DevLogFormat.ratio(align),
      });
      _controller.jumpTo(targetId, alignment: align);
      return Future<void>.value();
    }

    animateHighlight = highlight;
    this.loadPolicy = loadPolicy;
    final completer = Completer<void>();
    animateCompleter = completer;
    animateTargetId = targetId;
    animateAlignment = align;
    animateDuration = duration;
    animateCurve = curve;
    animateStartTime = null;
    loadGateWaiting = false;
    _pathStarted = false;
    _stitchMeasureLayoutAsked = false;
    _lastProgressBucket = -1;

    final offsetNow = _offsetToBuiltMessage(targetId);
    final readyNow = _isDestinationReady(targetId);
    log.event('animate.start', {
      'target': targetId,
      'align': DevLogFormat.ratio(animateAlignment),
      'durationMs': duration.inMilliseconds,
      'loadPolicy': loadPolicy.name,
      'highlight': highlight,
      'ready': readyNow,
      'offsetToTarget': offsetNow == null ? 'null' : DevLogFormat.f(offsetNow),
      'anchorId': _controller.anchorMessageId,
      'anchorY': DevLogFormat.f(_controller.anchorPixelOffset),
    });

    // Arm highlight at flight start so tint tracks the target through motion.
    if (highlight && highlightDuration > Duration.zero) {
      _requestHighlight(targetId, startHold: false);
    }

    _cancelFling();
    _tryBeginPath();
    _ensureTicker();
    return completer.future;
  }

  /// `true` when [targetId] is built and already at its close-path end Y.
  bool _isAlreadyAtAlignedTarget(int targetId, double alignment) {
    final child = _childForId(targetId);
    if (child == null) return false;
    if (!_isDestinationReady(targetId)) return false;
    final top = _offsetToBuiltMessage(targetId);
    if (top == null) return false;
    final end = _closePathEndOffsetFor(
      targetId,
      _heightOfChild(child),
      alignment,
    );
    return (top - end).abs() < _settleEpsilon;
  }

  /// Re-evaluate path after layout during load-gate / preferBuilt wait.
  /// Must not call [markNeedsLayout] / [jumpTo] synchronously — those re-enter
  /// layout.
  ///
  /// Unready destinations stay waiting. Ready destinations select close vs
  /// stitch from built distance only — never invent gap distance, never force
  /// stitch on unresolved shimmers.
  void onLayoutOpportunity({required double viewportHeight}) {
    if (animateCompleter == null || !loadGateWaiting || _pathStarted) {
      return;
    }

    if (!_isDestinationReady(animateTargetId)) {
      log.event('path.loadGate.stillUnready', {
        'target': animateTargetId,
        'vh': DevLogFormat.f(viewportHeight),
      });
      // Do not re-request the dest window here — that reasserted the pin and
      // queued a fetch every layout frame, cancelling/restarting in-flight
      // work and busy-looping. Pin + poll from [_enterLoadGateWait] refill.
      return;
    }

    final offsetToTarget = _offsetToBuiltMessage(animateTargetId);
    if (_shouldUseClosePath(offsetToTarget)) {
      log.event('path.loadGate.readyClose', {
        'target': animateTargetId,
        'offset': DevLogFormat.f(offsetToTarget!),
        'vh': DevLogFormat.f(viewportHeight),
        'bandHit': _messageIntersectsPaintBand(animateTargetId),
      });
      loadGateWaiting = false;
      _beginClose(offsetToTarget);
      return;
    }

    // Ready but far, or ready and not yet built → stitch (deferred).
    log.event('path.loadGate.readyStitch', {
      'target': animateTargetId,
      'offset': offsetToTarget == null
          ? 'null'
          : DevLogFormat.f(offsetToTarget),
      'vh': DevLogFormat.f(viewportHeight),
    });
    loadGateWaiting = false;
    scheduleMicrotask(() {
      if (animateCompleter == null || _pathStarted) return;
      _beginStitch();
    });
  }

  /// Layout finished after stitch jump — supply travel distance and direction.
  ///
  /// [elapsed] anchors the animation clock to this layout so motion starts
  /// without waiting for a later ticker frame.
  void applyStitchMeasure({
    required double scrollLength,
    required bool towardNewer,
    required double viewportHeight,
    Duration? elapsed,
  }) {
    if (!farAnimateActive || stitchMeasured) return;
    stitchScrollLength = math.max(scrollLength, 1);
    stitchTowardNewer = towardNewer;
    stitchViewportHeight = math.max(viewportHeight, 1);
    stitchMeasured = true;
    _stitchMeasureLayoutAsked = false;
    stitchProgress = 0;
    animateDuration = _stitchDuration(stitchScrollLength, stitchViewportHeight);
    animateCurve = Curves.easeOutQuint;
    animateStartTime = elapsed;
    _lastProgressBucket = -1;
    log.event('stitch.measure', {
      'target': animateTargetId,
      'scrollLen': DevLogFormat.f(stitchScrollLength),
      'towardNewer': towardNewer,
      'vh': DevLogFormat.f(stitchViewportHeight),
      'durationMs': animateDuration.inMilliseconds,
      'elapsedUs': elapsed?.inMicroseconds,
    });
    _markNeedsPaint();
  }

  Duration _stitchDuration(double scrollLength, double viewportHeight) =>
      chatAnimateTravelDuration(
        travelPx: scrollLength,
        viewportHeight: viewportHeight,
      );

  /// Travel-scaled duration + [Curves.easeOutQuint] for close-path motion.
  /// Caller [animate] duration/curve are hints only (stitch overrides the same
  /// way after measure).
  void _applyCloseTravelTiming(double travelPx) {
    final vh = math.max<double>(_viewportHeight(), 1);
    animateDuration = chatAnimateTravelDuration(
      travelPx: travelPx,
      viewportHeight: vh,
    );
    animateCurve = Curves.easeOutQuint;
  }

  /// Close path when the target is among current built children.
  ///
  /// Pixel distance alone must not force stitch — tall reverse hops and
  /// scroll-to-tail often land off-band with |offset| ≫ viewport while still
  /// built.
  bool _shouldUseClosePath(double? offsetToTarget) => offsetToTarget != null;

  void _tryBeginPath() {
    if (!_isDestinationReady(animateTargetId)) {
      log.event('path.loadGate.wait', {
        'target': animateTargetId,
        'loadPolicy': loadPolicy.name,
      });
      _enterLoadGateWait();
      return;
    }

    final offsetToTarget = _offsetToBuiltMessage(animateTargetId);
    if (_shouldUseClosePath(offsetToTarget)) {
      log.event('path.close', {
        'target': animateTargetId,
        'offset': DevLogFormat.f(offsetToTarget!),
        'bandHit': _messageIntersectsPaintBand(animateTargetId),
      });
      loadGateWaiting = false;
      _beginClose(offsetToTarget);
      return;
    }

    if (loadPolicy == AnimateToLoadPolicy.preferBuilt &&
        offsetToTarget == null) {
      // Ready payload, row not yet in build range — one layout chance for
      // close-path (self-insert / follow-tail). Never timeout→force-stitch.
      log.event('path.preferBuilt.wait', {'target': animateTargetId});
      _enterLoadGateWait();
      return;
    }

    log.event('path.stitch', {
      'target': animateTargetId,
      'reason': 'notBuilt',
      'offset': 'null',
      'loadPolicy': loadPolicy.name,
    });
    loadGateWaiting = false;
    _beginStitch();
  }

  void _enterLoadGateWait() {
    loadGateWaiting = true;
    _requestDestinationWindow(animateTargetId);
    // Kick a layout so readiness / build-range can resolve. Safe: called
    // from [animate], not from inside performLayout.
    _markNeedsLayout();
  }

  void _leaveLoadGateWait() {
    loadGateWaiting = false;
    _clearDestinationWindow();
  }

  void _beginClose(double offsetToTarget) {
    _pathStarted = true;
    _leaveLoadGateWait();
    final child = _childForId(animateTargetId);
    final endOffset = child != null
        ? _closePathEndOffsetFor(
            animateTargetId,
            _heightOfChild(child),
            animateAlignment,
          )
        : 0.0;
    _controller.reassignAnchor(animateTargetId, offsetToTarget);
    animateStartOffset = offsetToTarget;
    animateEndOffset = endOffset;
    farAnimateActive = false;
    farAnimateJumped = false;
    stitchMeasured = false;
    stitchProgress = 0;
    _lastProgressBucket = -1;
    final travel = (animateEndOffset - animateStartOffset).abs();
    _applyCloseTravelTiming(travel);
    log.event('close.begin', {
      'target': animateTargetId,
      'startY': DevLogFormat.f(animateStartOffset),
      'endY': DevLogFormat.f(animateEndOffset),
      'travel': DevLogFormat.f(travel),
      'durationMs': animateDuration.inMilliseconds,
      'hasChild': child != null,
      'tailTarget': _isTailClosePathTarget(animateTargetId),
    });
    // Zero travel (already at end) — finish without a 300ms empty tween.
    if (travel < _settleEpsilon) {
      log.event('close.noop', {'target': animateTargetId});
      _completeAnimate();
    }
  }

  void _beginStitch() {
    _pathStarted = true;
    // End the load-gate wait, but keep (or establish) the destination-window
    // fetch pin for the flight. Stitch layout spans outgoing strip + incoming
    // band; without the pin, poll/jump-fetch contiguous-fills that gap.
    loadGateWaiting = false;
    _requestDestinationWindow(animateTargetId);
    farAnimateActive = true;
    stitchMeasured = false;
    stitchProgress = 0;
    stitchScrollLength = 0;
    _stitchMeasureLayoutAsked = false;
    _lastProgressBucket = -1;
    log.event('stitch.begin', {
      'target': animateTargetId,
      'align': DevLogFormat.ratio(animateAlignment),
      'anchorBefore': _controller.anchorMessageId,
      'anchorYBefore': DevLogFormat.f(_controller.anchorPixelOffset),
    });
    // Capture frozen outgoing geometry *before* the jump relocates fan-out.
    _prepareStitchCapture(animateTargetId);
    // Mark jumped before jumpTo so a synchronous layout from jump listeners
    // can run stitch measure in the same turn.
    farAnimateJumped = true;
    _controller.jumpTo(animateTargetId, alignment: animateAlignment);
    // Re-assert select highlight after teleport. Host jumpTo clears tint;
    // stitch-owned jumps must not. Even when clear is skipped, the child may
    // be pending rebuild — pending arm until layout.
    if (animateHighlight && highlightDuration > Duration.zero) {
      _requestHighlight(animateTargetId, startHold: false);
    }
    log.event('stitch.jumped', {
      'target': animateTargetId,
      'anchorAfter': _controller.anchorMessageId,
      'anchorYAfter': DevLogFormat.f(_controller.anchorPixelOffset),
      'highlightId': highlightTargetId,
      'highlightPending': pendingHighlightTargetId,
    });
    _markNeedsLayout();
  }

  /// Cancel the in-flight animation. When a navigate-select highlight is
  /// armed, begins a fade (does not hard-clear).
  @override
  void cancel() => cancelAnimate();

  /// Cancel the in-flight animation. See [cancel].
  ///
  /// Pass [fadeHighlight]: false only for paths that immediately
  /// [clearHighlight] (replace → re-arm, dispose).
  void cancelAnimate({bool fadeHighlight = true}) {
    final completer = animateCompleter;
    if (completer == null) return;
    log.event('animate.cancel', {
      'target': animateTargetId,
      'far': farAnimateActive,
      'measured': stitchMeasured,
      'progress': DevLogFormat.ratio(stitchProgress),
      'loadGateWaiting': loadGateWaiting,
      'fadeHighlight': fadeHighlight && animateHighlight,
    });
    animateCompleter = null;
    animateStartTime = null;
    _pendingSettleTargetId = null;
    _leaveLoadGateWait();
    _pathStarted = false;
    _stitchMeasureLayoutAsked = false;
    _lastProgressBucket = -1;
    final wasStitch = farAnimateActive;
    StitchCancelSnapshot? stitchCancel;
    if (wasStitch) {
      stitchCancel = StitchCancelSnapshot(
        targetId: animateTargetId,
        measured: stitchMeasured,
        jumped: farAnimateJumped,
        progress: stitchProgress,
        scrollLength: stitchScrollLength,
        towardNewer: stitchTowardNewer,
      );
    }
    farAnimateActive = false;
    farAnimateJumped = false;
    stitchMeasured = false;
    stitchProgress = 0;
    if (stitchCancel != null) {
      _onStitchCancelled(stitchCancel);
    }
    if (fadeHighlight &&
        animateHighlight &&
        highlightDuration > Duration.zero &&
        (highlightTargetId != null || pendingHighlightTargetId != null)) {
      beginHighlightFade();
    }
    if (!completer.isCompleted) completer.complete();
  }

  /// Drive the in-flight animation by one tick. Returns the additional scroll
  /// delta to apply (for the close path); stitch mutates [stitchProgress].
  double tickAnimate(Duration elapsed) {
    if (animateCompleter == null) return 0;

    if (loadGateWaiting) {
      if (!_isDestinationReady(animateTargetId)) {
        // Still unready — do **not** markNeedsLayout every tick (that makes
        // pumpAndSettle hang forever). Data notify schedules layout.
        return 0;
      }
      final offsetToTarget = _offsetToBuiltMessage(animateTargetId);
      if (_shouldUseClosePath(offsetToTarget)) {
        log.event('path.loadGate.tickClose', {
          'target': animateTargetId,
          'offset': DevLogFormat.f(offsetToTarget!),
          'bandHit': _messageIntersectsPaintBand(animateTargetId),
        });
        _beginClose(offsetToTarget);
        // Fall through to close-path tick below.
      } else if (offsetToTarget != null) {
        log.event('path.loadGate.tickStitch', {
          'target': animateTargetId,
          'offset': DevLogFormat.f(offsetToTarget),
        });
        _beginStitch();
        return 0;
      } else {
        // Ready but not built — wait for [onLayoutOpportunity].
        return 0;
      }
    }

    if (farAnimateActive) {
      if (!stitchMeasured) {
        // Prefer real post-jump layout measure. Paint already uses provisional
        // off-screen offsets for incoming via [_stitchPaintDy] — do **not**
        // finalize measure here or a later layout geom pass is ignored
        // (`stitchMeasured` already true).
        if (!_stitchMeasureLayoutAsked) {
          _stitchMeasureLayoutAsked = true;
          log.event('stitch.awaitMeasure', {'target': animateTargetId});
          _markNeedsLayout();
        } else {
          log.event('stitch.awaitMeasure.pending', {'target': animateTargetId});
          _markNeedsLayout();
        }
        return 0;
      }
      final stitchStart = animateStartTime ??= elapsed;
      final stitchUs = animateDuration.inMicroseconds;
      final stitchElapsedUs = (elapsed - stitchStart).inMicroseconds;
      final stitchT = stitchUs <= 0
          ? 1.0
          : (stitchElapsedUs / stitchUs).clamp(0.0, 1.0);
      stitchProgress = animateCurve.transform(stitchT);
      _logProgressTick(
        path: 'stitch',
        t: stitchT,
        progress: stitchProgress,
        extra: {
          'towardNewer': stitchTowardNewer,
          'scrollLen': DevLogFormat.f(stitchScrollLength),
        },
      );
      if (stitchT >= 1.0) {
        stitchProgress = 1.0;
        _completeAnimate();
      } else {
        _markNeedsPaint();
      }
      return 0;
    }

    // Close path: interpolate anchor offset linearly along the curve.
    rebaseClosePathEnd(elapsed: elapsed);
    final segmentStart = animateStartTime ??= elapsed;
    final segmentUs = animateDuration.inMicroseconds;
    final segmentElapsedUs = (elapsed - segmentStart).inMicroseconds;
    final segmentT = segmentUs <= 0
        ? 1.0
        : (segmentElapsedUs / segmentUs).clamp(0.0, 1.0);
    if (segmentT >= 1.0) {
      _completeAnimate();
      return 0;
    }
    final eased = animateCurve.transform(segmentT);
    final target =
        animateStartOffset + (animateEndOffset - animateStartOffset) * eased;
    final delta = target - _controller.anchorPixelOffset;
    _logProgressTick(
      path: 'close',
      t: segmentT,
      progress: eased,
      extra: {
        'anchorY': DevLogFormat.f(_controller.anchorPixelOffset),
        'targetY': DevLogFormat.f(target),
        'delta': DevLogFormat.f(delta),
        'endY': DevLogFormat.f(animateEndOffset),
      },
    );
    return delta;
  }

  void _logProgressTick({
    required String path,
    required double t,
    required double progress,
    Map<String, Object?> extra = const {},
  }) {
    final bucket = (t * 10).floor().clamp(0, 10);
    if (bucket == _lastProgressBucket) return;
    // Log 0%, 20%, 40%, …, 100% (even buckets) to keep volume low.
    if (bucket != 0 && bucket != 10 && bucket.isOdd) return;
    _lastProgressBucket = bucket;
    log.event('tick.$path', {
      'target': animateTargetId,
      't': DevLogFormat.ratio(t),
      'progress': DevLogFormat.ratio(progress),
      ...extra,
    });
  }

  /// Re-target [animateEndOffset] when layout geometry changes mid-flight
  /// (bottom inset, message height, date-header relayout). Rebases from the
  /// current anchor offset so the interpolator tracks the live aligned target
  /// without layout-time snapping during close-path animation.
  void rebaseClosePathEnd({Duration? elapsed}) {
    if (animateCompleter == null || farAnimateActive) {
      return;
    }
    // Band-top alignment (0) is stable for ordinary targets; tail-target
    // animate still rebases when height/insets change (tall newest).
    if (!_isTailClosePathTarget(animateTargetId) && animateAlignment == 0.0) {
      return;
    }
    final child = _childForId(animateTargetId);
    if (child == null) return;
    final newEnd = _closePathEndOffsetFor(
      animateTargetId,
      _heightOfChild(child),
      animateAlignment,
    );
    if ((newEnd - animateEndOffset).abs() < 0.5) return;
    log.event('close.rebase', {
      'target': animateTargetId,
      'oldEnd': DevLogFormat.f(animateEndOffset),
      'newEnd': DevLogFormat.f(newEnd),
      'anchorY': DevLogFormat.f(_controller.anchorPixelOffset),
    });
    animateStartOffset = _controller.anchorPixelOffset;
    animateEndOffset = newEnd;
    if (elapsed != null) {
      animateStartTime = elapsed;
    }
  }

  /// Consumes a deferred post-animate settle callback, if any.
  int? takePendingSettleTargetId() {
    final id = _pendingSettleTargetId;
    _pendingSettleTargetId = null;
    return id;
  }

  void _completeAnimate() {
    final completer = animateCompleter;
    final targetId = animateTargetId;
    final wasFarPath = farAnimateActive;
    StitchCancelSnapshot? stitchComplete;
    if (wasFarPath) {
      stitchComplete = StitchCancelSnapshot(
        targetId: targetId,
        measured: stitchMeasured,
        jumped: farAnimateJumped,
        progress: stitchProgress,
        scrollLength: stitchScrollLength,
        towardNewer: stitchTowardNewer,
      );
    }
    log.event('animate.complete', {
      'target': targetId,
      'path': wasFarPath ? 'stitch' : 'close',
      'anchorId': _controller.anchorMessageId,
      'anchorY': DevLogFormat.f(_controller.anchorPixelOffset),
      'highlight': animateHighlight && highlightDuration > Duration.zero,
    });
    animateCompleter = null;
    animateStartTime = null;
    _pathStarted = false;
    _leaveLoadGateWait();
    _stitchMeasureLayoutAsked = false;
    _lastProgressBucket = -1;
    farAnimateActive = false;
    farAnimateJumped = false;
    stitchMeasured = false;
    stitchProgress = 0;
    if (stitchComplete != null) {
      _onStitchComplete(stitchComplete);
    }
    if (!wasFarPath) {
      var end = animateEndOffset;
      final child = _childForId(targetId);
      if (child != null) {
        end = _closePathEndOffsetFor(
          targetId,
          _heightOfChild(child),
          animateAlignment,
        );
      }
      _controller.reassignAnchor(targetId, end);
    }
    // Successful settle → restart solid hold. Highlight was usually armed at
    // navigate start; if not (deferred), request with hold-on-arm.
    if (highlightDuration > Duration.zero && animateHighlight) {
      if (highlightTargetId == targetId ||
          pendingHighlightTargetId == targetId) {
        startHighlightHold();
      } else {
        _requestHighlight(targetId, startHold: true);
      }
    }
    _pendingSettleTargetId = targetId;
    _markNeedsPaint();
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _requestHighlight(int targetId, {required bool startHold}) {
    if (_shouldDropPendingHighlight(targetId)) return;
    _startHoldWhenArmed = startHold;
    if (_isHighlightReady(targetId)) {
      _armHighlight(targetId, startHold: startHold);
    } else {
      pendingHighlightTargetId = targetId;
      // Keep any prior solid on a different id from painting over the wrong
      // row while we wait — pending is the source of truth until arm.
      if (highlightTargetId != null && highlightTargetId != targetId) {
        highlightTargetId = null;
        highlightPhase = ChatHighlightPhase.idle;
        highlightFactor = 0;
        _holdClockActive = false;
        highlightHoldStartTime = null;
        highlightFadeStartTime = null;
      }
      _ensureTicker();
    }
  }

  void _armHighlight(int targetId, {required bool startHold}) {
    pendingHighlightTargetId = null;
    highlightTargetId = targetId;
    highlightPhase = ChatHighlightPhase.solid;
    highlightFactor = 1.0;
    highlightFadeStartTime = null;
    _holdClockActive = startHold;
    highlightHoldStartTime = null;
    _startHoldWhenArmed = startHold;
    _ensureTicker();
    _markNeedsPaint();
  }

  /// Restart the solid hold clock after settle.
  ///
  /// If the row is still pending, hold starts when [tryArmPendingHighlight]
  /// succeeds.
  void startHighlightHold() {
    if (highlightDuration <= Duration.zero) return;
    _startHoldWhenArmed = true;
    if (highlightTargetId == null) return;
    if (highlightPhase == ChatHighlightPhase.fading) {
      // Interrupted fade → back to solid for a fresh hold.
      highlightPhase = ChatHighlightPhase.solid;
      highlightFactor = 1.0;
      highlightFadeStartTime = null;
    }
    highlightPhase = ChatHighlightPhase.solid;
    highlightFactor = 1.0;
    _holdClockActive = true;
    highlightHoldStartTime = null;
    _ensureTicker();
    _markNeedsPaint();
  }

  /// Arms a deferred highlight once the target message has loaded. Called from
  /// the render object at the end of `performLayout` after chunk data may
  /// have changed. Returns `true` when a highlight was started.
  bool tryArmPendingHighlight() {
    final id = pendingHighlightTargetId;
    if (id == null) return false;
    if (_shouldDropPendingHighlight(id)) {
      pendingHighlightTargetId = null;
      return false;
    }
    if (!_isHighlightReady(id)) return false;
    pendingHighlightTargetId = null;
    _armHighlight(id, startHold: _startHoldWhenArmed || !isAnimating);
    return true;
  }

  /// Enter fade-out; skips any remaining solid hold.
  void beginHighlightFade() {
    pendingHighlightTargetId = null;
    _startHoldWhenArmed = false;
    _holdClockActive = false;
    highlightHoldStartTime = null;
    if (highlightTargetId == null) {
      highlightPhase = ChatHighlightPhase.idle;
      highlightFactor = 0;
      return;
    }
    if (highlightPhase == ChatHighlightPhase.fading) return;
    highlightPhase = ChatHighlightPhase.fading;
    highlightFadeStartTime = null;
    highlightFactor = 1.0;
    _ensureTicker();
    _markNeedsPaint();
  }

  /// Advance hold / fade by one tick. Returns `true` while overlay or pending
  /// arm still needs the ticker.
  bool tickHighlight(Duration elapsed) {
    if (highlightTargetId == null) {
      return pendingHighlightTargetId != null;
    }
    if (highlightDuration <= Duration.zero) {
      clearHighlight();
      return false;
    }

    if (highlightPhase == ChatHighlightPhase.solid) {
      highlightFactor = 1.0;
      if (!_holdClockActive) return true;
      final start = highlightHoldStartTime ??= elapsed;
      final holdUs = highlightDuration.inMicroseconds;
      if (holdUs <= 0 || (elapsed - start).inMicroseconds >= holdUs) {
        beginHighlightFade();
        // Fall through to fade tick with same elapsed.
      } else {
        return true;
      }
    }

    if (highlightPhase == ChatHighlightPhase.fading) {
      final fadeStart = highlightFadeStartTime ??= elapsed;
      final fadeUs = kHighlightFadeDuration.inMicroseconds;
      if (fadeUs <= 0) {
        clearHighlight();
        return false;
      }
      final t = ((elapsed - fadeStart).inMicroseconds / fadeUs).clamp(0.0, 1.0);
      if (t >= 1.0) {
        clearHighlight();
        return false;
      }
      // Linear fade: factor 1 → 0 over [kHighlightFadeDuration].
      highlightFactor = 1.0 - t;
      return true;
    }

    return false;
  }

  /// Drop highlight state.
  ///
  /// [animated] true → [beginHighlightFade] (user drag / interrupt).
  /// false → immediate clear (jumpTo, overlay, new animate re-arm).
  void clearHighlight({bool animated = false}) {
    if (animated) {
      beginHighlightFade();
      return;
    }
    pendingHighlightTargetId = null;
    _startHoldWhenArmed = false;
    _holdClockActive = false;
    highlightHoldStartTime = null;
    highlightFadeStartTime = null;
    highlightPhase = ChatHighlightPhase.idle;
    if (highlightTargetId == null && highlightFactor == 0.0) return;
    highlightTargetId = null;
    highlightFactor = 0.0;
    _markNeedsPaint();
  }

  /// Paints a full-width wash **under** the highlight target row.
  ///
  /// Soft solid during hold; fades over [kHighlightFadeDuration] after
  /// unselect. Called from the render paint path **before** message children
  /// so text and bubbles stay crisp. Bubble selected-fill is host-owned.
  void paintHighlight({
    required PaintingContext context,
    required Offset offset,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    final targetId = highlightTargetId;
    if (targetId == null) return;
    final factor = highlightFactor;
    if (factor <= 0.0) return;
    final target = _childForId(targetId);
    if (target == null) return; // user scrolled the target out of the build
    final childOffset = _offsetOfChild(target);
    if (childOffset >= viewportHeight ||
        childOffset + _heightOfChild(target) <= 0) {
      return;
    }
    final base = highlightColor;
    // `.a` is the normalized alpha channel (0..1) for [Color.withValues]; the
    // deprecated `.alpha` getter is 0..255 int and must not be used here.
    final alpha = (base.a * factor).clamp(0.0, 1.0);
    if (alpha <= 0.0) return;
    final paint = Paint()..color = base.withValues(alpha: alpha);
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy + childOffset,
      viewportWidth,
      _heightOfChild(target),
    );
    context.canvas.drawRect(rect, paint);
  }
}
