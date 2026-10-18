import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart'
    show InlineEmbed, InlineEmbedPaintContext;
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_flow.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// What one item of an emoji-only body paints into its square.
@internal
sealed class ChatEmojiLeaf {
  const ChatEmojiLeaf();

  /// Calls [listener] when what [paint] draws changed. A still never does.
  void addListener(VoidCallback listener) {}

  /// Stops calling [listener].
  void removeListener(VoidCallback listener) {}

  /// Draws into [rect].
  void paint(Canvas canvas, Rect rect, Color? tint);

  /// Gives back what the leaf holds.
  void dispose() {}
}

/// A unicode emoji drawn as text at the step's font size.
@internal
final class ChatEmojiGlyphLeaf extends ChatEmojiLeaf {
  /// Wraps [painter], which is laid out and which this leaf owns.
  ChatEmojiGlyphLeaf(this.painter);

  /// The laid-out glyph.
  final TextPainter painter;

  @override
  void paint(Canvas canvas, Rect rect, Color? tint) => painter.paint(
    canvas,
    rect.center - Offset(painter.width / 2, painter.height / 2),
  );

  @override
  void dispose() => painter.dispose();
}

/// A custom emoji, or a sticker, drawn by an embed from the asset cache.
@internal
final class ChatEmojiEmbedLeaf extends ChatEmojiLeaf {
  /// Wraps [embed], which this leaf owns.
  ChatEmojiEmbedLeaf(this.embed);

  /// The embed that draws the item.
  final InlineEmbed embed;

  @override
  void addListener(VoidCallback listener) => embed.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => embed.removeListener(listener);

  @override
  void paint(Canvas canvas, Rect rect, Color? tint) =>
      embed.paint(canvas, rect, InlineEmbedPaintContext(tint: tint));

  @override
  void dispose() => embed.dispose();
}

/// An item nothing could draw (no resolver knows its document): it keeps its
/// square and shows nothing, as a leaf that failed keeps its placeholder.
@internal
final class ChatEmojiEmptyLeaf extends ChatEmojiLeaf {
  /// Creates the empty leaf.
  const ChatEmojiEmptyLeaf();

  @override
  void paint(Canvas canvas, Rect rect, Color? tint) {}
}

/// Lays out and paints the items of an emoji-only body in squares of one
/// side, by [ChatEmojiFlow].
///
/// It wraps at [wrapFraction] of the incoming maximum width and shrinks to
/// the widest line. The text scale plays no part: sizes come from the box.
@internal
final class RenderChatEmojiBody extends RenderBox {
  /// Creates the render object.
  RenderChatEmojiBody({
    required List<ChatEmojiLeaf> leaves,
    required List<int> lineBreaksBefore,
    required double box,
    required double inset,
    required double wrapFraction,
    required TextDirection textDirection,
    Color? tint,
  }) : _leaves = leaves,
       _lineBreaksBefore = lineBreaksBefore,
       _box = box,
       _inset = inset,
       _wrapFraction = wrapFraction,
       _textDirection = textDirection,
       _tint = tint;

  List<ChatEmojiLeaf> _leaves;
  List<int> _lineBreaksBefore;
  double _box;
  double _inset;
  double _wrapFraction;
  TextDirection _textDirection;
  Color? _tint;
  ChatEmojiFlow? _flow;

  /// The items, in order. Another list repaints and lays out again.
  List<ChatEmojiLeaf> get leaves => _leaves;
  set leaves(List<ChatEmojiLeaf> value) {
    if (identical(_leaves, value)) return;
    if (attached) _unlisten();
    _leaves = value;
    if (attached) _listen();
    markNeedsPaint();
  }

  /// The line breaks before each item.
  List<int> get lineBreaksBefore => _lineBreaksBefore;
  set lineBreaksBefore(List<int> value) {
    if (identical(_lineBreaksBefore, value)) return;
    _lineBreaksBefore = value;
    markNeedsLayout();
  }

  /// The side of an item's square.
  double get box => _box;
  set box(double value) {
    if (_box == value) return;
    _box = value;
    markNeedsLayout();
  }

  /// The margin around the items.
  double get inset => _inset;
  set inset(double value) {
    if (_inset == value) return;
    _inset = value;
    markNeedsLayout();
  }

  /// The share of the maximum width the items wrap at.
  double get wrapFraction => _wrapFraction;
  set wrapFraction(double value) {
    if (_wrapFraction == value) return;
    _wrapFraction = value;
    markNeedsLayout();
  }

  /// The reading direction lines start from.
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// The colour of the text around the body, for a template asset.
  Color? get tint => _tint;
  set tint(Color? value) {
    if (_tint == value) return;
    _tint = value;
    markNeedsPaint();
  }

  /// The index of the item at [local], or null.
  int? itemAt(Offset local) => _flow?.itemAt(local);

  ChatEmojiFlow _flowFor(double maxWidth) => ChatEmojiFlow.of(
    lineBreaksBefore: _lineBreaksBefore,
    box: _box,
    maxWidth: maxWidth.isFinite ? maxWidth * _wrapFraction : maxWidth,
    direction: _textDirection,
    inset: _inset,
  );

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  void _listen() {
    for (final leaf in _leaves) {
      leaf.addListener(markNeedsPaint);
    }
  }

  void _unlisten() {
    for (final leaf in _leaves) {
      leaf.removeListener(markNeedsPaint);
    }
  }

  @override
  void performLayout() {
    final flow = _flow = _flowFor(constraints.maxWidth);
    size = constraints.constrain(flow.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_flowFor(constraints.maxWidth).size);

  @override
  double computeMinIntrinsicWidth(double height) => _box + 2 * _inset;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _flowFor(double.infinity).size.width;

  @override
  double computeMinIntrinsicHeight(double width) => _flowFor(width).size.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _flowFor(width).size.height;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final flow = _flow;
    if (flow == null) return;
    final canvas = context.canvas;
    final count = math.min(_leaves.length, flow.rects.length);
    for (var i = 0; i < count; i++) {
      _leaves[i].paint(canvas, flow.rects[i].shift(offset), _tint);
    }
  }
}
