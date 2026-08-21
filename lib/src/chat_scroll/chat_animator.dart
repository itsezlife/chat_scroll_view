import 'dart:async';
import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_dev_log.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// Maximum distance (px) for which the close-path animation is used. Beyond
/// this the viewport falls back to the far-path stitch.
const double kCloseAnimateDistance = 2400;

/// How long [AnimateToLoadPolicy.preferBuilt] waits for the target row to
/// enter the build range before forcing a stitch.
const Duration kPreferBuiltTimeout = Duration(milliseconds: 300);

/// Owns `animateTo` scroll animation and post-settle target highlight for
/// [RenderChatScrollView].
///
/// Close-path endpoint geometry comes from [closePathEndOffsetFor] — for the
/// known conversation newest this is tail-pin top (`bottomEdge - height`), not
/// band alignment. See [ChatScrollController.animateTo].
///
/// **Tick integration:** [tickAnimate] returns anchor scroll delta for the
/// close path; the far-path stitch mutates [stitchProgress] and returns 0.
/// [tickHighlight] advances the post-animate tint and reports whether it is
/// still active.
///
/// **Far path (stitch):** capture outgoing rows → `jumpTo` → dual-translate
/// outgoing/incoming (no viewport opacity fade). See architecture doc
/// `11-animation-integration.md`.
class ChatAnimator implements ChatScrollAnimator {
  /// Creates an animator bound to [controller] and render-object callbacks.
  ChatAnimator({
    required ChatScrollController controller,
    required double? Function(int id) offsetToBuiltMessage,
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
    required VoidCallback markNeedsPaint,
    required VoidCallback markNeedsLayout,
    required VoidCallback ensureTicker,
    required VoidCallback cancelFling,
    required VoidCallback cancelBounceback,

    /// Capture visible outgoing rows before the stitch jump. Render-owned.
    required void Function(int targetId) prepareStitchCapture,

    /// Clear stitch pin / frozen tops on cancel or settle. Render-owned.
    required VoidCallback clearStitchCapture,
    Duration highlightDuration = const Duration(milliseconds: 1500),
    Color highlightColor = const Color(0x402196F3),
    Duration preferBuiltTimeout = kPreferBuiltTimeout,
  }) : _controller = controller,
       _offsetToBuiltMessage = offsetToBuiltMessage,
       _closePathEndOffsetFor = closePathEndOffsetFor,
       _isTailClosePathTarget = isTailClosePathTarget,
       _childForId = childForId,
       _offsetOfChild = offsetOfChild,
       _heightOfChild = heightOfChild,
       _isHighlightReady = isHighlightReady,
       _shouldDropPendingHighlight = shouldDropPendingHighlight,
       _markNeedsPaint = markNeedsPaint,
       _markNeedsLayout = markNeedsLayout,
       _ensureTicker = ensureTicker,
       _cancelFling = cancelFling,
       _cancelBounceback = cancelBounceback,
       _prepareStitchCapture = prepareStitchCapture,
       _clearStitchCapture = clearStitchCapture,
       _highlightDuration = highlightDuration,
       _highlightColor = highlightColor,
       _preferBuiltTimeout = preferBuiltTimeout;

  final ChatScrollController _controller;
  final double? Function(int id) _offsetToBuiltMessage;
  final double Function(int targetId, double messageHeight, double alignment)
  _closePathEndOffsetFor;
  final bool Function(int targetId) _isTailClosePathTarget;
  final RenderBox? Function(int id) _childForId;
  final double Function(RenderBox child) _offsetOfChild;
  final double Function(RenderBox child) _heightOfChild;
  final bool Function(int id) _isHighlightReady;
  final bool Function(int id) _shouldDropPendingHighlight;
  final VoidCallback _markNeedsPaint;
  final VoidCallback _markNeedsLayout;
  final VoidCallback _ensureTicker;
  final VoidCallback _cancelFling;
  final VoidCallback _cancelBounceback;
  final void Function(int targetId) _prepareStitchCapture;
  final VoidCallback _clearStitchCapture;
  final Duration _preferBuiltTimeout;

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

  /// `true` while waiting for the target row under [preferBuilt].
  bool preferBuiltWaiting = false;

  /// Close or stitch path has been entered for the in-flight animate.
  bool _pathStarted = false;

  /// Ticker time when preferBuilt wait began (null until first tick).
  Duration? _preferBuiltStartElapsed;

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

  /// Per-call preference from the active `animateTo`: whether to arm the
  /// post-settle highlight when the animation completes successfully.
  bool animateHighlight = true;

