import 'package:chrome_foundation/src/button/chrome_button_inks.dart';
import 'package:chrome_foundation/src/motion/chrome_ink.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:flutter/widgets.dart';

/// The geometry and type of a [ChromeBarButton].
@immutable
final class ChromeBarButtonMetrics {
  /// Metrics with every value given; the defaults are [standard]'s.
  const ChromeBarButtonMetrics({
    this.extent = 48,
    this.margin = 8,
    this.textSize = 14,
    this.fontWeight = FontWeight.w500,
  });

  /// A 48 tall button inset 8 from its bar, its words 14 at the medium
  /// weight.
  static const ChromeBarButtonMetrics standard = ChromeBarButtonMetrics();

  /// The height of the button, and of the flat bar.
  final double extent;

  /// The room around the filled button, from every edge of its bar.
  final double margin;

  /// The size of the words.
  final double textSize;

  /// The weight of the words.
  final FontWeight fontWeight;

  /// The height of the bar the button takes: a filled one with its margin
  /// above and below, a flat one its [extent] alone.
  double barExtentOf({required bool destructive}) =>
      destructive ? extent : extent + 2 * margin;

  @override
  bool operator ==(Object other) =>
      other is ChromeBarButtonMetrics &&
      other.extent == extent &&
      other.margin == margin &&
      other.textSize == textSize &&
      other.fontWeight == fontWeight;

  @override
  int get hashCode => Object.hash(extent, margin, textSize, fontWeight);
}

/// The button along the bottom of a sheet, the full width of its bar.
///
/// An action that adds is a filled pill in the accent, [metrics]' margin in
/// from every edge of the bar, its words in the colour on the accent. A
/// [destructive] one is a flat bar the full width, its words in the
/// destructive colour. The words take one line, ellipsized.
class ChromeBarButton extends StatelessWidget {
  /// A button that calls [onPressed].
  const ChromeBarButton({
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.metrics = ChromeBarButtonMetrics.standard,
    super.key,
  });

  /// The words.
  final String label;

  /// Called on a tap.
  final VoidCallback onPressed;

  /// Whether the action takes something away.
  final bool destructive;

  /// The geometry and type.
  final ChromeBarButtonMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: destructive ? palette.destructive : palette.onAccent,
        fontSize: metrics.textSize,
        fontWeight: metrics.fontWeight,
      ),
    );
    final radius = BorderRadius.circular(metrics.extent / 2);
    return Semantics(
      button: true,
      child: destructive
          ? ChromeInk(
              color: ChromeButtonInks.pressOf(palette),
              hoverColor: ChromeButtonInks.hoverOf(palette),
              onTap: onPressed,
              child: SizedBox(
                height: metrics.extent,
                child: Center(child: text),
              ),
            )
          : Padding(
              padding: EdgeInsets.all(metrics.margin),
              child: ChromeInk(
                color: ChromeButtonInks.pressOnAccentOf(palette),
                hoverColor: ChromeButtonInks.hoverOnAccentOf(palette),
                borderRadius: radius,
                onTap: onPressed,
                child: Container(
                  height: metrics.extent,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: radius,
                  ),
                  alignment: Alignment.center,
                  child: text,
                ),
              ),
            ),
    );
  }
}
