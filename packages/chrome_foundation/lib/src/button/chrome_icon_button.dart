import 'package:chrome_foundation/src/button/chrome_button_inks.dart';
import 'package:chrome_foundation/src/motion/chrome_ink.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:flutter/widgets.dart';

/// A round icon button: [painter] drawn in an [extent] square, pressed in a
/// circle of that diameter with the platform's ink, washed under a mouse.
///
/// The painter draws its own colour; the ink is [ChromeButtonInks.pressOf]
/// and [ChromeButtonInks.hoverOf] of the palette in scope. [label] is the
/// button's semantic label.
class ChromeIconButton extends StatelessWidget {
  /// A button that calls [onPressed].
  const ChromeIconButton({
    required this.label,
    required this.painter,
    required this.onPressed,
    this.extent = defaultExtent,
    super.key,
  });

  /// The side of the button and the diameter of its ink: 40.
  static const double defaultExtent = 40;

  /// What the button is called to assistive technology.
  final String label;

  /// The icon, drawn over the whole [extent] square.
  final CustomPainter painter;

  /// Called on a tap.
  final VoidCallback onPressed;

  /// The side of the button.
  final double extent;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    return Semantics(
      button: true,
      label: label,
      child: ChromeInk(
        color: ChromeButtonInks.pressOf(palette),
        hoverColor: ChromeButtonInks.hoverOf(palette),
        circleRadius: extent / 2,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: extent,
          child: CustomPaint(painter: painter),
        ),
      ),
    );
  }
}