  /// Message id receiving the post-animate fade-out tint, or `null` when no
  /// highlight is active.
  int? highlightTargetId;

  /// Post-animate highlight waiting for [isHighlightReady] — set when
  /// `animateTo` settles before the target message has loaded.
  int? pendingHighlightTargetId;

  /// Ticker time at the start of the active highlight; combined with
  /// [highlightDuration] this drives the per-frame opacity.
  Duration? highlightStartTime;

  /// Current opacity factor (0..1) of the highlight; 1 at the start, 0 at
  /// the end. Updated by [tickHighlight] each tick; read by [paintHighlight]
  /// so paint never has to look at ticker state.
  double highlightFactor = 0;

  /// Configurable: how long the post-animate highlight stays on the target.
  /// Zero disables the highlight entirely.
  Duration _highlightDuration;

  /// See [highlightDuration] setter.
  Duration get highlightDuration => _highlightDuration;
  set highlightDuration(Duration value) {
    if (_highlightDuration == value) return;
    _highlightDuration = value;
    // An in-flight fade computes `t = elapsed / total`; swapping `total`
    // without rebasing `highlightStartTime` makes `t` jump discontinuously
    // on the next tick. Easier and more honest: drop the active highlight
    // — the new duration is "from now on", not "retroactively reshape the
    // existing fade". `Duration.zero` clears synchronously so a hard
    // opt-out doesn't have to wait for the next ticker frame.
    if (highlightTargetId != null || pendingHighlightTargetId != null) {
      clearHighlight();
    }
  }

  /// Configurable: peak colour of the highlight overlay. Faded to fully
  /// transparent over [highlightDuration].
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

