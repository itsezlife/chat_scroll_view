import 'dart:ui' show Offset, Rect, Size, TextDirection;

import 'package:chrome_foundation/src/menu/pointer_menu_metrics.dart';
import 'package:flutter/painting.dart' show Alignment;

/// The corner of a pointer menu that stays at the pointer while it grows.
enum PointerMenuOrigin {
  /// The body's top leading corner is at the pointer: the menu opens down and
  /// away from the pointer's side.
  topLeft,

  /// The top trailing corner is at the pointer.
  topRight,

  /// The bottom leading corner is at the pointer: the menu opened upward.
  bottomLeft,

  /// The bottom trailing corner is at the pointer.
  bottomRight;

  /// Whether the origin is on the top edge.
  bool get isTop => this == topLeft || this == topRight;

  /// Whether the origin is on the left edge.
  bool get isLeft => this == topLeft || this == bottomLeft;

  /// The alignment of the origin corner in the body.
  Alignment get alignment => switch (this) {
    topLeft => Alignment.topLeft,
    topRight => Alignment.topRight,
    bottomLeft => Alignment.bottomLeft,
    bottomRight => Alignment.bottomRight,
  };
}

/// Where a pointer menu's body goes and which corner it grows from.
typedef PointerMenuPlacement = ({Rect body, PointerMenuOrigin origin});

/// Placement of a pointer menu and of its submenus: the reference client's
/// `PopupMenu::prepareGeometryFor`, on the body (the panel without its
/// shadow), clamped to the overlay instead of the screen.
abstract final class PointerMenuPlacements {
  /// The placement of a menu of [size] opened at [pointer] inside [bounds].
  ///
  /// The body's top leading corner goes `pointerOffset` from the pointer
  /// along the reading direction and level with it. If the body does not fit
  /// on that side it goes to the other, its edge `pointerOffset` from the
  /// pointer; if it does not fit below it goes up, its bottom at the pointer.
  /// A menu that still overflows is pushed in, right then left then bottom
  /// then top, so one taller than [bounds] spills off the bottom.
  ///
  /// In right-to-left the horizontal logic mirrors.
  static PointerMenuPlacement of({
    required Offset pointer,
    required Size size,
    required Rect bounds,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    const gap = PointerMenuMetrics.pointerOffset;
    final rtl = textDirection == TextDirection.rtl;
    var left = rtl ? pointer.dx - gap - size.width : pointer.dx + gap;
    var top = pointer.dy;
    var onLeft = !rtl;
    var onTop = true;
    final overflowsAway = rtl
        ? left < bounds.left
        : left + size.width > bounds.right;
    if (overflowsAway) {
      left = rtl ? pointer.dx + gap : pointer.dx - gap - size.width;
      onLeft = rtl;
    }
    if (top + size.height > bounds.bottom) {
      top = pointer.dy - size.height;
      onTop = false;
    }
    if (left + size.width > bounds.right) left = bounds.right - size.width;
    if (left < bounds.left) left = bounds.left;
    if (top + size.height > bounds.bottom) top = bounds.bottom - size.height;
    if (top < bounds.top) top = bounds.top;
    return (
      body: Rect.fromLTWH(left, top, size.width, size.height),
      origin: switch ((onTop, onLeft)) {
        (true, true) => PointerMenuOrigin.topLeft,
        (true, false) => PointerMenuOrigin.topRight,
        (false, true) => PointerMenuOrigin.bottomLeft,
        (false, false) => PointerMenuOrigin.bottomRight,
      },
    );
  }

  /// The placement of a submenu of [size] opened from the row of its parent
  /// whose top is [rowTop] (in the same coordinates as [parent], the parent's
  /// body).
  ///
  /// The submenu's leading edge touches the parent's trailing edge, and its
  /// panel starts `verticalPadding` above the row, so its first row is level
  /// with the row that opened it. If it does not fit it opens on the parent's
  /// other side; if it is too low it is pushed up to [bounds]' bottom.
  static PointerMenuPlacement submenu({
    required Rect parent,
    required double rowTop,
    required Size size,
    required Rect bounds,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final rtl = textDirection == TextDirection.rtl;
    var left = rtl ? parent.left - size.width : parent.right;
    var onLeft = !rtl;
    final overflows = rtl
        ? left < bounds.left
        : left + size.width > bounds.right;
    if (overflows) {
      left = rtl ? parent.right : parent.left - size.width;
      onLeft = rtl;
    }
    var top = rowTop - PointerMenuMetrics.verticalPadding;
    if (top + size.height > bounds.bottom) top = bounds.bottom - size.height;
    if (top < bounds.top) top = bounds.top;
    if (left + size.width > bounds.right) left = bounds.right - size.width;
    if (left < bounds.left) left = bounds.left;
    return (
      body: Rect.fromLTWH(left, top, size.width, size.height),
      origin: onLeft ? PointerMenuOrigin.topLeft : PointerMenuOrigin.topRight,
    );
  }
}
