import 'package:flutter/widgets.dart';

/// The scrim over the bottom safe band of a keyboard-replacement panel.
///
/// Softens content that scrolls into the navigation-bar or home-indicator
/// band, as a list with a bottom fade would. Drawn over the page and does not
/// take pointers; the panel fill behind stays opaque.
///
/// The scrim fades in with the band: nothing below [minHeight], full from
/// [fullHeight], so a thin gesture bar leaves the content alone and a
/// three-button bar does not.
class KeyboardNavBarFade extends StatelessWidget {
  /// A fade [height] logical pixels tall over [color], the panel fill.
  const KeyboardNavBarFade({
    required this.height,
    required this.color,
    super.key,
  });

  /// Below this band height the scrim is invisible.
  static const double minHeight = 32;

  /// From this band height the scrim is at full strength.
  static const double fullHeight = 48;

  /// The height of the safe band.
  final double height;

  /// The panel fill the scrim fades from.
  final Color color;

  /// The strength of the scrim for a band [height] tall: 0 up to
  /// [minHeight], 1 from [fullHeight], linear between.
  static double strengthFor(double height) {
    if (height <= minHeight) return 0;
    return ((height - minHeight) / (fullHeight - minHeight)).clamp(0.0, 1.0);
  }

  static Color _scaled(Color color, double by) =>
      by == 1 ? color : color.withValues(alpha: (color.a * by).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final strength = strengthFor(height);
    if (strength <= 0) return const SizedBox.shrink();
    final base = _scaled(color, strength);
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
                _scaled(base, 0.66),
                base.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
