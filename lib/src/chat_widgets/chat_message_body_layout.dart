import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Measured offsets and size for one content + meta layout pass.
///
/// Produced by [layoutChatMessageBody] and applied by the slotted render
/// object to size itself and position children.
class ChatMessageBodyLayout {
  /// Creates a measured layout result.
  const ChatMessageBodyLayout({
    required this.size,
    required this.contentOffset,
    required this.metaOffset,
  });

  /// Outer size after applying incoming [BoxConstraints].
  final Size size;

  /// Paint offset for the content child, relative to the parent origin.
  final Offset contentOffset;

  /// Paint offset for the meta child, relative to the parent origin.
  final Offset metaOffset;
}

/// Measures last-line packing for a content + meta pair.
///
/// [lastLineWidth] should return the trailing X of the last text line in the
/// content child's coordinate space (see [lastLineWidthOf]), or the content
/// width when line metrics are unavailable (dry layout / non-text body).
///
/// Returns either an **inline** result (meta on the last line, height =
/// content height) or a **wrap** result (meta on the next row).
ChatMessageBodyLayout layoutChatMessageBody({
  required BoxConstraints constraints,
  required EdgeInsets padding,
  required double spacing,
  required Size contentSize,
  required Size metaSize,
  required double Function() lastLineWidth,
  required bool hasContent,
  required bool hasMeta,
}) {
  final availableWidth = math.max<double>(
    0,
    constraints.maxWidth - padding.horizontal,
  );

  if (!hasContent || contentSize == Size.zero) {
    return ChatMessageBodyLayout(
      size: constraints.constrain(
        Size(
          padding.horizontal + metaSize.width,
          padding.vertical + metaSize.height,
        ),
      ),
      contentOffset: Offset(padding.left, padding.top),
      metaOffset: Offset(padding.left, padding.top),
    );
  }

  if (!hasMeta || metaSize == Size.zero) {
    return ChatMessageBodyLayout(
      size: constraints.constrain(
        Size(
          padding.horizontal + contentSize.width,
          padding.vertical + contentSize.height,
        ),
      ),
      contentOffset: Offset(padding.left, padding.top),
      metaOffset: Offset.zero,
    );
  }

  final lineWidth = lastLineWidth();
  final fitsInline = lineWidth + spacing + metaSize.width <= availableWidth;

  if (fitsInline) {
    final innerWidth = math.max(
      contentSize.width,
      lineWidth + spacing + metaSize.width,
    );
    final size = constraints.constrain(
      Size(
        padding.horizontal + innerWidth,
        padding.vertical + contentSize.height,
      ),
    );
    return ChatMessageBodyLayout(
      size: size,
      contentOffset: Offset(padding.left, padding.top),
      metaOffset: Offset(
        size.width - padding.right - metaSize.width,
        padding.top + contentSize.height - metaSize.height,
      ),
    );
  }

  final size = constraints.constrain(
    Size(
      padding.horizontal + math.max(contentSize.width, metaSize.width),
      padding.vertical + contentSize.height + metaSize.height,
    ),
  );
  return ChatMessageBodyLayout(
    size: size,
    contentOffset: Offset(padding.left, padding.top),
    metaOffset: Offset(
      size.width - padding.right - metaSize.width,
      padding.top + contentSize.height,
    ),
  );
}

/// Depth-first last [RenderParagraph] under [root], or null if none.
///
/// Lets a [Text] nested under padding / alignment still drive last-line
/// packing for the in-bubble content + meta layout.
RenderParagraph? findLastParagraph(RenderObject root) {
  RenderParagraph? last;
  void visit(RenderObject node) {
    if (node is RenderParagraph) {
      last = node;
    }
    node.visitChildren(visit);
  }

  visit(root);
  return last;
}

/// Trailing X of the last text line in [content]'s coordinate space.
///
/// Reads glyph boxes from the last [RenderParagraph] under [content] and maps
/// the line's right edge through [RenderObject.getTransformTo] so nested
/// padding still packs against visible glyphs.
///
/// Returns [fallback] when there is no paragraph or no boxes (non-text body,
/// empty text, or before a wet layout). Prefer [content.size.width] as
/// [fallback] for a conservative wrap bias.
double lastLineWidthOf(RenderBox content, {required double fallback}) {
  final paragraph = findLastParagraph(content);
  if (paragraph == null) return fallback;

  final plainLength = paragraph.text.toPlainText().length;
  if (plainLength == 0) return 0;

  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plainLength),
  );
  if (boxes.isEmpty) return 0;

  var maxBottom = boxes.first.bottom;
  for (final box in boxes) {
    if (box.bottom > maxBottom) maxBottom = box.bottom;
  }

  double? maxRight;
  for (final box in boxes) {
    if ((box.bottom - maxBottom).abs() > 0.5) continue;
    maxRight = maxRight == null ? box.right : math.max(maxRight, box.right);
  }
  if (maxRight == null) return fallback;

  final transform = paragraph.getTransformTo(content);
  final endInContent = MatrixUtils.transformPoint(
    transform,
    Offset(maxRight, 0),
  );
  return endInContent.dx;
}
