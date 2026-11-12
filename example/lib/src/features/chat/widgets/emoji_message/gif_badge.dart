import 'package:flutter/material.dart';

/// The label a desktop chat shows over a GIF message while the pointer is on
/// it (and over the user's own last one): "GIF" in a dark pill at the GIF's
/// top start corner.
///
/// 13 px regular white text, padded 8 by 2, on black at `0x54`, its corners
/// half its height, [inset] in from the GIF's corner.
class GifBadge extends StatelessWidget {
  /// The badge.
  const GifBadge({super.key});

  /// How far the badge sits in from the GIF's top and start edges.
  static const double inset = 4;

  /// The text.
  static const String label = 'GIF';

  /// The pill's fill.
  static const Color background = Color(0x54000000);

  /// The text's colour.
  static const Color foreground = Color(0xFFFFFFFF);

  /// The text's size.
  static const double fontSize = 13;

  /// The padding around the text.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 2,
  );

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: const ShapeDecoration(
        color: background,
        shape: StadiumBorder(),
      ),
      child: Padding(
        padding: padding,
        child: Text(
          label,
          maxLines: 1,
          style: DefaultTextStyle.of(context).style.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w400,
            color: foreground,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}
