import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// The style every label of a row is set in, before a row's own effect: the
/// theme's label-large at the reference's 14 dp medium, in the menu's text
/// colour.
///
/// The theme gives the family and the line height; the size and weight are
/// `FloatingToolbar`'s (`setTextSize(COMPLEX_UNIT_DIP, 14)` with the medium
/// typeface) and the letter spacing is 0 as Android's text view has none, which
/// matters for the fit: the Material label's tracking would widen every row.
/// The row sizing (`splitSelectionMenuRow`, `sizeSelectionMenuPage`) measures
/// with this same style, so a box is exactly as wide as its label.
TextStyle selectionMenuLabelStyle(
  ThemeData theme,
  SelectionMenuTokens tokens,
) => (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
  fontSize: SelectionMenuMetrics.labelFontSize,
  fontWeight: FontWeight.w500,
  letterSpacing: 0,
  color: tokens.text,
);

/// The style of the Back row's label: 16 dp regular, the reference's
/// `mOverflowButtonText`.
TextStyle selectionMenuBackStyle(ThemeData theme, SelectionMenuTokens tokens) =>
    (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: SelectionMenuMetrics.backFontSize,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: tokens.text,
    );

/// The elevated rounded card the menu's pages live in.
///
/// It shrink-wraps the page. `Align` with both factors does it under the loose
/// constraints of an overlay: without the height factor `Align` would take the
/// whole height budget and park a tall empty box on the selection under a short
/// page. Its height is the page's: the More page sizes itself by the room, so
/// the card sets no height limit.
class SelectionMenuCard extends StatelessWidget {
  /// A card around [child], at most [maxWidth] wide.
  const SelectionMenuCard({
    required this.tokens,
    required this.maxWidth,
    required this.child,
    super.key,
  });

  /// The colours.
  final SelectionMenuTokens tokens;

  /// The widest the card may be.
  final double maxWidth;

  /// The pages.
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    widthFactor: 1,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        elevation: SelectionMenuTokens.elevation,
        shadowColor: tokens.shadow,
        borderRadius: BorderRadius.circular(SelectionMenuTokens.cornerRadius),
        clipBehavior: Clip.antiAlias,
        color: tokens.background,
        child: child,
      ),
    ),
  );
}

/// A text button of the main row: its label between [startPadding] and
/// [endPadding], 48 dp tall and 48 dp wide at least.
class SelectionMenuButton extends StatelessWidget {
  /// A button that shows [label] in [style].
  const SelectionMenuButton({
    required this.label,
    required this.style,
    required this.onPressed,
    required this.startPadding,
    required this.endPadding,
    this.selected = false,
    super.key,
  });

  /// The text, which is also the spoken label.
  final String label;

  /// The label style, colour included.
  final TextStyle style;

  /// Called on a tap; the button is disabled while null.
  final VoidCallback? onPressed;

  /// Padding before the label: 16, or 24 on the row's first button.
  final double startPadding;

  /// Padding after the label: 16, or 24 on the row's last button.
  final double endPadding;

