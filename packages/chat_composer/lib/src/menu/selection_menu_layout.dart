import 'dart:math' as math;
import 'dart:ui';

import 'package:chat_composer/src/menu/selection_menu_metrics.dart';

/// Where the selection menu's pieces go and how big they are: the reference
/// floating toolbar's layout arithmetic as pure functions, so the numbers are
/// testable without a widget.
///
/// Sizes are logical pixels.
abstract final class SelectionMenuLayout {
  /// Width of a main-row item whose label is [textWidth] wide: the label and
  /// its padding, at least 48, with 24 at the outer end of the first and the
  /// last item.
  static double mainItemWidth(
    double textWidth, {
    required bool first,
    required bool last,
  }) {
    final start = first
        ? SelectionMenuMetrics.outerItemPadding
        : SelectionMenuMetrics.itemPadding;
    final end = last
        ? SelectionMenuMetrics.outerItemPadding
        : SelectionMenuMetrics.itemPadding;
    return math.max(SelectionMenuMetrics.itemMinWidth, start + textWidth + end);
  }

  /// How many of the items, in order, stay on the main row, and how wide that
  /// row is.
  ///
  /// An item stays while it fits next to the More button; the last item of the
  /// whole list may take the button's room when everything else already fits.
  /// The first one that does not fit ends the row, and it and every item after
  /// it go to the overflow page. [budget] is the toolbar's width.
  static ({int count, double width}) mainRow({
    required List<double> textWidths,
    required double budget,
  }) {
    var available = budget;
    var count = 0;
    for (var i = 0; i < textWidths.length; i++) {
      final last = i == textWidths.length - 1;
      final width = math.min(
        mainItemWidth(textWidths[i], first: i == 0, last: last),
        budget,
      );
      final fitsBesideMore =
          width <= available - SelectionMenuMetrics.moreWidth;
      final fitsAlone = last && width <= available;
      if (!fitsBesideMore && !fitsAlone) break;
      available -= width;
      count++;
    }
    final overflows = count < textWidths.length;
    return (
      count: count,
      width:
          budget -
          available +
          (overflows ? SelectionMenuMetrics.moreWidth : 0.0),
    );
  }

  /// The toolbar's width budget on a [viewportWidth] wide screen:
  /// `min(400, width - 2 * 16)`.
  static double budget(double viewportWidth) => math.min(
    SelectionMenuMetrics.maxWidth,
    viewportWidth - 2 * SelectionMenuMetrics.screenMargin,
  );

  /// Width of the overflow page for items whose labels are [textWidths] wide:
  /// the widest item (label and 18 dp each side, at least 48), and at least
  /// the More button's 56. Capped at [budget], where the
  /// labels ellipsize.
  static double overflowWidth(List<double> textWidths, {double? budget}) {
    var width = SelectionMenuMetrics.moreWidth;
    for (final text in textWidths) {
      width = math.max(
        width,
        math.max(
          SelectionMenuMetrics.itemMinWidth,
          text + 2 * SelectionMenuMetrics.overflowPadding,
        ),
      );
    }
    return budget == null ? width : math.min(width, budget);
  }

  /// Height of the overflow page for [count] items when [rows] item rows fit
  /// above the back row: `rows` clamped to 2..4 and to [count], times 48, plus
  /// the back row, plus half a row of peek when it scrolls.
  static double overflowHeight(int count, {int rows = 4}) {
    final shown = math.min(
      SelectionMenuMetrics.maxOverflowRows,
      math.min(math.max(SelectionMenuMetrics.minOverflowRows, rows), count),
    );
    final peek = shown < count ? SelectionMenuMetrics.overflowPeek : 0.0;
    return shown * SelectionMenuMetrics.rowHeight +
        SelectionMenuMetrics.moreHeight +
        peek;
  }

  /// How many item rows fit in [suggestedHeight] of overflow page.
  static int rowsIn(double suggestedHeight) =>
      ((suggestedHeight - SelectionMenuMetrics.moreHeight) /
              SelectionMenuMetrics.rowHeight)
          .floor();

