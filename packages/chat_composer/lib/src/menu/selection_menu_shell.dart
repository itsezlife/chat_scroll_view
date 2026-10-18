import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// The style every label of the menu is set in, before a row's own effect:
/// the theme's body-large at 16 in the menu's text colour.
///
/// The main row measures its split with this same style, so it breaks exactly
/// where it would run out of width.
TextStyle selectionMenuLabelStyle(
  ThemeData theme,
  SelectionMenuTokens tokens,
) => (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
  fontSize: SelectionMenuMetrics.labelFontSize,
  color: tokens.text,
);

/// The elevated rounded card the menu's pages live in.
///
/// It shrink-wraps the page. `Align` with both factors does it under the loose
/// constraints of an overlay: without the height factor `Align` would take
/// the whole height budget and park a tall empty box on the selection under a
/// short page.
class SelectionMenuCard extends StatelessWidget {
  /// A card around [child], at most [maxWidth] by [maxHeight].
  const SelectionMenuCard({
    required this.tokens,
    required this.maxWidth,
    required this.child,
    this.maxHeight,
    super.key,
  });

  /// The colours.
  final SelectionMenuTokens tokens;

  /// The widest the card may be.
  final double maxWidth;

  /// The tallest the card may be; unbounded when null.
  final double? maxHeight;

  /// The pages.
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    widthFactor: 1,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight ?? double.infinity,
      ),
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

/// A text button of the main row: its label and 12 dp each side, 42 dp tall.
class SelectionMenuButton extends StatelessWidget {
  /// A button that shows [label] in [style].
  const SelectionMenuButton({
    required this.label,
    required this.style,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  /// The text, which is also the spoken label.
  final String label;

  /// The label style, colour included.
  final TextStyle style;

  /// Called on a tap; the button is disabled while null.
  final VoidCallback? onPressed;

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
          padding: const EdgeInsets.symmetric(
            horizontal: SelectionMenuMetrics.buttonPadding,
          ),
          minimumSize: const Size(0, SelectionMenuMetrics.tileHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: style,
          shape: const RoundedRectangleBorder(),
        ),
        child: Text(label),
      ),
    );
  }
}

/// The More button that ends the main row: the vertical dots, 46 by 42 with
/// 4 dp kept from the card's end.
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
    child: Padding(
      padding: const EdgeInsetsDirectional.only(
        end: SelectionMenuMetrics.moreButtonEndPadding,
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: null,
        icon: const Icon(Icons.more_vert, size: SelectionMenuMetrics.iconSize),
        color: color,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: SelectionMenuMetrics.tileHeight,
          minHeight: SelectionMenuMetrics.tileHeight,
        ),
      ),
    ),
  );
}

/// A row of the More page: 42 dp tall, 18 dp each side, an optional leading
/// icon or marker, the label on one line.
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
    this.leadingGap = SelectionMenuMetrics.leadingGap,
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
            height: SelectionMenuMetrics.tileHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SelectionMenuMetrics.tilePadding,
              ),
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

/// The line between the More page's list and its Back tile.
class SelectionMenuDivider extends StatelessWidget {
  /// A divider in [color].
  const SelectionMenuDivider({required this.color, super.key});

  /// The line's colour.
  final Color color;

  @override
  Widget build(BuildContext context) => Divider(
    height: SelectionMenuMetrics.dividerThickness,
    thickness: SelectionMenuMetrics.dividerThickness,
    color: color,
  );
}
