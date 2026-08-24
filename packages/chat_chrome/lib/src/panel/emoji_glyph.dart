import 'package:flutter/material.dart';

/// Fixed-size emoji glyph (fixed-size centered emoji glyph).
///
/// Clips paint to [size]×[size] and optically centers via [FittedBox] so
/// skin-tone variants do not drift on different font metrics.
class EmojiGlyph extends StatelessWidget {
  /// Creates a clipped, centered emoji at [size] logical pixels.
  const EmojiGlyph({
    required this.glyph,
    required this.size,
    this.paintFraction = 0.88,
    super.key,
  });

  /// Emoji string to draw.
  final String glyph;

  /// Cell width and height.
  final double size;

  /// Drawn glyph diameter as a fraction of [size] (~34 in ~45 cell).
  final double paintFraction;

  static const TextHeightBehavior _heightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  @override
  Widget build(BuildContext context) {
    final paint = size * paintFraction;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: Center(
          child: SizedBox(
            width: paint,
            height: paint,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Text(
                glyph,
                textHeightBehavior: _heightBehavior,
                style: TextStyle(fontSize: paint, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
