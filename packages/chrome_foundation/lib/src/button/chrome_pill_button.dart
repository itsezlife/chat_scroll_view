import 'package:chrome_foundation/src/button/chrome_button_inks.dart';
import 'package:chrome_foundation/src/motion/chrome_ink.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:flutter/widgets.dart';

/// A small pill button: [child] in a band [height] tall, [padding] in from
/// either side, on a fully rounded [fill] when there is one.
///
/// A filled pill presses with [ChromeButtonInks.pressOnAccentOf]; a plain
/// one with [ChromeButtonInks.pressOf]; both wash with
/// [ChromeButtonInks.hoverOf] under a mouse. A pill that is not [enabled]
/// keeps its place but takes no press and is left out of the semantics
/// tree, so two pills can trade places by fading one out.
class ChromePillButton extends StatelessWidget {
  /// A pill that calls [onPressed].
  const ChromePillButton({
    required this.onPressed,
    required this.padding,
    required this.child,
    this.fill,
    this.enabled = true,
    this.height = defaultHeight,
    super.key,
  });

  /// The height of the band: 28.
  static const double defaultHeight = 28;

  /// Called on a tap.
  final VoidCallback onPressed;

  /// The room at either side of [child].
  final double padding;

  /// The fill, or null for none.
  final Color? fill;

  /// Whether the pill takes a press.
  final bool enabled;

  /// The height of the band; the pill's corners are half of it.
  final double height;

  /// What the pill shows, usually its words.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final radius = BorderRadius.circular(height / 2);
    return IgnorePointer(
      ignoring: !enabled,
      child: Semantics(
        button: true,
        excludeSemantics: !enabled,
        child: ChromeInk(
          color: switch (fill) {
            null => ChromeButtonInks.pressOf(palette),
            _ => ChromeButtonInks.pressOnAccentOf(palette),
          },
          hoverColor: ChromeButtonInks.hoverOf(palette),
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: padding),
            alignment: Alignment.center,
            decoration: switch (fill) {
              final fill? => BoxDecoration(color: fill, borderRadius: radius),
              null => null,
            },
            child: child,
          ),
        ),
      ),
    );
  }
}
