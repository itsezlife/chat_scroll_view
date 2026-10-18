import 'dart:math' as math;

import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:flutter/widgets.dart';

/// How many of the clipboard buttons the main row holds.
@immutable
final class SelectionMenuRowSplit {
  /// A split of [count] buttons taking [width], with a More button after them
  /// when [hasMore].
  const SelectionMenuRowSplit({
    required this.count,
    required this.width,
    required this.hasMore,
  });

  /// How many buttons, from the first, fit the row. The rest go to the top of
  /// the More page.
  final int count;

  /// The width of those buttons, without the More button.
  final double width;

  /// Whether the row ends with a More button: something is left for the page,
  /// a clipboard button that did not fit or a formatting item.
  final bool hasMore;

  /// The width of the whole row: the buttons and the More button.
  double get rowWidth =>
      width + (hasMore ? SelectionMenuMetrics.moreButtonWidth : 0);
}

/// Splits [labels] so the row never runs past [maxWidth], by the rule of the
/// reference's `layoutMainPanelItems` (`FloatingToolbar` 1004-1049).
///
/// Each label is measured in the style the row draws it in. A button stays
/// while it fits beside the More button; the one that is last of the whole menu
/// (the last label, with nothing after it on the page: [moreFollows] false) may
/// take that room instead, since it then has no More button to leave room for.
/// The first button that does not fit and everything after it go to the page, so
/// the order still reads naturally there. A button's width is cut to the row's
/// before it is compared, so a label wider than the row still gets the row when
/// it is alone.
///
/// [moreFollows] is whether the page holds more than the clipboard buttons that
/// overflow, the formatting items.
SelectionMenuRowSplit splitSelectionMenuRow({
  required List<String> labels,
  required TextStyle style,
  required double maxWidth,
  bool moreFollows = false,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  var available = maxWidth;
  var used = 0.0;
  var count = 0;
  for (var i = 0; i < labels.length; i++) {
    final isLast = i == labels.length - 1 && !moreFollows;
    final width = math.min(
      selectionMenuButtonWidth(
        label: labels[i],
        style: style,
        textScaler: textScaler,
        textDirection: textDirection,
        isFirst: i == 0,
        isLast: isLast,
      ),
      maxWidth,
    );
    final fitsBesideMore =
        width <= available - SelectionMenuMetrics.moreButtonWidth;
    final fitsAlone = isLast && width <= available;
    if (!fitsBesideMore && !fitsAlone) break;
    available -= width;
    used += width;
    count++;
  }
  return SelectionMenuRowSplit(
    count: count,
    width: used,
    hasMore: count < labels.length || moreFollows,
  );
}

/// The width a main-row button takes for [label]: the text between its
/// paddings, at least the button's minimum.
///
/// The row's first button keeps 1.5 times the padding at its start and its last
/// at its end ([isFirst], [isLast]); only a button with no More button after
/// it is last.
double selectionMenuButtonWidth({
  required String label,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
  bool isFirst = false,
  bool isLast = false,
}) => math.max(
  SelectionMenuMetrics.buttonMinWidth,
  selectionMenuButtonStartPadding(isFirst: isFirst) +
      selectionMenuTextWidth(
        label: label,
        style: style,
        textScaler: textScaler,
        textDirection: textDirection,
      ) +
      selectionMenuButtonEndPadding(isLast: isLast),
);

/// The padding a main-row button keeps at its start.
double selectionMenuButtonStartPadding({required bool isFirst}) =>
    SelectionMenuMetrics.buttonPadding *
    (isFirst ? SelectionMenuMetrics.outerPaddingFactor : 1);

/// The padding a main-row button keeps at its end.
double selectionMenuButtonEndPadding({required bool isLast}) =>
    SelectionMenuMetrics.buttonPadding *
    (isLast ? SelectionMenuMetrics.outerPaddingFactor : 1);

/// The width of [label] on one line, up to the next whole logical pixel, so a
/// box of exactly that width never breaks or ellipsizes the label for want of
/// a fraction (the reference measures in whole pixels).
double selectionMenuTextWidth({
  required String label,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

/// How big the More page is: as wide as its widest row, as tall as the rows it
/// shows and its Back row.
@immutable
final class SelectionMenuPageSize {
  /// A page [width] wide whose list is [listHeight] tall.
  const SelectionMenuPageSize({
    required this.width,
    required this.listHeight,
    required this.scrolls,
  });

  /// The page's width.
  final double width;

  /// The height of the list's visible area: the rows it shows, each counted at
  /// the reference's 48 dp, and the peek of the next one while it scrolls.
  final double listHeight;

  /// Whether the list has more rows than it shows.
  final bool scrolls;

  /// The page's height: the list and the Back row.
  double get height => listHeight + SelectionMenuMetrics.backHeight;
}

/// Sizes the More page for [items] by the rule of the reference's overflow
/// panel (`FloatingToolbar` 1088-1150).
///
/// The width is that of the widest row, its text between 18 dp each side,
/// measured on one line in the row's own style: nothing is ellipsized or
/// wrapped, the page widens. The height is a number of rows, from
/// [SelectionMenuMetrics.pageMinRows] to [SelectionMenuMetrics.pageMaxRows]
/// and no more than there are, that the room [maxHeight] leaves after the Back
/// row; a list longer than that shows half a row more, and scrolls.
///
/// The reference does not limit the width and clips a label it cannot show;
/// here [maxWidth], the room across, does, and a row wider than it ellipsizes
/// as the only case in which a label is shortened. It also does not count the
/// Back row's label, and a page of short rows would cut "Back"; here the page
/// is at least as wide as that row.
///
/// A null [maxHeight] is no limit.
SelectionMenuPageSize sizeSelectionMenuPage({
  required List<SelectionMenuItem> items,
  required TextStyle style,
  required String backLabel,
  required TextStyle backStyle,
  required double maxWidth,
  required TextScaler textScaler,
  required TextDirection textDirection,
  double? maxHeight,
}) {
  var width =
      SelectionMenuMetrics.backLabelInset +
      selectionMenuTextWidth(
        label: backLabel,
        style: backStyle,
        textScaler: textScaler,
        textDirection: textDirection,
      ) +
      SelectionMenuMetrics.buttonPadding;
  for (final item in items) {
    final marker = item.kind.listMarker == null
        ? 0.0
        : SelectionMenuMetrics.listMarkerWidth +
              SelectionMenuMetrics.listMarkerGap;
    width = math.max(
      width,
      SelectionMenuMetrics.tilePadding * 2 +
          marker +
          selectionMenuTextWidth(
            label: item.label,
            style: item.labelStyle.apply(style),
            textScaler: textScaler,
            textDirection: textDirection,
          ),
    );
  }
  final fits = maxHeight == null
      ? SelectionMenuMetrics.pageMaxRows
      : ((maxHeight - SelectionMenuMetrics.backHeight) /
                SelectionMenuMetrics.pageLineHeight)
            .floor();
  final rows = math.min(
    SelectionMenuMetrics.pageMaxRows,
    math.min(math.max(SelectionMenuMetrics.pageMinRows, fits), items.length),
  );
  final scrolls = rows < items.length;
  return SelectionMenuPageSize(
    width: math.min(width, maxWidth),
    listHeight:
        rows * SelectionMenuMetrics.pageLineHeight +
        (scrolls ? SelectionMenuMetrics.pagePeek : 0),
    scrolls: scrolls,
  );
}
