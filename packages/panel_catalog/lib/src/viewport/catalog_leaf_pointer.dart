import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';

/// Viewport-owned tap / long-press recognizers for paint-leaf catalogs.
///
/// Maps the resolved [CatalogLeafHit] under the pointer into shell callbacks.
/// Does **not** own hit-testing ([leafAt] is supplied by the render object),
/// scroll drag, or press-scale animation.
///
/// ## Arena
///
/// [TapGestureRecognizer] is registered when [onLeafTap] is non-null.
/// [LongPressGestureRecognizer] is created when [onLeafLongPressStart] is
/// non-null, but each pointer adds to it only when [leafLongPressEligible]
/// returns true (or when the predicate is null — every leaf). Skipping
/// ineligible leaves avoids the ~500ms tap cancel with no action that occurs
/// when a long-press recognizer competes on plain glyphs.
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
  LongPressGestureRecognizer? _longPress;
  CatalogLeafHit? _downHit;

  /// Hit captured at the last [addPointer], if any.
  CatalogLeafHit? get downHit => _downHit;

  /// Forwards [event] to leaf recognizers when a leaf is under the pointer
  /// and at least one leaf callback is wired.
  void addPointer(PointerDownEvent event) {
    final resolve = leafAt;
    if (resolve == null) return;
    if (onLeafTap == null && onLeafLongPressStart == null) return;
    final hit = resolve(event.localPosition);
    _downHit = hit;
    if (hit == null) return;
    final longPressEligible =
        onLeafLongPressStart != null &&
        (leafLongPressEligible?.call(hit) ?? true);
    if (onLeafTap == null && !longPressEligible) return;
    _ensureRecognizers();
    _tap?.addPointer(event);
    if (longPressEligible) {
      _longPress?.addPointer(event);
    }
  }

  /// Drops recognizers. Safe to call twice.
  void dispose() {
    onGestureCancel = null;
    flingCancelSuppresses = null;
    onLeafTap = null;
    onLeafLongPressStart = null;
    onLeafLongPressMove = null;
    onLeafLongPressEnd = null;
    leafLongPressEligible = null;
    leafAt = null;
    _tap?.dispose();
    _tap = null;
    _longPress?.dispose();
    _longPress = null;
    _downHit = null;
  }

  void _ensureRecognizers() {
    if (onLeafTap != null) {
      _tap ??= TapGestureRecognizer(debugOwner: debugOwner)..onTap = _onTap;
    } else {
      _tap?.dispose();
      _tap = null;
    }

    if (onLeafLongPressStart != null) {
      _longPress ??= LongPressGestureRecognizer(debugOwner: debugOwner)
        ..onLongPressStart = _onLongPressStart
        ..onLongPressMoveUpdate = _onLongPressMoveUpdate
        ..onLongPressEnd = _onLongPressEnd
        ..onLongPressCancel = _onCancel;
    } else {
      _longPress?.dispose();
      _longPress = null;
    }
  }

  void _onTap() {
    if (flingCancelSuppresses?.call() ?? false) return;
    final hit = _downHit;
    final tap = onLeafTap;
    if (hit == null || tap == null) return;
    tap(hit);
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
