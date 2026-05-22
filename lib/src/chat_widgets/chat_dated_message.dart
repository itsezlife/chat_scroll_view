import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart'
    show ChatMessageParentData;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Parent data for [RenderDatedMessage]'s two children.
class _DatedMessageParentData extends ContainerBoxParentData<RenderBox> {}

/// The first message of a day: an inline date [separator] stacked above the
/// message [body].
///
/// `RenderChatScrollView` writes a `dividerOpacity` into this render object's
/// [ChatMessageParentData] as it positions children; the separator is painted
/// at that opacity. It fades out as the message scrolls up toward the floating
/// day header — so the inline divider and the floating header never both show.
/// The separator always keeps its laid-out height, so the reserved space does
/// not collapse as it fades.
///
/// Intentionally *not* wrapped in an outer [RepaintBoundary] by its builder: it
/// must re-paint each scroll frame to apply the changing opacity. Both children
/// are wrapped in their own [RepaintBoundary] here, so their pictures stay
/// cached — a scroll frame only re-composites two layers.
class DatedMessage extends MultiChildRenderObjectWidget {
  DatedMessage({
    required Widget separator,
    required Widget body,
    super.key,
  }) : super(
         children: <Widget>[
           RepaintBoundary(child: separator),
           RepaintBoundary(child: body),
         ],
       );

  @override
  RenderDatedMessage createRenderObject(BuildContext context) =>
      RenderDatedMessage();
}

/// Render object for [DatedMessage] — stacks the separator above the body and
/// paints the separator at the `dividerOpacity` from its [ChatMessageParentData].
class RenderDatedMessage extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _DatedMessageParentData> {
  final LayerHandle<OpacityLayer> _separatorLayer = LayerHandle<OpacityLayer>();

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DatedMessageParentData) {
      child.parentData = _DatedMessageParentData();
    }
  }

  RenderBox get _separator => firstChild!;
  RenderBox get _body => lastChild!;

  /// Inline-divider opacity, written by `RenderChatScrollView` into our parent
  /// data; `1` when this object is not (yet) a viewport child.
  double get _dividerOpacity {
    final pd = parentData;
    return pd is ChatMessageParentData ? pd.dividerOpacity : 1.0;
  }

  static Offset _offsetOf(RenderBox child) =>
      (child.parentData! as _DatedMessageParentData).offset;

  @override
  void performLayout() {
    assert(childCount == 2, 'DatedMessage needs exactly a separator and a body');
    final cc = BoxConstraints.tightFor(width: constraints.maxWidth);
    final separator = _separator..layout(cc, parentUsesSize: true);
    final body = _body..layout(cc, parentUsesSize: true);
    (separator.parentData! as _DatedMessageParentData).offset = Offset.zero;
    (body.parentData! as _DatedMessageParentData).offset = Offset(
      0,
      separator.size.height,
    );
    size = constraints.constrain(
      Size(constraints.maxWidth, separator.size.height + body.size.height),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final cc = BoxConstraints.tightFor(width: constraints.maxWidth);
    final separator = _separator.getDryLayout(cc);
    final body = _body.getDryLayout(cc);
    return constraints.constrain(
      Size(constraints.maxWidth, separator.height + body.height),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // The body is the interactive part — test it first.
    final body = _body;
    final hitBody = result.addWithPaintOffset(
      offset: _offsetOf(body),
      position: position,
      hitTest: (innerResult, transformed) =>
          body.hitTest(innerResult, position: transformed),
    );
    if (hitBody) return true;
    // A faded-out separator takes no input.
    if (_dividerOpacity <= 0.0) return false;
    final separator = _separator;
    return result.addWithPaintOffset(
      offset: _offsetOf(separator),
      position: position,
      hitTest: (innerResult, transformed) =>
          separator.hitTest(innerResult, position: transformed),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final body = _body;
    context.paintChild(body, offset + _offsetOf(body));

    final opacity = _dividerOpacity;
    if (opacity <= 0.0) {
      _separatorLayer.layer = null;
      return;
    }
    final separator = _separator;
    final separatorOffset = offset + _offsetOf(separator);
    if (opacity >= 1.0) {
      _separatorLayer.layer = null;
      context.paintChild(separator, separatorOffset);
    } else {
      _separatorLayer.layer = context.pushOpacity(
        separatorOffset,
        (opacity * 255).round().clamp(0, 255),
        (innerContext, innerOffset) =>
            innerContext.paintChild(separator, innerOffset),
        oldLayer: _separatorLayer.layer,
      );
    }
  }

  @override
  void dispose() {
    _separatorLayer.layer = null;
    super.dispose();
  }
}
