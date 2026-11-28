import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// A file name drawn in [maxLines] lines, cut in the middle when it is
/// longer; with [tooltipWhenElided] a cut name shows the whole name in a
/// chrome tooltip (where an overlay is there to show it in).
///
/// A file name's start and its extension both say what the file is, so a
/// name is shortened in the middle, never at its end.
class MiddleElidedText extends StatelessWidget {
  /// Draws [text] in [style] under [textScaler].
  const MiddleElidedText(
    this.text, {
    required this.style,
    this.textScaler = TextScaler.noScaling,
    this.maxLines = 1,
    this.textAlign = TextAlign.left,
    this.tooltipWhenElided = false,
    super.key,
  });

  /// The full text.
  final String text;

  /// Its style.
  final TextStyle style;

  /// The text scaler it is cut and drawn under: the one the layout
  /// measured with.
  final TextScaler textScaler;

  /// The lines it may take.
  final int maxLines;

  /// Its alignment in its box.
  final TextAlign textAlign;

  /// Whether a cut text shows the full text in a tooltip.
  final bool tooltipWhenElided;

  /// [text] cut in the middle (`"report-fi…nal.pdf"`) so it fits [maxLines]
  /// lines [maxWidth] wide in [style], and whether it was cut.
  ///
  /// The cut is by grapheme, so no emoji or combined letter is split.
  static (String, bool) elide(
    String text, {
    required TextStyle style,
    required double maxWidth,
    required int maxLines,
    required TextDirection textDirection,
    TextScaler textScaler = TextScaler.noScaling,
    String ellipsis = '…',
  }) {
    final painter = TextPainter(
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
    );
    bool fits(String candidate) {
      painter
        ..text = TextSpan(text: candidate, style: style)
        ..layout(maxWidth: maxWidth);
      return !painter.didExceedMaxLines && painter.width <= maxWidth;
    }

    try {
      if (fits(text)) return (text, false);
      final characters = text.characters.toList();
      String keep(int count) {
        final head = (count + 1) ~/ 2;
        final tail = count - head;
        return characters.take(head).join() +
            ellipsis +
            characters.skip(characters.length - tail).join();
      }

      var low = 0;
      var high = characters.length - 1;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (fits(keep(mid))) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      return (keep(low), true);
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final (shown, elided) = elide(
        text,
        style: style,
        maxWidth: constraints.maxWidth,
        maxLines: maxLines,
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      );
      final label = Text(
        shown,
        style: style,
        maxLines: maxLines,
        softWrap: maxLines > 1,
        overflow: TextOverflow.clip,
        textAlign: textAlign,
        textScaler: textScaler,
      );
      if (!elided || !tooltipWhenElided || Overlay.maybeOf(context) == null) {
        return label;
      }
      // The overlay child is built in this subtree, so it sees the chrome
      // scopes; the chrome tooltip carries its own text root there.
      return RawTooltip(
        semanticsTooltip: text,
        tooltipBuilder: (context, animation) => FadeTransition(
          opacity: animation,
          child: ChromeTooltip(text: text),
        ),
        child: label,
      );
    },
  );
}