  /// Where the card goes for a selection occupying [content] on a screen
  /// whose usable area is [viewport].
  ///
  /// [main] is the main row's size; [overflowWidth] and [overflowCount] size
  /// the overflow page, none when [overflowCount] is zero. The card is
  /// right-anchored in a window as wide as the wider page, which is centred on
  /// the selection and kept [SelectionMenuMetrics.screenMargin] from the
  /// viewport's end; [rtl] anchors it to the left instead.
  static SelectionMenuPlacement place({
    required Rect viewport,
    required Rect content,
    required Size main,
    required double overflowWidth,
    required int overflowCount,
    bool rtl = false,
  }) {
    const margin = SelectionMenuMetrics.verticalMargin;
    const both = 2 * margin;
    const row = SelectionMenuMetrics.rowHeight;
    const rowWithMargin = row + both;
    final hasOverflow = overflowCount > 0;

    final above = content.top - viewport.top;
    final below = viewport.bottom - content.bottom;

    var rows = SelectionMenuMetrics.maxOverflowRows;
    var upwards = false;
    double windowTop;
    // The window's height depends on the overflow height, which depends on the
    // case; the cases that set `rows` need it for their own `y`.
    double windowHeight() =>
        math.max(
          row,
          hasOverflow ? overflowHeight(overflowCount, rows: rows) : row,
        ) +
        both;

    if (!hasOverflow) {
      if (above >= rowWithMargin) {
        windowTop = content.top - rowWithMargin;
      } else if (below >= rowWithMargin) {
        windowTop = content.bottom;
      } else if (below >= row) {
        windowTop = content.bottom - margin;
      } else {
        windowTop = math.max(viewport.top, content.top - rowWithMargin);
      }
    } else {
      final minimum = overflowHeight(overflowCount, rows: 2) + both;
      final throughDown = viewport.bottom - content.top + rowWithMargin;
      final throughUp = content.bottom - viewport.top + rowWithMargin;
      if (above >= minimum) {
        rows = rowsIn(above - both);
        windowTop = content.top - windowHeight();
        upwards = true;
      } else if (above >= rowWithMargin && throughDown >= minimum) {
        rows = rowsIn(throughDown - both);
        windowTop = content.top - rowWithMargin;
      } else if (below >= minimum) {
        rows = rowsIn(below - both);
        windowTop = content.bottom;
      } else if (below >= rowWithMargin && viewport.height >= minimum) {
        rows = rowsIn(throughUp - both);
        windowTop = content.bottom + rowWithMargin - windowHeight();
        upwards = true;
      } else {
        rows = rowsIn(viewport.height - both);
        windowTop = viewport.top;
      }
    }

    final openHeight = hasOverflow
        ? overflowHeight(overflowCount, rows: rows)
        : row;
    final windowWidth =
        math.max(main.width, hasOverflow ? overflowWidth : 0) +
        2 * SelectionMenuMetrics.screenMargin;
    final windowLeft = math.max<double>(
      0,
      math.min(
        content.center.dx - windowWidth / 2,
        viewport.right - windowWidth,
      ),
    );
    final cardTop = windowTop + margin;
    final cardBottom = cardTop + math.max(row, openHeight);
    final anchorX = rtl
        ? windowLeft + SelectionMenuMetrics.screenMargin
        : windowLeft + windowWidth - SelectionMenuMetrics.screenMargin;
    return SelectionMenuPlacement._(
      anchorX: anchorX,
      anchorY: upwards ? cardBottom : cardTop,
      overflowUpwards: upwards,
      rtl: rtl,
      main: main,
      overflow: hasOverflow ? Size(overflowWidth, openHeight) : null,
    );
  }
}

/// Where the card sits: the corner it keeps while it changes size, and the
/// sizes it changes between.
final class SelectionMenuPlacement {
  const SelectionMenuPlacement._({
    required this.anchorX,
    required this.anchorY,
    required this.overflowUpwards,
    required this.rtl,
    required this.main,
    required this.overflow,
  });

  /// The card's end edge (left in a right-to-left locale), which holds still
  /// while the card morphs: its right edge in left-to-right text.
  final double anchorX;

  /// The card's bottom edge when the overflow page opens upwards, else its top
  /// edge: the edge that holds still while the card morphs.
  final double anchorY;

