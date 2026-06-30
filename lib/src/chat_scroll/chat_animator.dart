import 'dart:async';

import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// Maximum distance (px) for which the close-path animation is used. Beyond
/// this the viewport falls back to the far-path: crossfade + jumpTo.
const double kCloseAnimateDistance = 2400;

/// Owns `animateTo` scroll animation and post-settle target highlight for
/// [RenderChatScrollView].
///
/// The render object keeps [fadeLayer] and applies [fadeOpacity] from
/// [tickAnimate] during paint — layer handles stay on the render side.
///
/// **Tick integration:** [tickAnimate] returns anchor scroll delta for the
/// close path; the far path mutates [fadeOpacity] in-place and returns 0.
/// [tickHighlight] advances the post-animate tint and reports whether it is
/// still active.
class ChatAnimator implements ChatScrollAnimator {
  /// Creates an animator bound to [controller] and render-object callbacks.
  ChatAnimator({
    required ChatScrollController controller,
    required double? Function(int id) offsetToBuiltMessage,
    required double Function(double messageHeight, double alignment)
    alignedTopForMessage,
    required RenderBox? Function(int id) childForId,
    required double Function(RenderBox child) offsetOfChild,
    required double Function(RenderBox child) heightOfChild,
    required VoidCallback markNeedsPaint,
    required VoidCallback ensureTicker,
    required VoidCallback cancelFling,
    required VoidCallback cancelBounceback,
    required void Function(int targetId) onAnimateComplete,
    Duration highlightDuration = const Duration(milliseconds: 1500),
    Color highlightColor = const Color(0x402196F3),
  }) : _controller = controller,
       _offsetToBuiltMessage = offsetToBuiltMessage,
       _alignedTopForMessage = alignedTopForMessage,
       _childForId = childForId,
       _offsetOfChild = offsetOfChild,
       _heightOfChild = heightOfChild,
       _markNeedsPaint = markNeedsPaint,
       _ensureTicker = ensureTicker,
       _cancelFling = cancelFling,
       _cancelBounceback = cancelBounceback,
       _onAnimateComplete = onAnimateComplete,
       _highlightDuration = highlightDuration,
       _highlightColor = highlightColor;

  final ChatScrollController _controller;
  final double? Function(int id) _offsetToBuiltMessage;
  final double Function(double messageHeight, double alignment)
  _alignedTopForMessage;
  final RenderBox? Function(int id) _childForId;
  final double Function(RenderBox child) _offsetOfChild;
  final double Function(RenderBox child) _heightOfChild;
  final VoidCallback _markNeedsPaint;
  final VoidCallback _ensureTicker;
  final VoidCallback _cancelFling;
  final VoidCallback _cancelBounceback;
  final void Function(int targetId) _onAnimateComplete;

  /// Active `animateTo`'s completer, or `null` when no animation is running.
  Completer<void>? animateCompleter;

  /// Target id for the in-flight animation; for the close-target branch the
  /// anchor has already been reassigned to this id at the start.
  int animateTargetId = 0;

  /// Viewport alignment (`0` = top, `1` = bottom) for the in-flight target.
  double animateAlignment = 0;

  /// Anchor pixel offset at animation start (close path) or the fade window
  /// progress driver (far path).
  double animateStartOffset = 0;

  /// Target anchor offset (close path) or unused progress sentinel (far path).
  double animateEndOffset = 0;

  /// Ticker timestamp when the current animation segment started.
  Duration? animateStartTime;

  /// Total duration of the active `animateTo`.
  Duration animateDuration = Duration.zero;

  /// Easing curve for the active `animateTo`.
  Curve animateCurve = Curves.linear;

  /// `true` while the far-target crossfade is active. Drives the render
  /// object's opacity wrap and the jumpTo at the fade midpoint.
  bool farAnimateActive = false;

  /// `true` after the far-path midpoint `jumpTo` has run.
  bool farAnimateJumped = false;

  /// Current fade opacity for far-target crossfade (1.0 → 0.0 → 1.0 across
  /// the animation duration). 1.0 when no far animation is in flight.
  double fadeOpacity = 1;

  /// Per-call preference from the active `animateTo`: whether to arm the
  /// post-settle highlight when the animation completes successfully.
  bool animateHighlight = true;

  /// Message id receiving the post-animate fade-out tint, or `null` when no
  /// highlight is active.
  int? highlightTargetId;

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
    if (highlightTargetId != null) clearHighlight();
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
  bool get isAnimating => animateCompleter != null;

  /// Whether a post-animate highlight tint is active.
  bool get hasHighlight => highlightTargetId != null;

