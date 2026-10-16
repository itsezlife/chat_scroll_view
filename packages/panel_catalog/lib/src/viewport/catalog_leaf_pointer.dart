import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';

/// Viewport-owned tap / secondary-tap / long-press recognizers for paint-leaf
/// catalogs.
///
/// Maps the resolved [CatalogLeafHit] under the pointer into shell callbacks.
/// Does **not** own hit-testing ([leafAt] is supplied by the render object),
/// scroll drag, or press-scale animation.
///
/// ## Arena
///
/// [TapGestureRecognizer] is registered when [onLeafTap] or
/// [onLeafSecondaryTap] is non-null; it answers the primary button with the
/// first and the secondary with the second, so a right click never reaches
/// [onLeafTap] and a left click never reaches [onLeafSecondaryTap].
/// [LongPressGestureRecognizer] is created when [onLeafLongPressStart] is
/// non-null, but each pointer adds to it only when [leafLongPressEligible]
/// returns true (or when the predicate is null — every leaf). Skipping
/// ineligible leaves avoids the ~500ms tap cancel with no action that occurs
/// when a long-press recognizer competes on plain glyphs.
///
/// ## Long-press delay
///
/// A recognizer's deadline is fixed when it is made, so the delay asked of
/// [leafLongPressDelay] for a pointer picks one recognizer of a small set,
/// one per distinct delay, made on first use. A pointer the callback gives no
/// delay waits the platform's.
///
/// Call [addPointer] from the render object's [PointerDownEvent] path only
/// when [leafAt] returns a leaf. Header / padding downs skip this helper so
/// scroll drag alone owns the arena.
final class CatalogLeafPointer {
  /// Creates recognizers owned by [debugOwner] (the viewport render object).
  CatalogLeafPointer({required this.debugOwner});

  /// Gesture debug owner — the viewport render object.
  final Object debugOwner;

  /// Resolves the cell under a viewport-local position, or `null` when the
  /// pointer is over a header / padding / empty band.
  CatalogLeafHit? Function(Offset localPosition)? leafAt;

  /// Shell tap (insert / pick). Null skips tap recognizer registration.
  ValueChanged<CatalogLeafHit>? onLeafTap;

  /// Shell long-press start. Null skips the long-press recognizer entirely —
  /// [onLeafLongPressMove] / [onLeafLongPressEnd] are ignored until start is
  /// non-null.
  void Function(CatalogLeafHit hit, LongPressStartDetails details)?
  onLeafLongPressStart;

  /// Shell long-press drag update while a long-press session is live.
  void Function(CatalogLeafHit hit, LongPressMoveUpdateDetails details)?
  onLeafLongPressMove;

  /// Shell long-press end.
  void Function(CatalogLeafHit hit, LongPressEndDetails details)?
  onLeafLongPressEnd;

  /// Shell secondary tap (a mouse right click): the cell and where it was,
  /// in global coordinates. Null leaves the secondary button unrecognised.
  void Function(CatalogLeafHit hit, Offset globalPosition)? onLeafSecondaryTap;

  /// How long the press on [hit] by a pointer of [kind] must last to be a
  /// long press, or null for the platform's `kLongPressTimeout`.
  ///
  /// [Duration.zero] makes the press a long press at once: it starts as the
  /// event loop turns after the pointer went down, and a click that lifts
  /// sooner is still a tap.
  Duration? Function(CatalogLeafHit hit, PointerDeviceKind kind)?
  leafLongPressDelay;

  /// Per-leaf gate for registering [LongPressGestureRecognizer] on pointer
  /// down. When null, every leaf is eligible while [onLeafLongPressStart] is
  /// wired. When non-null, returns false to leave tap-only recognition on
  /// that leaf (host policy for contextual long-press actions).
  bool Function(CatalogLeafHit hit)? leafLongPressEligible;

  /// Fired when long-press is cancelled (arena lost / pointer cancel) so the
  /// host can release press scale. Tap cancel MUST NOT use this path — when
  /// long-press wins the arena, tap is cancelled while the pointer is still
  /// down and press scale MUST stay live until up / leave-bounds / drag.
  VoidCallback? onGestureCancel;

