import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chat_composer/src/menu/selection_menu_overflow.dart';
import 'package:chat_composer/src/menu/selection_menu_shell.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// Where the Back tile sits on the More page.
enum SelectionMenuBackPlacement {
  /// Above the list, for a card that opens below the selection.
  top,

  /// Under the list, for a card that opens above the selection, so Back stays
  /// next to the text the menu points at.
  bottom,
}

/// The main row: the clipboard buttons that fit, then the More button.
///
/// [items] must already fit the row; see `splitSelectionMenuRow`. The first
/// button keeps 24 dp at its start, and so does the last at its end while no
/// More button follows it, as the reference lays them out.
class SelectionMenuRootPage extends StatelessWidget {
  /// A row of [items], with a More button while [onOpenMore] is given.
  const SelectionMenuRootPage({
    required this.items,
    required this.tokens,
    required this.labelStyle,
    required this.moreLabel,
    required this.onSelected,
    required this.onOpenMore,
    this.maxWidth = double.infinity,
    super.key,
  });

  /// The clipboard items that fit.
  final List<SelectionMenuItem> items;

  /// The colours.
  final SelectionMenuTokens tokens;

  /// The style every label is set in. It must be the style the split was
  /// measured with.
  final TextStyle labelStyle;

  /// The More button's spoken label.
  final String moreLabel;

  /// Runs an item.
  final ValueChanged<SelectionMenuItem> onSelected;

  /// Opens the More page; null leaves the More button out.
  final VoidCallback? onOpenMore;

  /// The widest a button may be: the row's own limit. A button the split kept
  /// is within it; this only cuts a label that is wider than the row alone.
  final double maxWidth;

  /// The key of the More button.
  static const Key moreKey = ValueKey<String>('selection_menu_more');

  @override
  Widget build(BuildContext context) {
    final hasMore = onOpenMore != null;
    return SizedBox(
      height: SelectionMenuMetrics.rowHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, item) in items.indexed)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SelectionMenuButton(
                key: ValueKey<SelectionMenuItemKind>(item.kind),
                label: item.label,
                style: item.labelStyle.apply(labelStyle),
                selected: item.selected,
                startPadding: selectionMenuButtonStartPadding(
                  isFirst: index == 0,
                ),
                endPadding: selectionMenuButtonEndPadding(
                  isLast: index == items.length - 1 && !hasMore,
                ),
                onPressed: item.enabled ? () => onSelected(item) : null,
              ),
            ),
          if (onOpenMore case final open?)
            SelectionMenuMoreButton(
              key: moreKey,
              label: moreLabel,
              color: tokens.text,
              onPressed: open,
            ),
        ],
      ),
    );
  }
}

/// The More page: the clipboard items that did not fit the row, then the
/// formatting items, with a Back row at one end.
///
/// It is [size] wide and tall, by `sizeSelectionMenuPage`: a list of 42 dp
/// rows in a box of the rows it shows (counted at 48 dp, with 4 dp above the
/// first), and the Back row. A plain scroll view would take the whole budget
/// and leave a gap under a short page, which is why the list's box is exact.
class SelectionMenuMorePage extends StatelessWidget {
  /// A page of [items].
  const SelectionMenuMorePage({
    required this.items,
    required this.tokens,
    required this.labelStyle,
    required this.backStyle,
    required this.backLabel,
    required this.backPlacement,
    required this.onSelected,
    required this.onBack,
    required this.size,
    super.key,
  });

  /// The overflowed clipboard items, then the formatting items.
  final List<SelectionMenuItem> items;

  /// The colours.
  final SelectionMenuTokens tokens;

  /// The style every label is set in; a formatting row layers its own effect
  /// on it.
  final TextStyle labelStyle;

  /// The style of the Back row's label.
  final TextStyle backStyle;

  /// The Back row's label.
  final String backLabel;

  /// Which end of the page holds the Back row.
  final SelectionMenuBackPlacement backPlacement;

  /// Runs an item.
  final ValueChanged<SelectionMenuItem> onSelected;

  /// Returns to the main row.
  final VoidCallback onBack;

  /// How big the page is.
  final SelectionMenuPageSize size;

  /// The key of the Back row.
  static const Key backKey = ValueKey<String>('selection_menu_back');

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final item in items)
        SelectionMenuTile(
          key: ValueKey<SelectionMenuItemKind>(item.kind),
          label: item.label,
          style: item.labelStyle.apply(labelStyle),
          selected: item.selected,
          iconColor: tokens.text,
          onTap: item.enabled ? () => onSelected(item) : null,
          leading: switch (item.kind.listMarker) {
            final marker? => SizedBox(
              width: SelectionMenuMetrics.listMarkerWidth,
              // A marker wider than its column (a number at a large text
              // scale) spills into the gap rather than wrapping.
              child: Text(
                marker,
                style: labelStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
            null => null,
          },
          leadingGap: SelectionMenuMetrics.listMarkerGap,
        ),
    ];
    // The hairline is the top edge of the Back row, so it separates the two
    // only where Back is under the list; above the list it is the card's edge.
    final back = Stack(
      children: [
        SelectionMenuTile(
          key: backKey,
          label: backLabel,
          style: backStyle,
          iconColor: tokens.text,
          height: SelectionMenuMetrics.backHeight,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: SelectionMenuMetrics.buttonPadding,
          ),
          leadingGap:
              SelectionMenuMetrics.backLabelInset -
              SelectionMenuMetrics.backIconInset -
              SelectionMenuMetrics.iconSize,
          leading: const Icon(Icons.arrow_back),
          onTap: onBack,
        ),
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          child: SelectionMenuDivider(color: tokens.divider),
        ),
      ],
    );
    final list = SizedBox(
      height: size.listHeight,
      child: SelectionMenuListFade(
        child: ListView(
          primary: false,
          padding: const EdgeInsets.only(
            top: SelectionMenuMetrics.listPaddingTop,
            bottom: SelectionMenuMetrics.listPaddingBottom,
          ),
          children: tiles,
        ),
      ),
    );
    return SizedBox(
      width: size.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (backPlacement) {
          SelectionMenuBackPlacement.top => [back, list],
          SelectionMenuBackPlacement.bottom => [list, back],
        },
      ),
    );
  }
}
