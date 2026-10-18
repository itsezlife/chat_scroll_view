import 'dart:ui' show Offset, Rect, Size;

import 'package:chrome_foundation/src/menu/pointer_menu_metrics.dart';
import 'package:chrome_foundation/src/menu/pointer_menu_placement.dart';
import 'package:chrome_foundation/src/motion/pointer_menu_motion.dart';
import 'package:meta/meta.dart';

/// The state of a pointer menu's open animation at one moment of its clock.
///
/// The reference client's `PanelAnimation`: the menu is drawn at its final
/// size into a frame that grows from the corner at the pointer. Width grows
/// from half to full over the first 0.6 of the clock and height from 30% to
/// full over the first 0.9, each on `EaseOutCirc`; the opacity rises over the
/// first 0.3; and a strip 20% of the frame high sweeps down the frame,
/// uncovering the rows from the top.
@immutable
final class PointerMenuReveal {
  const PointerMenuReveal._({
    required this.widthFraction,
    required this.heightFraction,
    required this.opacity,
    required this.contentRevealed,
  });

  /// The state at [clock], 0 at the start of the show and 1 at its end;
  /// clamped to that range.
  factory PointerMenuReveal.at(double clock) {
    const circ = EaseOutCirc();
    final t = clock.clamp(0.0, 1.0);
    double within(double duration) => (t / duration).clamp(0.0, 1.0);
    const start = PointerMenuMetrics.startWidth;
    const heightStart = PointerMenuMetrics.startHeight;
    return PointerMenuReveal._(
      widthFraction:
          start +
          (1 - start) *
              circ.transform(within(PointerMenuMetrics.widthDuration)),
      heightFraction:
          heightStart +
          (1 - heightStart) *
              circ.transform(within(PointerMenuMetrics.heightDuration)),
      opacity: circ.transform(within(PointerMenuMetrics.opacityDuration)),
      contentRevealed: circ.transform(t),
    );
  }

  /// The frame's width as a fraction of the body's.
  final double widthFraction;

  /// The frame's height as a fraction of the body's.
  final double heightFraction;

  /// The opacity of the whole menu.
  final double opacity;

  /// How far the revealing strip has swept down the frame: 0 hides every row,
  /// 1 shows them all.
  final double contentRevealed;

  /// The frame inside a body of [size], anchored at [origin].
  Rect frame(Size size, PointerMenuOrigin origin) {
    final width = size.width * widthFraction;
    final height = size.height * heightFraction;
    return Rect.fromLTWH(
      origin.isLeft ? 0 : size.width - width,
      origin.isTop ? 0 : size.height - height,
      width,
      height,
    );
  }

  /// Where the revealing strip begins inside [frame]: rows above it show, rows
  /// below `top + PointerMenuMetrics.fadeHeight * frame.height` do not.
  Offset stripTop(Rect frame) =>
      Offset(frame.left, frame.top + frame.height * contentRevealed);
}