  /// When true, tap and long-press callbacks are silent (fling-cancel pointer
  /// that only stops inertial scroll).
  bool Function()? flingCancelSuppresses;

  TapGestureRecognizer? _tap;
  final _longPresses = <Duration?, LongPressGestureRecognizer>{};
  CatalogLeafHit? _downHit;

  /// Hit captured at the last [addPointer], if any.
  CatalogLeafHit? get downHit => _downHit;

  /// Forwards [event] to leaf recognizers when a leaf is under the pointer
  /// and at least one leaf callback is wired.
  void addPointer(PointerDownEvent event) {
    final resolve = leafAt;
    if (resolve == null) return;
    if (onLeafTap == null &&
        onLeafSecondaryTap == null &&
        onLeafLongPressStart == null) {
      return;
    }
    final hit = resolve(event.localPosition);
    _downHit = hit;
    if (hit == null) return;
    final longPressEligible =
        onLeafLongPressStart != null &&
        (leafLongPressEligible?.call(hit) ?? true);
    if (onLeafTap == null && onLeafSecondaryTap == null && !longPressEligible) {
      return;
    }
    _ensureRecognizers();
    _tap?.addPointer(event);
    if (longPressEligible) {
      _longPressFor(
        leafLongPressDelay?.call(hit, event.kind),
      ).addPointer(event);
    }
  }

  /// Drops recognizers. Safe to call twice.
  void dispose() {
    onGestureCancel = null;
    flingCancelSuppresses = null;
    onLeafTap = null;
    onLeafSecondaryTap = null;
    leafLongPressDelay = null;
    onLeafLongPressStart = null;
    onLeafLongPressMove = null;
    onLeafLongPressEnd = null;
    leafLongPressEligible = null;
    leafAt = null;
    _tap?.dispose();
    _tap = null;
    _disposeLongPresses();
    _downHit = null;
  }

  void _disposeLongPresses() {
    for (final recognizer in _longPresses.values) {
      recognizer.dispose();
    }
    _longPresses.clear();
  }

  // The tap recognizer takes a button only if it has a callback for it, so
  // wiring one button and not the other is what keeps the other out.
  void _ensureRecognizers() {
    if (onLeafTap != null || onLeafSecondaryTap != null) {
      (_tap ??= TapGestureRecognizer(debugOwner: debugOwner))
        ..onTap = onLeafTap == null ? null : _onTap
        ..onSecondaryTapUp = onLeafSecondaryTap == null
            ? null
            : _onSecondaryTapUp;
    } else {
      _tap?.dispose();
      _tap = null;
    }
    if (onLeafLongPressStart == null) _disposeLongPresses();
  }

  LongPressGestureRecognizer _longPressFor(Duration? delay) =>
      _longPresses[delay] ??=
          LongPressGestureRecognizer(debugOwner: debugOwner, duration: delay)
            ..onLongPressStart = _onLongPressStart
            ..onLongPressMoveUpdate = _onLongPressMoveUpdate
            ..onLongPressEnd = _onLongPressEnd
            ..onLongPressCancel = _onCancel;

  void _onTap() {
    if (flingCancelSuppresses?.call() ?? false) return;
    final hit = _downHit;
    final tap = onLeafTap;
    if (hit == null || tap == null) return;
    tap(hit);
  }

  // Only a mouse has a right button: a stylus barrel button reports the same
  // bit, and a long press is the secondary gesture of a finger.
  void _onSecondaryTapUp(TapUpDetails details) {
    if (flingCancelSuppresses?.call() ?? false) return;
    if (details.kind != PointerDeviceKind.mouse) return;
    final hit = _downHit;
    final secondary = onLeafSecondaryTap;
    if (hit == null || secondary == null) return;
    secondary(hit, details.globalPosition);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (flingCancelSuppresses?.call() ?? false) return;
    final hit = _downHit;
    final start = onLeafLongPressStart;
    if (hit == null || start == null) return;
    start(hit, details);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final hit = _downHit;
    final move = onLeafLongPressMove;
    if (hit == null || move == null) return;
    move(hit, details);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final hit = _downHit;
    final end = onLeafLongPressEnd;
    if (hit == null || end == null) return;
    end(hit, details);
  }

  void _onCancel() => onGestureCancel?.call();
}
