import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'chat_message_render.dart';

/// Optional mixin for [ChatMessageRender] that adds text selection support.
///
/// Subclass provides two getters: [selectableParagraph] and [paragraphOrigin].
/// The mixin provides hit testing, word boundary detection, and paint helpers.
///
/// Usage:
/// ```dart
/// class MyRender extends ChatMessageRender with SelectableChatMessageRender {
///   @override
///   ui.Paragraph? get selectableParagraph => _paragraph;
///   @override
///   Offset get paragraphOrigin => Offset(_padX, _padY);
///
///   @override
///   void paintMessage(Canvas canvas, Size size) {
///     canvas.drawRRect(bubble, bgPaint);
///     paintSelectionHighlight(canvas, size);
///     canvas.drawParagraph(_paragraph!, paragraphOrigin);
///   }
/// }
/// ```
mixin SelectableChatMessageRender on ChatMessageRender {
  // --- Subclass provides ---

  /// The [ui.Paragraph] used for text layout and hit testing.
  ui.Paragraph? get selectableParagraph;

  /// Offset where the paragraph is drawn within this render
  /// (the translation applied before [Canvas.drawParagraph]).
  Offset get paragraphOrigin;

  // --- Selection state (managed by viewport) ---

  bool _isSelected = false;
  TextSelection? _textSelection;

  /// Whether this message is currently selected (text or bubble).
  bool get isSelected => _isSelected;

  /// The text selection range, or `null` for bubble selection.
  TextSelection? get textSelection => _textSelection;

  /// Called by the viewport when this message's selection changes.
  /// [textSelection] is non-null for text mode, null for bubble mode.
  void applySelection(TextSelection? textSelection) {
    if (_isSelected && _textSelection == textSelection) return;
    _isSelected = true;
    _textSelection = textSelection;
    invalidatePaint();
  }

  /// Called by the viewport when this message is deselected.
  void clearSelection() {
    if (!_isSelected) return;
    _isSelected = false;
    _textSelection = null;
    invalidatePaint();
  }

  // --- Query methods (viewport calls during gesture handling) ---

  /// Convert a local offset (relative to this render's origin) to a
  /// [TextPosition] in the paragraph.
  TextPosition getTextPosition(Offset localOffset) {
    return selectableParagraph!.getPositionForOffset(
      localOffset - paragraphOrigin,
    );
  }

  /// Get the word boundary at the given text position.
  TextRange getWordBoundary(TextPosition position) {
    return selectableParagraph!.getWordBoundary(position);
  }

  // --- Paint helper (subclass calls in paintMessage) ---

  /// Paint selection highlight. Call in [paintMessage] before drawing text.
  ///
  /// Automatically determines the mode:
  /// - Text mode: draws highlight boxes from [ui.Paragraph.getBoxesForRange]
  /// - Bubble mode: draws a semi-transparent overlay on the entire size
  void paintSelectionHighlight(
    Canvas canvas,
    Size size, {
    Color textColor = const Color(0x40448AFF),
    Color bubbleColor = const Color(0x20448AFF),
  }) {
    if (!_isSelected) return;
    if (_textSelection case final sel? when !sel.isCollapsed) {
      final paragraph = selectableParagraph;
      if (paragraph == null) return;
      final boxes = paragraph.getBoxesForRange(
        sel.start,
        sel.end,
        boxHeightStyle: ui.BoxHeightStyle.max,
        boxWidthStyle: ui.BoxWidthStyle.max,
      );
      final paint = Paint()..color = textColor;
      for (final box in boxes) {
        canvas.drawRect(box.toRect().shift(paragraphOrigin), paint);
      }
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = bubbleColor);
    }
  }
}
