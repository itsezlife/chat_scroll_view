import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_stretch_overscroll.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Per-viewport runtime of one [ChatScrollPhysics]: the [fling] runner and
/// the [edge] effect state, both mutable and driven by the viewport ticker.
///
/// The render object owns exactly one and replaces it whole when the host
/// passes unequal physics, so a fling and an edge effect from different
/// pairings never run together. Replacing it does not stop anything by
/// itself — the owner cancels the old fling (emitting fling end) and resets
/// the old edge effect first.
@internal
final class ChatScrollMotion {
  /// Fresh, idle runtime for [physics].
  ChatScrollMotion(this.physics)
    : fling = ChatFlingMotion(physics.fling),
      edge = switch (physics.edgeEffect) {
        final ChatEdgeEffect$Stretch stretch => ChatStretchOverscroll(stretch),
      };

  /// The description this runtime was created from.
  final ChatScrollPhysics physics;

  /// Inertial travel runner for [ChatScrollPhysics.fling].
  final ChatFlingMotion fling;

  /// Edge-effect state for [ChatScrollPhysics.edgeEffect].
  final ChatEdgeEffectState edge;
}

/// Contract between the render object and one edge-effect strategy.
///
/// The render object keeps layout clamped and decides *when* motion reaches
/// a boundary pin; the strategy decides *how* the message layer responds and
/// when that response releases. The render object never encodes a
/// strategy's release rules itself.
///
/// All deltas and velocities use the chat sign convention: positive moves
/// content down, revealing older messages, and presses the oldest (top)
/// edge; negative presses the newest (bottom) edge.
///
/// Only the drag path (touch, stylus, trackpad pan) and the fling feed this
/// contract. Wheel, keyboard, scrollbar, and programmatic scrolling never
/// call [claim], [pull], or [absorbImpact].
@internal
abstract interface class ChatEdgeEffectState {
  /// Whether the effect is painted or its spring is running — the viewport
  /// ticker MUST keep running while this is `true`.
  bool get isActive;

  /// Whether a release spring is moving the effect right now. A press that
  /// lands while this is `true` catches the effect via [onDragStart] and
  /// must not produce a tap or long-press.
  bool get isSpringing;

  /// Finger down on the effect: a drag start, or a press that lands while
  /// the spring runs. Stops the spring and keeps a visible effect exactly
  /// where it is; a sub-visible remainder snaps to rest. Idempotent — a
  /// press that turns into a drag calls it twice.
  void onDragStart();

  /// First claim on drag motion, before layout consumes it. Returns the
  /// remainder layout may apply to the scroll origin.
  ///
  /// Only motion back toward content — opposite the pressed edge — is
  /// claimable; other motion passes through unchanged. [travel] is the part
  /// of `delta.abs()` content can still travel before a reached pin, in
  /// pixels (`0` at that pin, `delta.abs()` when the pin is not in play).
  double claim(double delta, {required double travel});

  /// Drag motion a reached pin could not consume, in pixels.
  ///
  /// [viewportHeight] normalizes the pull. [travel] is the remaining pin
  /// distance consumed before this remainder; [fits] marks short content
  /// (zero travel on both pins). Callers MUST NOT feed motion that content
  /// consumed.
  void pull(
    double unconsumedPx,
    double viewportHeight, {
    double travel = 0,
    bool fits = false,
  });

  /// Finger up with the drag's terminal [velocity] (px/s). Returns whether
  /// a content fling may start from this release; the caller still applies
  /// its own fling gates (minimum velocity, short content).
  bool onDragEnd(double velocity);

  /// A fling reached a pin; [velocity] is its leftover velocity (px/s),
  /// signed toward the pin it hit.
  void absorbImpact(double velocity);

  /// Advances the release spring to ticker [elapsed]. Returns whether the
  /// spring is still running and needs another painted frame.
  bool tick(Duration elapsed);

  /// Drops the effect to rest at once — jump, scroll-by, animate, overlay,
  /// controller or physics swap, bottom-inset change.
  void reset();

  /// Transform for the message layer at viewport [size], or `null` at rest.
  ///
  /// Applies to message and chunk-error children only; the floating day
  /// header and the scrollbar MUST stay outside it. Hit-testing, the paint
  /// transform reported to descendants, and row chrome paint tops MUST use
  /// the same matrix the paint pushes.
  Matrix4? paintTransform(Size size);
}