  /// Whether the item is applied to the selection, spoken as selected.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = style.color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: color.withValues(alpha: 0.38),
          padding: EdgeInsetsDirectional.only(
            start: startPadding,
            end: endPadding,
          ),
          minimumSize: const Size(
            SelectionMenuMetrics.buttonMinWidth,
            SelectionMenuMetrics.rowHeight,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: style,
          shape: const RoundedRectangleBorder(),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// The More button that ends the main row: the vertical dots in a 56 by 48
/// frame, flush with the card's end, lit by a 40 dp disc
/// (`RIPPLE_MASK_CIRCLE_20DP`).
///
/// It has no tooltip. The menu is hosted under a `CompositedTransformFollower`,
/// and a `Tooltip` there asserts in `localToGlobal`
/// (flutter/flutter#178522).
class SelectionMenuMoreButton extends StatelessWidget {
  /// A More button spoken as [label].
  const SelectionMenuMoreButton({
    required this.label,
    required this.color,
    required this.onPressed,
    super.key,
  });

  /// The spoken label.
  final String label;

  /// The icon's colour.
  final Color color;

  /// Opens the More page.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    // The frame takes the tap; the IconButton inside is only the 40 dp disc
    // that lights up, since an IconButton's ink fills its whole box.
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: SelectionMenuMetrics.moreButtonWidth,
        height: SelectionMenuMetrics.rowHeight,
        child: Center(
          child: IconButton(
            onPressed: onPressed,
            tooltip: null,
            icon: const Icon(
              Icons.more_vert,
              size: SelectionMenuMetrics.iconSize,
            ),
            color: color,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            constraints: const BoxConstraints.tightFor(
              width: SelectionMenuMetrics.moreButtonInkDiameter,
              height: SelectionMenuMetrics.moreButtonInkDiameter,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A row of the More page: [height] tall, [padding] each side, an optional
/// leading icon or marker, the label on one line.
///
/// A tile with no [onTap] is disabled: its label is drawn at 0.38 and it takes
/// no tap.
class SelectionMenuTile extends StatelessWidget {
  /// A tile that shows [label] in [style].
  const SelectionMenuTile({
    required this.label,
    required this.style,
    required this.onTap,
    required this.iconColor,
    this.leading,
    this.leadingGap = 0,
    this.height = SelectionMenuMetrics.tileHeight,
    this.padding = const EdgeInsetsDirectional.symmetric(
      horizontal: SelectionMenuMetrics.tilePadding,
    ),
    this.selected = false,
    super.key,
  });

  /// The text, which is also the spoken label.
  final String label;

  /// The label style, colour included.
  final TextStyle style;

  /// Called on a tap; the tile is disabled while null.
  final VoidCallback? onTap;

  /// The colour of a leading icon.
  final Color iconColor;

  /// An icon, or a list marker, before the label.
  final Widget? leading;

  /// Space between [leading] and the label.
  final double leadingGap;

  /// The tile's height.
  final double height;

  /// Padding before the leading widget and after the label.
  final EdgeInsetsGeometry padding;

  /// Whether the item is applied to the selection, spoken as selected.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = style.color ?? iconColor;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: padding,
              child: Row(
                children: [
                  if (leading != null) ...[
                    IconTheme(
                      data: IconThemeData(
                        color: enabled
                            ? iconColor
                            : iconColor.withValues(alpha: 0.38),
                        size: SelectionMenuMetrics.iconSize,
                      ),
                      child: leading!,
                    ),
                    SizedBox(width: leadingGap),
                  ],
                  // The page is as wide as its widest label, so this only
                  // ellipsizes where the room across is shorter than that.
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: enabled
                          ? style
                          : style.copyWith(
                              color: color.withValues(alpha: 0.38),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hairline at the top edge of the Back row: one device pixel thick, as
/// the reference draws it (`1f / AndroidUtilities.density`).
class SelectionMenuDivider extends StatelessWidget {
  /// A divider in [color].
  const SelectionMenuDivider({required this.color, super.key});

  /// The line's colour.
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1 / MediaQuery.devicePixelRatioOf(context),
    child: ColoredBox(color: color),
  );
}

/// Fades the top and bottom 16 dp of [child] to nothing, so a row that runs
/// under an edge of the list dissolves instead of being cut.
///
/// The reference draws each row that reaches into either 16 dp band through a
/// `DST_IN` gradient of eight stops shaped by `PathInterpolator(0.42, 0, 0.58,
/// 1)` (`OverflowPanel.drawChild`, 1295-1345). One mask over the list changes
/// the same pixels: a row that does not reach a band has none in it.
class SelectionMenuListFade extends StatelessWidget {
  /// Fades the edges of [child].
  const SelectionMenuListFade({required this.child, super.key});

  /// The list.
  final Widget child;

  static const int _stops = 8;

  static Shader _shader(Rect bounds) {
    final fade = (SelectionMenuMetrics.listFadeHeight / bounds.height).clamp(
      0.0,
      0.5,
    );
    final positions = <double>[];
    final colors = <Color>[];
    for (var i = 0; i < _stops; i++) {
      final t = i / (_stops - 1);
      final alpha = Curves.easeInOut.transform(t);
      positions.add(t * fade);
      colors.add(Color.fromRGBO(0, 0, 0, alpha));
    }
    for (var i = 0; i < _stops; i++) {
      final t = i / (_stops - 1);
      final alpha = Curves.easeInOut.transform(1 - t);
      positions.add(1 - fade + t * fade);
      colors.add(Color.fromRGBO(0, 0, 0, alpha));
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: positions,
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: _shader,
    child: child,
  );
}
