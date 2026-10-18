import 'dart:ui' show Rect, Size, TextDirection;

import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_flow.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_policy.dart';
import 'package:flutter/foundation.dart';

/// What lays out an emoji-only body, as one value: the policy's numbers
/// resolved for one message. The body paints from it and
/// [ChatEmojiGeometry.of] reads it, so the two cannot disagree.
@internal
@immutable
final class ChatEmojiLayoutSpec {
  /// Creates the spec.
  const ChatEmojiLayoutSpec({
    required this.kind,
    required this.lineBreaksBefore,
    required this.box,
    required this.skip,
    required this.inset,
    required this.wrap,
    required this.reserve,
    required this.direction,
  });

  /// The layout.
  final ChatEmojiLayoutKind kind;

  /// The line breaks before each item.
  final List<int> lineBreaksBefore;

  /// The side of an item's square: the sticker's extent for the sticker.
  final double box;

  /// The gap between two items of a line.
  final double skip;

  /// The margin around the items.
  final double inset;

  /// What narrows the wrap, applied to the row's width.
  final ChatEmojiWrapLimit wrap;

  /// The height of the strip the host reserves under the items.
  final double reserve;

  /// The direction lines start from.
  final TextDirection direction;

  @override
  bool operator ==(Object other) =>
      other is ChatEmojiLayoutSpec &&
      other.kind == kind &&
      listEquals(other.lineBreaksBefore, lineBreaksBefore) &&
      other.box == box &&
      other.skip == skip &&
      other.inset == inset &&
      other.wrap == wrap &&
      other.reserve == reserve &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(
    kind,
    Object.hashAll(lineBreaksBefore),
    box,
    skip,
    inset,
    wrap,
    reserve,
    direction,
  );
}

/// Where the parts of an emoji-only body are, in the body's own coordinates
/// (origin at its top left, x to the right): what a host reads to set the time,
/// reactions and headers around it.
///
/// The text layout's rectangles are of the items: [content] is the widest line
/// by every line, [lastLine] the items of the last line (the one a time sits
/// under), [trailingEdge] the end of the text in the layout's own direction.
/// The sticker layout's [content] is the sticker's art, inside the platform's
/// inset. [reserved] is the strip the host asked the body to keep free under
/// the items, so the body's [size] holds the host's chrome without the body
/// being resized around it.
@immutable
final class ChatEmojiGeometry {
  const ChatEmojiGeometry._({
    required this.kind,
    required this.size,
    required this.content,
    required this.lastLine,
    required this.reserved,
    required this.trailingEdge,
    required this.direction,
    required this.items,
  });

  /// Lays out [spec] in a row [maxWidth] wide.
  @internal
  factory ChatEmojiGeometry.of(
    ChatEmojiLayoutSpec spec, {
    required double maxWidth,
  }) {
    final flow = ChatEmojiFlow.of(
      lineBreaksBefore: spec.lineBreaksBefore,
      box: spec.box,
      maxWidth: spec.wrap.of(maxWidth),
      direction: spec.direction,
      inset: spec.inset,
      skip: spec.skip,
    );
    final width = flow.size.width;
    return ChatEmojiGeometry._(
      kind: spec.kind,
      size: Size(width, flow.size.height + spec.reserve),
      content: flow.content,
      lastLine: flow.lastLine,
      reserved: Rect.fromLTWH(0, flow.size.height, width, spec.reserve),
      trailingEdge: switch (spec.direction) {
        TextDirection.ltr => flow.content.right,
        TextDirection.rtl => flow.content.left,
      },
      direction: spec.direction,
      items: flow.rects,
    );
  }

  /// Which layout this is.
  final ChatEmojiLayoutKind kind;

  /// The body's box: the items, their inset and the [reserved] strip.
  final Size size;

  /// The area of the items: the widest line by every line, or the sticker's
  /// art.
  final Rect content;

  /// The items of the last line.
  final Rect lastLine;

  /// The strip under the items the host reserved; zero high without a request.
  final Rect reserved;

  /// The x of the text's end: the right edge of [content] in a left-to-right
  /// layout, its left edge in a right-to-left one.
  final double trailingEdge;

  /// The direction the items flow in.
  final TextDirection direction;

  /// The square of each item, in the order of the message.
  final List<Rect> items;

  @override
  bool operator ==(Object other) =>
      other is ChatEmojiGeometry &&
      other.kind == kind &&
      other.size == size &&
      other.content == content &&
      other.lastLine == lastLine &&
      other.reserved == reserved &&
      other.trailingEdge == trailingEdge &&
      other.direction == direction &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(
    kind,
    size,
    content,
    lastLine,
    reserved,
    trailingEdge,
    direction,
    Object.hashAll(items),
  );

  @override
  String toString() =>
      'ChatEmojiGeometry($kind, size: $size, content: $content, '
      'reserved: $reserved)';
}