  /// Whether the overflow page grows upwards from the main row.
  final bool overflowUpwards;

  /// Whether the card is anchored at its left edge.
  final bool rtl;

  /// The main row's size.
  final Size main;

  /// The overflow page's size, or null when there is none.
  final Size? overflow;

  /// The card's rectangle when it is [size] big.
  Rect cardRect(Size size) {
    final left = rtl ? anchorX : anchorX - size.width;
    final top = overflowUpwards ? anchorY - size.height : anchorY;
    return Rect.fromLTWH(left, top, size.width, size.height);
  }
}

/// The pieces of the card while it morphs between the main row and the
/// overflow page, in the card's own coordinates.
///
/// The card keeps its end edge (and its bottom edge when it grows upwards)
/// while its size changes; the main row, the overflow list and the back row
/// each keep to that edge too, which is what makes the page appear to unfold
/// from the row instead of sliding in.
final class SelectionMenuMorph {
  /// The morph between [main] and [overflow] for a card that grows
  /// [upwards], mirrored when [rtl].
  const SelectionMenuMorph({
    required this.main,
    required this.overflow,
    required this.upwards,
    required this.rtl,
  });

  /// The main row's size.
  final Size main;

  /// The overflow page's size.
  final Size overflow;

  /// Whether the page grows upwards from the row.
  final bool upwards;

  /// Whether the layout is mirrored.
  final bool rtl;

  /// The diagonal the card's size changes along, which sets the morph's
  /// duration.
  double get diagonal => math.sqrt(
    math.pow(main.width - overflow.width, 2) +
        math.pow(overflow.height - main.height, 2),
  );

  /// The pieces at one instant.
  ///
  /// [opening] is the direction. [width] and [height] are how far each
  /// dimension has got from its start size to its end size (already curved),
  /// and [ease] is the back row's own progress along its eased curve.
  SelectionMenuFrame frame({
    required bool opening,
    required double width,
    required double height,
    required double ease,
  }) {
    final from = opening ? main : overflow;
    final to = opening ? overflow : main;
    final w = lerpDouble(from.width, to.width, width)!;
    final h = lerpDouble(from.height, to.height, height)!;

    final mainX = w - main.width;
    final mainY = upwards ? h - main.height : 0.0;
    final listX = w - overflow.width;
    final listY = upwards
        ? h - overflow.height
        : SelectionMenuMetrics.moreHeight;
    final buttonX = opening
        ? (main.width - SelectionMenuMetrics.moreWidth) +
              ease * (SelectionMenuMetrics.moreWidth - overflow.width) +
              (w - main.width)
        : ease * (overflow.width - SelectionMenuMetrics.moreWidth) +
              (w - overflow.width);
    final buttonY = upwards ? h - SelectionMenuMetrics.moreHeight : 0.0;
    final buttonWidth = overflow.width;

    Rect piece(double x, double y, double width, double height) =>
        Rect.fromLTWH(rtl ? w - x - width : x, y, width, height);

    return SelectionMenuFrame._(
      size: Size(w, h),
      main: piece(mainX, mainY, main.width, main.height),
      list: piece(
        listX,
        listY,
        overflow.width,
        overflow.height - SelectionMenuMetrics.moreHeight,
      ),
      backRow: piece(
        buttonX,
        buttonY,
        buttonWidth,
        SelectionMenuMetrics.moreHeight,
      ),
      backOpacity: opening ? ease : 1 - ease,
    );
  }
}

/// One instant of the morph; see [SelectionMenuMorph.frame].
final class SelectionMenuFrame {
  const SelectionMenuFrame._({
    required this.size,
    required this.main,
    required this.list,
    required this.backRow,
    required this.backOpacity,
  });

  /// The card's size.
  final Size size;

  /// The main row.
  final Rect main;

  /// The overflow list, which sits under the back row (above it when the page
  /// opens upwards).
  final Rect list;

  /// The back row, which is the More button while the page is closed.
  final Rect backRow;

  /// How visible the back row's label and hairline are: 0 as the More button,
  /// 1 as the back row.
  final double backOpacity;
}
