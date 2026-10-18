import 'dart:math' as math;

import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:flutter/rendering.dart';

/// Paints the markers of a text's list items (bullets, derived numbers) in the
/// gutter beside the field's text, as the editable's gutter painter.
///
/// The marker is not text: the field's text holds the item's words and nothing
/// else, so the caret, selection and copy never meet a marker. The gutter is
/// a column before the text (after it in right-to-left text), as wide as the
/// widest marker, and the field gives it that room only while it holds a
/// marker ([extent]); a text without a list keeps the layout of a text field
/// with none.
///
/// Every marker shares the one column and hugs the text, so a wide number
/// does not push a bullet away from its line. How deep an item is shows in the
/// shape of its bullet rather than in an indent, because the field lays out
/// one paragraph and an indent per depth would move the plain lines with it.
final class ComposerListGutterPainter extends RenderEditablePainter {
  /// A painter for the markers of [text], in [style].
  ComposerListGutterPainter({
    required this.text,
    required TextStyle style,
    TextScaler textScaler = TextScaler.noScaling,
  }) : _style = style,
       _textScaler = textScaler {
    text.addListener(_onText);
  }

  /// The text whose items get markers.
  final ComposerTextController text;

  /// Space between a marker and the text.
  static const double markerGap = 6;

  TextStyle _style;
  TextScaler _textScaler;
  final Map<String, TextPainter> _painters = {};

  /// The marker typography: the field's text style.
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _discardPainters();
    notifyListeners();
  }

  /// The scaling of the markers, that of the field's text.
  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _discardPainters();
    notifyListeners();
  }

  /// The room the gutter needs now: the widest marker and its gap, zero while
  /// the text has no item.
  double get extent {
    var widest = 0.0;
    for (final marker in text.listMarkers) {
      widest = math.max(widest, _painterFor(marker.label).width);
    }
    return widest == 0 ? 0 : widest + markerGap;
  }

  @override
  void paint(Canvas canvas, Size size, RenderEditable renderEditable) {
    final markers = text.listMarkers;
    if (markers.isEmpty) return;
    final ltr = renderEditable.textDirection == TextDirection.ltr;
    final length = renderEditable.plainText.length;
    for (final marker in markers) {
      if (marker.offset > length) continue;
      final painter = _painterFor(marker.label);
      final caret = renderEditable.getLocalRectForCaret(
        TextPosition(offset: marker.offset),
      );
      // A line scrolled out of the field has no marker to show.
      if (caret.bottom < 0 || caret.top > size.height) continue;
      final dx = ltr ? -painter.width - markerGap : size.width + markerGap;
      final dy = caret.top + (caret.height - painter.height) / 2;
      painter.paint(canvas, Offset(dx, dy));
    }
  }

  TextPainter _painterFor(String label) => _painters[label] ??= TextPainter(
    text: TextSpan(text: label, style: _style),
    textDirection: TextDirection.ltr,
    textScaler: _textScaler,
  )..layout();

  void _onText() => notifyListeners();

  void _discardPainters() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }

  @override
  bool shouldRepaint(RenderEditablePainter? oldDelegate) =>
      oldDelegate is! ComposerListGutterPainter ||
      !identical(oldDelegate.text, text) ||
      oldDelegate._style != _style ||
      oldDelegate._textScaler != _textScaler;

  @override
  void dispose() {
    text.removeListener(_onText);
    _discardPainters();
    super.dispose();
  }
}
