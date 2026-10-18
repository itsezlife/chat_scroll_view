import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart'
    show InlineEmbed, InlineEmbedPaintContext;
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_geometry.dart';
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

/// Lays out and paints the items of an emoji-only body by its
/// [ChatEmojiLayoutSpec].
///
/// It wraps at the spec's limit of the incoming maximum width and shrinks to
/// the widest line, then adds the strip the host reserved. The text scale
/// plays no part: sizes come from the spec.
@internal
final class RenderChatEmojiBody extends RenderBox {
  /// Creates the render object.
  RenderChatEmojiBody({
    required List<ChatEmojiLeaf> leaves,
    required ChatEmojiLayoutSpec spec,
    Color? tint,
  }) : _leaves = leaves,
       _spec = spec,
       _tint = tint;

  List<ChatEmojiLeaf> _leaves;
  ChatEmojiLayoutSpec _spec;
  Color? _tint;
  ChatEmojiGeometry? _geometry;

  /// The items, in order. Another list repaints and lays out again.
  List<ChatEmojiLeaf> get leaves => _leaves;
  set leaves(List<ChatEmojiLeaf> value) {
    if (identical(_leaves, value)) return;
    if (attached) _unlisten();
    _leaves = value;
    if (attached) _listen();
    markNeedsPaint();
  }

  /// What lays the items out.
  ChatEmojiLayoutSpec get spec => _spec;
  set spec(ChatEmojiLayoutSpec value) {
    if (_spec == value) return;
    _spec = value;
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
  int? itemAt(Offset local) {
    final items = _geometry?.items;
    if (items == null) return null;
    for (var i = 0; i < items.length; i++) {
      if (items[i].contains(local)) return i;
    }
    return null;
  }

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

  ChatEmojiGeometry _geometryFor(double maxWidth) =>
      ChatEmojiGeometry.of(_spec, maxWidth: maxWidth);

  @override
  void performLayout() {
    final geometry = _geometry = _geometryFor(constraints.maxWidth);
    size = constraints.constrain(geometry.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_geometryFor(constraints.maxWidth).size);

  @override
  double computeMinIntrinsicWidth(double height) => _spec.box + 2 * _spec.inset;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _geometryFor(double.infinity).size.width;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _geometryFor(width).size.height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _geometryFor(width).size.height;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final geometry = _geometry;
    if (geometry == null) return;
    final canvas = context.canvas;
    final count = math.min(_leaves.length, geometry.items.length);
    for (var i = 0; i < count; i++) {
      _leaves[i].paint(canvas, geometry.items[i].shift(offset), _tint);
    }
  }
}
