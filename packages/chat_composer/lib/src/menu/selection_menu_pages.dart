import 'dart:math' as math;

import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
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
/// [items] must already fit the row; see `splitSelectionMenuRow`.
class SelectionMenuRootPage extends StatelessWidget {
  /// A row of [items], with a More button while [onOpenMore] is given.
  const SelectionMenuRootPage({
    required this.items,
    required this.tokens,
    required this.labelStyle,
    required this.moreLabel,
    required this.onSelected,
    required this.onOpenMore,
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

  /// The key of the More button.
  static const Key moreKey = ValueKey<String>('selection_menu_more');

  @override
  Widget build(BuildContext context) => SizedBox(
    height: SelectionMenuMetrics.tileHeight,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          SelectionMenuButton(
            key: ValueKey<SelectionMenuItemKind>(item.kind),
            label: item.label,
            style: item.labelStyle.apply(labelStyle),
            selected: item.selected,
            onPressed: item.enabled ? () => onSelected(item) : null,
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

/// The More page: the clipboard items that did not fit the row, then the
/// formatting items, with a Back tile at one end.
///
/// The list is a column of 42 dp tiles; when it would be taller than the room
/// it becomes a scrolling list in a box of exactly that height. A plain
/// scroll view would take the whole budget and leave a gap under a short page.
class SelectionMenuMorePage extends StatelessWidget {
  /// A page of [items].
  const SelectionMenuMorePage({
    required this.items,
    required this.tokens,
    required this.labelStyle,
    required this.backLabel,
    required this.backPlacement,
    required this.onSelected,
    required this.onBack,
    this.maxHeight,
    super.key,
  });

  /// The overflowed clipboard items, then the formatting items.
  final List<SelectionMenuItem> items;

  /// The colours.
  final SelectionMenuTokens tokens;

  /// The style every label is set in; a formatting row layers its own effect
  /// on it.
  final TextStyle labelStyle;

  /// The Back tile's label.
  final String backLabel;

  /// Which end of the page holds the Back tile.
  final SelectionMenuBackPlacement backPlacement;

  /// Runs an item.
  final ValueChanged<SelectionMenuItem> onSelected;

  /// Returns to the main row.
  final VoidCallback onBack;

  /// The tallest the page may be; unbounded when null.
  final double? maxHeight;

  /// The key of the Back tile.
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
    final max = maxHeight;
    final listBudget = max == null
        ? null
        : math.max<double>(0, max - SelectionMenuMetrics.pageHeaderBudget);
    final back = SelectionMenuTile(
      key: backKey,
      label: backLabel,
      style: labelStyle,
      iconColor: tokens.text,
      leading: const Icon(Icons.arrow_back),
      onTap: onBack,
    );
    final list = _list(tiles, listBudget);
    final divider = SelectionMenuDivider(color: tokens.divider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (backPlacement) {
        SelectionMenuBackPlacement.top => [back, divider, list],
        SelectionMenuBackPlacement.bottom => [list, divider, back],
      },
    );
  }

  static Widget _list(List<Widget> tiles, double? budget) {
    final content = tiles.length * SelectionMenuMetrics.tileHeight;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: tiles,
    );
    if (budget == null) return column;
    if (content <= budget) return SizedBox(height: content, child: column);
    return SizedBox(
      height: budget,
      child: ListView(
        primary: false,
        padding: EdgeInsets.zero,
        children: tiles,
      ),
    );
  }
}