  /// Whether a post-animate highlight tint is active.
  bool get hasHighlight => highlightTargetId != null;

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
  }) {
    final align = alignment.clamp(0.0, 1.0);

    // Telegram `RecyclerAnimationScrollHelper.scrollToPosition`:
    //   if (recyclerView.fastScrollAnimationRunning) return;
    // Keep the in-flight motion. Same destination → coalesce onto its future;
    // any other request is dropped (not cancel+replace).
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
      if (highlight) _requestHighlight(targetId);
      return Future<void>.value();
    }

    // Fresh animate owns attention: drop leftover highlight / spring-back.
    // (Re-entrant different-target spam never reaches here — ignored above.)
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
    preferBuiltWaiting = false;
    _preferBuiltStartElapsed = null;
    _pathStarted = false;
    _stitchMeasureLayoutAsked = false;
    _lastProgressBucket = -1;

    final offsetNow = _offsetToBuiltMessage(targetId);
    log.event('animate.start', {
      'target': targetId,
      'align': DevLogFormat.ratio(animateAlignment),
      'durationMs': duration.inMilliseconds,
      'loadPolicy': loadPolicy.name,
      'highlight': highlight,
      'offsetToTarget': offsetNow == null ? 'null' : DevLogFormat.f(offsetNow),
      'anchorId': _controller.anchorMessageId,
      'anchorY': DevLogFormat.f(_controller.anchorPixelOffset),
    });

    _cancelFling();
    _tryBeginPath();
    _ensureTicker();
    return completer.future;
  }

  /// `true` when [targetId] is built and already at its close-path end Y.
  bool _isAlreadyAtAlignedTarget(int targetId, double alignment) {
    final child = _childForId(targetId);
    if (child == null) return false;
    final top = _offsetToBuiltMessage(targetId);
    if (top == null) return false;
    final end = _closePathEndOffsetFor(
      targetId,
      _heightOfChild(child),
      alignment,
    );
    return (top - end).abs() < _settleEpsilon;
  }

  /// Re-evaluate path after layout (preferBuilt wait). Must not call
  /// [markNeedsLayout] / [jumpTo] synchronously — those re-enter layout.
  ///
  /// One layout is enough: if the target still is not built, stitch now
  /// (Telegram does not idle-wait when the row is missing).
  void onLayoutOpportunity({required double viewportHeight}) {
    if (animateCompleter == null || !preferBuiltWaiting || _pathStarted) {
      return;
    }

    final offsetToTarget = _offsetToBuiltMessage(animateTargetId);
    if (offsetToTarget != null &&
        offsetToTarget.abs() <= kCloseAnimateDistance) {
      log.event('path.preferBuilt.readyClose', {
        'target': animateTargetId,
        'offset': DevLogFormat.f(offsetToTarget),
        'vh': DevLogFormat.f(viewportHeight),
      });
      preferBuiltWaiting = false;
      _preferBuiltStartElapsed = null;
      _beginClose(offsetToTarget);
      return;
    }

    // Built-but-far, or still missing after this layout → stitch (deferred).
    log.event('path.preferBuilt.forceStitch', {
      'target': animateTargetId,
      'offset': offsetToTarget == null
          ? 'null'
          : DevLogFormat.f(offsetToTarget),
      'vh': DevLogFormat.f(viewportHeight),
    });
    preferBuiltWaiting = false;
    _preferBuiltStartElapsed = null;
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
    // Start the clock at measure time (Telegram starts ValueAnimator after
    // the layout listener, not after an idle gap).
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

  Duration _stitchDuration(double scrollLength, double viewportHeight) {
    final raw = ((scrollLength / viewportHeight) + 1.0) * 200.0;
    final ms = raw.clamp(300.0, 1300.0).round();
    return Duration(milliseconds: ms);
  }

  void _tryBeginPath() {
    final offsetToTarget = _offsetToBuiltMessage(animateTargetId);
    if (offsetToTarget != null &&
        offsetToTarget.abs() <= kCloseAnimateDistance) {
      log.event('path.close', {
        'target': animateTargetId,
        'offset': DevLogFormat.f(offsetToTarget),
      });
      preferBuiltWaiting = false;
      _preferBuiltStartElapsed = null;
      _beginClose(offsetToTarget);
      return;
    }

    if (loadPolicy == AnimateToLoadPolicy.preferBuilt &&
        offsetToTarget == null) {
      log.event('path.preferBuilt.wait', {
        'target': animateTargetId,
        'timeoutMs': _preferBuiltTimeout.inMilliseconds,
      });
      preferBuiltWaiting = true;
      // Kick a layout so the target can enter the build range. Safe: called
      // from [animate], not from inside performLayout.
      _markNeedsLayout();
      return;
    }

    log.event('path.stitch', {
      'target': animateTargetId,
      'reason': offsetToTarget == null ? 'notBuilt' : 'tooFar',
      'offset': offsetToTarget == null
          ? 'null'
          : DevLogFormat.f(offsetToTarget),
      'loadPolicy': loadPolicy.name,
    });
    preferBuiltWaiting = false;
    _preferBuiltStartElapsed = null;
    _beginStitch();
  }

  void _beginClose(double offsetToTarget) {
    _pathStarted = true;
    preferBuiltWaiting = false;
    _preferBuiltStartElapsed = null;
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
    log.event('close.begin', {
      'target': animateTargetId,
      'startY': DevLogFormat.f(animateStartOffset),
      'endY': DevLogFormat.f(animateEndOffset),
      'hasChild': child != null,
      'tailTarget': _isTailClosePathTarget(animateTargetId),
    });
    // Zero travel (already at end) — finish without a 300ms empty tween.
    if ((animateEndOffset - animateStartOffset).abs() < _settleEpsilon) {
      log.event('close.noop', {'target': animateTargetId});
      _completeAnimate();
    }
  }

  void _beginStitch() {
    _pathStarted = true;
    preferBuiltWaiting = false;
    _preferBuiltStartElapsed = null;
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
    log.event('stitch.jumped', {
      'target': animateTargetId,
      'anchorAfter': _controller.anchorMessageId,
      'anchorYAfter': DevLogFormat.f(_controller.anchorPixelOffset),
    });
    _markNeedsLayout();
  }

  /// Cancel the in-flight animation without arming a highlight.
  void cancelAnimate() {
    final completer = animateCompleter;
    if (completer == null) return;
    log.event('animate.cancel', {
      'target': animateTargetId,
      'far': farAnimateActive,
      'measured': stitchMeasured,
      'progress': DevLogFormat.ratio(stitchProgress),
      'preferBuiltWaiting': preferBuiltWaiting,
    });
    animateCompleter = null;
    animateStartTime = null;
    _pendingSettleTargetId = null;
    preferBuiltWaiting = false;
    _preferBuiltStartElapsed = null;
    _pathStarted = false;
    _stitchMeasureLayoutAsked = false;
    _lastProgressBucket = -1;
    final wasStitch = farAnimateActive;
    farAnimateActive = false;
    farAnimateJumped = false;
    stitchMeasured = false;
    stitchProgress = 0;
    if (wasStitch) {
      _clearStitchCapture();
      _markNeedsPaint();
    }
    if (!completer.isCompleted) completer.complete();
  }

  /// Drive the in-flight animation by one tick. Returns the additional scroll
  /// delta to apply (for the close path); stitch mutates [stitchProgress].
  double tickAnimate(Duration elapsed) {
    if (animateCompleter == null) return 0;

    if (preferBuiltWaiting) {
      _preferBuiltStartElapsed ??= elapsed;
      final waited = elapsed - _preferBuiltStartElapsed!;
      final offsetToTarget = _offsetToBuiltMessage(animateTargetId);
      if (offsetToTarget != null &&
          offsetToTarget.abs() <= kCloseAnimateDistance) {
        log.event('path.preferBuilt.tickClose', {
          'target': animateTargetId,
          'waitedMs': waited.inMilliseconds,
          'offset': DevLogFormat.f(offsetToTarget),
        });
        _beginClose(offsetToTarget);
        // Fall through to close-path tick below.
      } else if (offsetToTarget != null || waited >= _preferBuiltTimeout) {
        log.event('path.preferBuilt.tickStitch', {
          'target': animateTargetId,
          'waitedMs': waited.inMilliseconds,
          'offset': offsetToTarget == null
              ? 'null'
              : DevLogFormat.f(offsetToTarget),
        });
        _beginStitch();
        return 0;
      } else {
        // Still waiting — do **not** markNeedsLayout every tick (that makes
        // pumpAndSettle hang forever).
        return 0;
      }
    }

    if (farAnimateActive) {
      if (!stitchMeasured) {
        // Prefer real post-jump layout measure (Telegram OnLayoutChange).
        // Paint already uses provisional off-screen offsets for incoming via
        // [_stitchPaintDy] — do **not** finalize measure here or a later
        // layout geom pass is ignored (`stitchMeasured` already true).
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
    _preferBuiltStartElapsed = null;
    _stitchMeasureLayoutAsked = false;
    _lastProgressBucket = -1;
    farAnimateActive = false;
    farAnimateJumped = false;
    stitchMeasured = false;
    stitchProgress = 0;
    if (wasFarPath) {
      _clearStitchCapture();
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
    // Successful settle (close-path reached t == 1 or far-path completed
    // its jumpTo + fade-in) → kick off the target highlight when both the
    // viewport gate (`highlightDuration > 0`) and the per-call
    // `animateHighlight` flag are set. Cancel (`cancelAnimate`) skips this
    // path, so an interrupted animateTo leaves no leftover tint. When the
    // target slot is still a skeleton, arm is deferred via
    // [pendingHighlightTargetId] until [tryArmPendingHighlight].
    if (highlightDuration > Duration.zero && animateHighlight) {
      _requestHighlight(targetId);
    }
    _pendingSettleTargetId = targetId;
    _markNeedsPaint();
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _requestHighlight(int targetId) {
    if (_shouldDropPendingHighlight(targetId)) return;
    if (_isHighlightReady(targetId)) {
      _armHighlight(targetId);
    } else {
      pendingHighlightTargetId = targetId;
    }
  }

  void _armHighlight(int targetId) {
    highlightTargetId = targetId;
    highlightStartTime = null;
    highlightFactor = 1.0;
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
    _armHighlight(id);
    return true;
  }

  /// Advance the highlight fade by one tick. Returns `true` when the
  /// highlight is still active after the update; `false` once it has ended
  /// (in which case state has been cleared).
  bool tickHighlight(Duration elapsed) {
    if (highlightTargetId == null) return false;
    final start = highlightStartTime ??= elapsed;
    final dt = elapsed - start;
    final totalUs = highlightDuration.inMicroseconds;
    if (totalUs <= 0) {
      clearHighlight();
      return false;
    }
    final t = (dt.inMicroseconds / totalUs).clamp(0.0, 1.0);
    if (t >= 1.0) {
      clearHighlight();
      return false;
    }
    highlightFactor = 1.0 - t;
    return true;
  }

  /// Drop any active post-animate highlight tint and any deferred arm.
  void clearHighlight() {
    pendingHighlightTargetId = null;
    if (highlightTargetId == null) return;
    highlightTargetId = null;
    highlightStartTime = null;
    highlightFactor = 0.0;
    _markNeedsPaint();
  }

  /// Draws a full-width tint over the target message after a successful
  /// `animateTo`. Fades from full to 0 over [highlightDuration].
  ///
  /// Called from the render object's paint path, after messages and before the
  /// day header and scrollbar, so chrome stays on top.
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
