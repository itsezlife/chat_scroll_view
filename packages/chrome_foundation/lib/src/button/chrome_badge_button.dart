import 'package:chrome_foundation/src/button/chrome_button_inks.dart';
import 'package:chrome_foundation/src/motion/chrome_ink.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:flutter/widgets.dart';

/// The geometry and type of a [ChromeBadgeButton].
@immutable
final class ChromeBadgeButtonMetrics {
  /// Metrics with every value given; the defaults are [standard]'s.
  const ChromeBadgeButtonMetrics({
    this.extent = 42,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
    this.textSize = 13,
    this.fontWeight = FontWeight.w600,
    this.badgeExtent = 18,
    this.badgeGap = 6,
    this.badgePadding = 5,
    this.badgeTextSize = 11,
    this.badgeFontWeight = FontWeight.w700,
  });

  /// A 42 tall button with 16 at each side and 12 above and below, its words
  /// semibold 13; its badge 18 tall, 6 after the words, 5 at each side of a
  /// bold 11 count.
  static const ChromeBadgeButtonMetrics standard = ChromeBadgeButtonMetrics();

  /// The height of the button.
  final double extent;

  /// The room around the button.
  final EdgeInsets padding;

  /// The size of the words.
  final double textSize;

  /// The weight of the words.
  final FontWeight fontWeight;

  /// The height of the badge, and its least width.
  final double badgeExtent;

  /// The gap between the words and the badge.
  final double badgeGap;

  /// The room at either side of the count in its badge.
  final double badgePadding;

  /// The size of the count.
  final double badgeTextSize;

  /// The weight of the count.
  final FontWeight badgeFontWeight;

  /// The height the button takes with its [padding].
  double get barExtent => extent + padding.vertical;

  @override
  bool operator ==(Object other) =>
      other is ChromeBadgeButtonMetrics &&
      other.extent == extent &&
      other.padding == padding &&
      other.textSize == textSize &&
      other.fontWeight == fontWeight &&
      other.badgeExtent == badgeExtent &&
      other.badgeGap == badgeGap &&
      other.badgePadding == badgePadding &&
      other.badgeTextSize == badgeTextSize &&
      other.badgeFontWeight == badgeFontWeight;

  @override
  int get hashCode => Object.hash(
    extent,
    padding,
    textSize,
    fontWeight,
    badgeExtent,
    badgeGap,
    badgePadding,
    badgeTextSize,
    badgeFontWeight,
  );
}

/// A fully rounded button whose words may carry a count in a badge after
/// them, the bottom button of a box under a pointer.
///
/// An action that adds is filled with the accent, its words in the colour on
/// the accent and its badge filled with that colour, the count in the
/// accent. A [destructive] one is flat, its words in the destructive colour
/// and its badge filled with it. A [count] that is null or not positive
/// shows no badge. The semantic label is the words and the count together.
class ChromeBadgeButton extends StatelessWidget {
  /// A button that calls [onPressed].
  const ChromeBadgeButton({
    required this.label,
    required this.onPressed,
    this.count,
    this.destructive = false,
    this.metrics = ChromeBadgeButtonMetrics.standard,
    super.key,
  });

  /// The key of the count's badge, for finding it.
  static const Key countKey = ValueKey('chrome-badge-button-count');

  /// The words.
  final String label;

  /// The count in the badge, or null for none.
  final int? count;

  /// Called on a tap.
  final VoidCallback onPressed;

  /// Whether the action takes something away.
  final bool destructive;

  /// The geometry and type.
  final ChromeBadgeButtonMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final foreground = destructive ? palette.destructive : palette.onAccent;
    final (badgeFill, badgeText) = destructive
        ? (palette.destructive, palette.onAccent)
        : (palette.onAccent, palette.accent);
    final radius = BorderRadius.all(Radius.circular(metrics.extent / 2));
    return Padding(
      padding: metrics.padding,
      child: Semantics(
        button: true,
        label: switch (count) {
          final count? => '$label $count',
          null => label,
        },
        excludeSemantics: true,
        child: ChromeInk(
          color: destructive
              ? ChromeButtonInks.pressOf(palette)
              : ChromeButtonInks.pressOnAccentOf(palette),
          hoverColor: destructive
              ? ChromeButtonInks.hoverOf(palette)
              : ChromeButtonInks.hoverOnAccentOf(palette),
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            height: metrics.extent,
            decoration: BoxDecoration(
              color: destructive ? null : palette.accent,
              borderRadius: radius,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: metrics.textSize,
                      fontWeight: metrics.fontWeight,
                    ),
                  ),
                ),
                if (count case final count? when count > 0) ...[
                  SizedBox(width: metrics.badgeGap),
                  Container(
                    key: countKey,
                    height: metrics.badgeExtent,
                    constraints: BoxConstraints(minWidth: metrics.badgeExtent),
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.badgePadding,
                    ),
                    decoration: BoxDecoration(
                      color: badgeFill,
                      borderRadius: BorderRadius.circular(
                        metrics.badgeExtent / 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: badgeText,
                        fontSize: metrics.badgeTextSize,
                        fontWeight: metrics.badgeFontWeight,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
