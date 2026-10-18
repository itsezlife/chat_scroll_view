import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:flutter/widgets.dart';

/// How many of the clipboard buttons the main row holds.
@immutable
final class SelectionMenuRowSplit {
  /// A split of [count] buttons taking [width].
  const SelectionMenuRowSplit({required this.count, required this.width});

  /// How many buttons, from the first, fit the row. The rest go to the top of
  /// the More page.
  final int count;

  /// The width of those buttons, without the More button.
  final double width;
}

/// Splits [labels] so the row never runs past [maxWidth].
///
/// Each label is measured in the style the row draws it in. Buttons are kept
/// while they fit next to the More button; the first that does not fit and
/// everything after it go to the page, so the order still reads naturally
/// there. The More button's width is kept free even when the menu ends up
/// with none, which only ever leaves the row a little short.
SelectionMenuRowSplit splitSelectionMenuRow({
  required List<String> labels,
  required TextStyle style,
  required double maxWidth,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final budget = maxWidth - SelectionMenuMetrics.moreButtonWidth;
  var used = 0.0;
  var count = 0;
  for (final label in labels) {
    final width = selectionMenuButtonWidth(
      label: label,
      style: style,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    if (used + width > budget) break;
    used += width;
    count++;
  }
  return SelectionMenuRowSplit(count: count, width: used);
}

/// The width a main-row button takes for [label]: the text and its padding.
double selectionMenuButtonWidth({
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
  final width = painter.width;
  painter.dispose();
  return width + SelectionMenuMetrics.buttonPadding * 2;
}
