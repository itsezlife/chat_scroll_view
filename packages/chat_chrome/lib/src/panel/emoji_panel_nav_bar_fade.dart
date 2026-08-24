import 'package:flutter/material.dart';

/// Bottom safe-inset scrim for keyboard-replacement panels.
///
/// Softens glyphs that scroll into the navigation-bar inset (same role as a
/// `clipToPadding = false` grid with a bottom fade). Drawn **over** the grid
/// and **under** the floating bottom bar; the panel fill behind stays opaque.
///
/// **Factor**: `clamp01((height − 32) / 16)` in logical pixels — zero below
/// 32, full at ≥ 48. Stops: base color, base × 0.66 alpha, transparent
/// (bottom → top).
class EmojiPanelNavBarFade extends StatelessWidget {
  /// Creates a bottom-inset fade of [height] using [color] as the theme fill.
  const EmojiPanelNavBarFade({
    required this.height,
    required this.color,
    super.key,
  });

  /// Safe / navigation-bar inset height (logical pixels).
  final double height;

  /// Panel background color.
  final Color color;

  /// Opacity scale for [height]: 0 below 32, 1 at ≥ 48.
  static double thirdButtonsFactor(double height) {
    if (height <= 0) return 0;
    return ((height - 32) / 16).clamp(0.0, 1.0);
  }

  static Color _multAlpha(Color c, double multiply) {
    if (multiply == 1) return c;
    return c.withValues(alpha: (c.a * multiply).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final factor = thirdButtonsFactor(height);
    if (height <= 0 || factor <= 0) {
      return const SizedBox.shrink();
    }

    final base = _multAlpha(color, factor);
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: <Color>[
                base,
                _multAlpha(base, 0.66),
                base.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