  @override
  Future<void> animate(
    int targetId, {
    required Duration duration,
    required Curve curve,
    double alignment = 0.0,
    bool highlight = true,
  }) {
    // Re-entrant animateTo: cancel the in-flight one, schedule the new
    // one, and drop any leftover highlight — the user expects the new
    // target to own the attention. Other cancellers (drag, clamp, …) leave
    // the highlight running on purpose: it's a fade, not a focus lock.
    // Also cancel any spring-back so the new animation owns the anchor.
    clearHighlight();
    cancelAnimate();
    _cancelBounceback();
    if (duration <= Duration.zero) {
      // Zero duration is instant jumpTo — no animation phase and no highlight.
      _controller.jumpTo(targetId, alignment: alignment);
      return Future<void>.value();
    }

    animateHighlight = highlight;
    final completer = Completer<void>();
    animateCompleter = completer;
    animateTargetId = targetId;
    animateAlignment = alignment.clamp(0.0, 1.0);
    animateDuration = duration;
    animateCurve = curve;
    animateStartTime = null;

    final offsetToTarget = _offsetToBuiltMessage(targetId);
    if (offsetToTarget != null &&
        offsetToTarget.abs() <= kCloseAnimateDistance) {
      final child = _childForId(targetId);
      final endOffset = child != null
          ? _alignedTopForMessage(_heightOfChild(child), alignment)
          : 0.0;
      // Close path: re-base the anchor onto the target with its current
      // offset, then animate that offset toward the aligned position.
      _controller.reassignAnchor(targetId, offsetToTarget);
      animateStartOffset = offsetToTarget;
      animateEndOffset = endOffset;
      farAnimateActive = false;
      farAnimateJumped = false;
      fadeOpacity = 1.0;
    } else {
      // Far path: a crossfade — fade out, jumpTo at the midpoint, fade back.
      farAnimateActive = true;
      farAnimateJumped = false;
      animateStartOffset = 1.0;
      animateEndOffset = 0.0;
      fadeOpacity = 1.0;
    }
    _cancelFling();
    _ensureTicker();
    return completer.future;
  }

  /// Cancel the in-flight animation without arming a highlight.
  void cancelAnimate() {
    final completer = animateCompleter;
    if (completer == null) return;
    animateCompleter = null;
    animateStartTime = null;
    farAnimateActive = false;
    farAnimateJumped = false;
    if (fadeOpacity != 1.0) {
      fadeOpacity = 1.0;
      _markNeedsPaint();
    }
    // Completing the completer resumes `ChatScrollController.animateTo`, which
    // emits `ChatAnimateEnd` in its `finally` — don't emit it here too.
    if (!completer.isCompleted) completer.complete();
  }

  /// Drive the in-flight animation by one tick. Returns the additional scroll
  /// delta to apply (for the close path); the far path mutates [fadeOpacity]
  /// in-place and returns 0.
  double tickAnimate(Duration elapsed) {
    if (animateCompleter == null) return 0;
    final start = animateStartTime ??= elapsed;
    final totalUs = animateDuration.inMicroseconds;
    final elapsedUs = (elapsed - start).inMicroseconds;
    final t = totalUs <= 0 ? 1.0 : (elapsedUs / totalUs).clamp(0.0, 1.0);

    if (farAnimateActive) {
      // 0 → 0.5 → 1: opacity 1 → 0 → 1. Mid-point performs the jumpTo.
      // Apply the curve to each half independently. Using one
      // `curve.transform(t)` across the full 0..1 range would not guarantee
      // opacity == 0 at the midpoint for non-symmetric curves (e.g.
      // `easeInOut*` family transforms 0.5 to ≈0.5 but easeIn / easeOut
      // do not), so the synchronous `jumpTo` could happen while the
      // viewport is still partially visible. Per-half normalisation pins
      // opacity to exactly 0 at t == 0.5.
      if (t < 0.5) {
        final eased = animateCurve.transform(t * 2.0);
        fadeOpacity = (1.0 - eased).clamp(0.0, 1.0);
      } else {
        if (!farAnimateJumped) {
          farAnimateJumped = true;
          _controller.jumpTo(animateTargetId, alignment: animateAlignment);
        }
        final eased = animateCurve.transform((t - 0.5) * 2.0);
        fadeOpacity = eased.clamp(0.0, 1.0);
      }
      if (t >= 1.0) {
        fadeOpacity = 1.0;
        _completeAnimate();
      } else {
        _markNeedsPaint();
      }
      return 0;
    }

    // Close path: interpolate anchor offset linearly along the curve.
    final eased = animateCurve.transform(t);
    final target =
        animateStartOffset + (animateEndOffset - animateStartOffset) * eased;
    final delta = target - _controller.anchorPixelOffset;
    if (t >= 1.0) _completeAnimate();
    return delta;
  }

  void _completeAnimate() {
    final completer = animateCompleter;
    final targetId = animateTargetId;
    animateCompleter = null;
    animateStartTime = null;
    farAnimateActive = false;
    farAnimateJumped = false;
    // Successful settle (close-path reached t == 1 or far-path completed
    // its jumpTo + fade-in) → kick off the target highlight when both the
    // viewport gate (`highlightDuration > 0`) and the per-call
    // `animateHighlight` flag are set. Cancel (`cancelAnimate`) skips this
    // path, so an interrupted animateTo leaves no leftover tint.
    if (highlightDuration > Duration.zero && animateHighlight) {
      highlightTargetId = targetId;
      highlightStartTime = null;
      highlightFactor = 1.0;
      _ensureTicker();
      _markNeedsPaint();
    }
    _onAnimateComplete(targetId);
    if (completer != null && !completer.isCompleted) completer.complete();
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

  /// Drop any active post-animate highlight tint.
  void clearHighlight() {
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
