import 'package:chat_scroll_view/src/chat_widgets/chat_message_body.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_message_body_layout.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Render object for [ChatMessageBody].
///
/// Lays out slotted children, paints [ChatMessageBodySlot.content] then
/// [ChatMessageBodySlot.meta], and hit-tests meta first (painted on top).
class RenderChatMessageBody extends RenderBox
    with SlottedContainerRenderObjectMixin<ChatMessageBodySlot, RenderBox> {
  /// Creates a content + meta layout render object.
  RenderChatMessageBody({
    required double spacing,
    required EdgeInsetsGeometry padding,
    required TextDirection textDirection,
  }) : _spacing = spacing,
       _padding = padding,
       _textDirection = textDirection;

  double _spacing;
  EdgeInsetsGeometry _padding;
  TextDirection _textDirection;

  /// See [ChatMessageBody.spacing].
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  /// See [ChatMessageBody.padding].
  EdgeInsetsGeometry get padding => _padding;
  set padding(EdgeInsetsGeometry value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  /// Resolves [padding]; taken from ambient [Directionality].
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  EdgeInsets get _resolvedPadding => _padding.resolve(_textDirection);

  RenderBox? get _content => childForSlot(ChatMessageBodySlot.content);
  RenderBox? get _meta => childForSlot(ChatMessageBodySlot.meta);

  /// Hit-test order: meta first (on top), then content.
  @override
  Iterable<RenderBox> get children => <RenderBox>[?_meta, ?_content];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final child = _content ?? _meta;
    if (child == null) return null;
    final distance = child.getDistanceToActualBaseline(baseline);
    if (distance == null) return null;
    return distance + _offsetOf(child).dy;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _measure(constraints, dry: true).size;

  @override
  void performLayout() {
    final result = _measure(constraints, dry: false);
    size = result.size;
    final content = _content;
    if (content != null) {
      _positionChild(content, result.contentOffset);
    }
    final meta = _meta;
    if (meta != null) {
      _positionChild(meta, result.metaOffset);
    }
  }

  ChatMessageBodyLayout _measure(
    BoxConstraints constraints, {
    required bool dry,
  }) {
    final padding = _resolvedPadding;
    final availableWidth = (constraints.maxWidth - padding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final childConstraints = BoxConstraints(maxWidth: availableWidth);

    final content = _content;
    final meta = _meta;
    final contentSize = content == null
        ? Size.zero
        : _layoutChild(content, childConstraints, dry: dry);
    final metaSize = meta == null
        ? Size.zero
        : _layoutChild(meta, childConstraints, dry: dry);

    return layoutChatMessageBody(
      constraints: constraints,
      padding: padding,
      spacing: _spacing,
      contentSize: contentSize,
      metaSize: metaSize,
      hasContent: content != null,
      hasMeta: meta != null,
      lastLineWidth: () => dry
          ? contentSize.width
          : lastLineWidthOf(content!, fallback: contentSize.width),
    );
  }

  Size _layoutChild(
    RenderBox child,
    BoxConstraints constraints, {
    required bool dry,
  }) {
    if (dry) return child.getDryLayout(constraints);
    child.layout(constraints, parentUsesSize: true);
    return child.size;
  }

  static Offset _offsetOf(RenderBox child) =>
      (child.parentData! as BoxParentData).offset;

  static void _positionChild(RenderBox child, Offset offset) {
    (child.parentData! as BoxParentData).offset = offset;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final content = _content;
    if (content != null) {
      context.paintChild(content, offset + _offsetOf(content));
    }
    final meta = _meta;
    if (meta != null) {
      context.paintChild(meta, offset + _offsetOf(meta));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final childParentData = child.parentData! as BoxParentData;
      final isHit = result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (isHit) return true;
    }
    return false;
  }
}
