import 'package:chrome_foundation/src/sheet/chrome_sheet_route.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:chrome_foundation/src/theme/chrome_typography.dart';
import 'package:flutter/widgets.dart';

/// The measures of a [ChromeTooltip]'s box, per use: the pointer's tooltip
/// by the cursor ([pointer]) and the hint at a control a tap was refused on
/// ([hint]).
///
/// Colours are the theme's (`PanelTokens.tooltipFill`, `tooltipText`,
/// `tooltipBorder`); only shape and text measures differ by use.
@immutable
final class ChromeTooltipMetrics {
  /// Tooltip measures.
  const ChromeTooltipMetrics({
    required this.padding,
    required this.radius,
    required this.fontSize,
    required this.maxWidth,
    this.edge = 1,
    this.maxLines,
    this.textAlign = TextAlign.start,
  });

  /// A mouse resting on an item: a 1 px edge, 5 and 2 px of padding and
  /// 13 px text, rounded at 3, wide enough for a long name, up to 12 lines.
  static const pointer = ChromeTooltipMetrics(
    padding: EdgeInsets.fromLTRB(5, 2, 5, 2),
    radius: 3,
    fontSize: 13,
    maxWidth: 800,
    maxLines: 12,
  );

  /// The hint at a control the user tried and may not use: 14 px text,
  /// centred, 10 and 6 px of padding, rounded at 8, at most 260 px wide.
  static const hint = ChromeTooltipMetrics(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    radius: 8,
    fontSize: 14,
    maxWidth: 260,
    textAlign: TextAlign.center,
  );

  /// Space between the edge and the text.
  final EdgeInsets padding;

  /// Corner radius of the box.
  final double radius;

  /// Size of the text.
  final double fontSize;

  /// The widest the box is laid out.
  final double maxWidth;

  /// Width of the box's edge.
  final double edge;

  /// Most lines the text takes before an ellipsis; null lets it wrap.
  final int? maxLines;

  /// How the text lines up in the box.
  final TextAlign textAlign;
}

/// The chrome's one tooltip box: [text] in the theme's tooltip colours,
/// shaped by [metrics].
///
/// The box only: where it goes (by the cursor, at a tab) and when it shows
/// are its owner's. It takes no pointer, carries its own text root, so it
/// draws the chrome's text in an overlay entry too, and, as a [liveRegion],
/// is announced when it appears.
class ChromeTooltip extends StatelessWidget {
  /// A tooltip box showing [text].
  const ChromeTooltip({
    required this.text,
    this.metrics = ChromeTooltipMetrics.pointer,
    this.liveRegion = false,
    super.key,
  });

  /// What the tooltip says.
  final String text;

  /// Shape and text measures.
  final ChromeTooltipMetrics metrics;

  /// Whether assistive technology announces the text when it appears: a
  /// hint shown in answer to a tap is, a pointer's tooltip is not.
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final panel = ChromeThemeScope.panelOf(context);
    final m = metrics;
    return IgnorePointer(
      child: ChromeTextRoot(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: m.maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: panel.tooltipFill,
              border: Border.all(color: panel.tooltipBorder, width: m.edge),
              borderRadius: BorderRadius.circular(m.radius),
            ),
            child: Padding(
              padding: m.padding + EdgeInsets.all(m.edge),
              child: Semantics(
                liveRegion: liveRegion,
                child: Text(
                  text,
                  maxLines: m.maxLines,
                  overflow: switch (m.maxLines) {
                    null => null,
                    _ => TextOverflow.ellipsis,
                  },
                  textAlign: m.textAlign,
                  style: ChromeTypography.of(
                    context,
                  ).copyWith(color: panel.tooltipText, fontSize: m.fontSize),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
