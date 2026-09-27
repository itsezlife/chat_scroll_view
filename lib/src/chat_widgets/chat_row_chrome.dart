import 'package:chat_scroll_view/src/chat_scroll/chat_row_chrome_delegate.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_opacity_paint.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart'
    show ChatMessageParentData;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One item in a [ChatRowChrome] stack: a [child] widget plus the [delegate]
/// that decides, frame by frame, how visible it is and whether it takes
/// input.
///
/// ```dart
/// ChatRowChromeItem(
///   delegate: const ChatRowChromeDelegate.fadeUnderHeader(),
///   child: DaySeparator(date: date),
/// )
/// ```
@immutable
final class ChatRowChromeItem {
  /// Creates an item. [delegate] defaults to [ChatRowChromeDelegate.opaque],
  /// which always paints the child and lets it take input.
  const ChatRowChromeItem({
    required this.child,
    this.delegate = const ChatRowChromeDelegate.opaque(),
  });

  /// Resolves the child's opacity and hit-testability on every paint and hit
  /// test. Replacing it with a delegate that is not `==` repaints the row
  /// without relayout.
  final ChatRowChromeDelegate delegate;

  /// The chrome widget. It gets the row's full width and picks its own
  /// height, which stays reserved whatever [delegate] resolves.
  final Widget child;
}

/// A message row with a stack of row chrome above the message body.
///
/// Row chrome is decoration that belongs to one message slot but is not part
/// of the message. The usual case is the inline day separator on a row that
/// starts a day. The viewport builds a [ChatRowChrome] for each such row and
/// gives the separator item the delegate from
/// `ChatScrollView.dayHeaderDelegate.inlineSeparator`. The viewport composes
/// the row outside the selection wrapper, so selection chrome never tints the
/// chrome and it never counts as message surface.
///
/// ```dart
/// ChatRowChrome(
///   chrome: [
///     ChatRowChromeItem(
///       delegate: const ChatRowChromeDelegate.hideUnderHeader(),
///       child: DaySeparator(date: date),
///     ),
///   ],
///   body: MessageBubble(message: message),
/// )
/// ```
///
/// ## Layout
///
/// Every child gets the row's full width and picks its own height. Chrome
/// items stack top to bottom in list order, and the body sits directly below
/// the last one. The row is as tall as all chrome plus the body. Chrome keeps
/// its height whatever its delegate resolves, so hiding an item never shifts
/// the rows around it.
///
/// ## Viewport contract
///
/// The row must be the viewport's direct child, not wrapped in another
/// widget. There it writes the summed chrome height into
/// [ChatMessageParentData.messageBodyTop] on every layout. The viewport
/// treats a press above that line as chrome, so long-press selection and the
/// message menu never start on any chrome item.
///
/// ## Paint and input
///
/// On every paint and hit test, each item's [ChatRowChromeItem.delegate]
/// turns [ChatRowChromeMetrics] into a [ChatRowChromeEffect]. Inside the
/// viewport the metrics carry the item's viewport-local paint top and
/// height, the floating header zone, and the scroll activity. Anywhere else,
/// the top is the item's offset within the row, there is no header, and
/// activity is `1`.
///
/// The row paints the body first, then chrome in list order at each item's
/// resolved opacity. It skips an item at opacity `<= 0.001` and paints it
/// without a layer at `>= 0.999`. Hit testing tries the body first, then
/// hit-testable chrome from the bottom item up.
///
/// ## Repaint boundaries
///
/// Each chrome child and the body get their own [RepaintBoundary]. Don't wrap
/// the row itself in another one: opacity can change every scroll frame, and
/// the row applies it by re-compositing the cached child pictures.
class ChatRowChrome extends MultiChildRenderObjectWidget {
  /// Creates a row with [chrome] stacked top to bottom above [body].
  ///
  /// With an empty [chrome] list the row lays out [body] alone, and the body
  /// top is `0`.
  ChatRowChrome({
    required List<ChatRowChromeItem> chrome,
    required Widget body,
    super.key,
  }) : super(
         children: <Widget>[
           for (final item in chrome)
             _ChatRowChromeDelegateData(
               delegate: item.delegate,
               child: RepaintBoundary(child: item.child),
             ),
           RepaintBoundary(child: body),
         ],
       );

  @override
  RenderChatRowChrome createRenderObject(BuildContext context) =>
      RenderChatRowChrome();
}

/// Writes a chrome child's delegate into its parent data, so it travels
/// with the child through reorders and updates.
class _ChatRowChromeDelegateData
    extends ParentDataWidget<_ChatRowChromeParentData> {
  const _ChatRowChromeDelegateData({
    required this.delegate,
    required super.child,
  });

  final ChatRowChromeDelegate delegate;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData! as _ChatRowChromeParentData;
    if (pd.delegate == delegate) return;
    pd.delegate = delegate;
    renderObject.parent?.markNeedsPaint();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => ChatRowChrome;
}

/// Parent data for [RenderChatRowChrome] children.
class _ChatRowChromeParentData extends ContainerBoxParentData<RenderBox> {
  /// Presentation delegate; the body keeps the default and is identified by
  /// position.
  ChatRowChromeDelegate delegate = const ChatRowChromeDelegate.opaque();

  /// Retained [OpacityLayer] while the child paints partially transparent.
  final LayerHandle<OpacityLayer> opacityLayer = LayerHandle<OpacityLayer>();

  @override
  void detach() {
    opacityLayer.layer = null;
    super.detach();
  }
}

/// Render object for [ChatRowChrome].
///
/// Children are the chrome items in stack order, then the body as the last
/// child. The body is always present.
class RenderChatRowChrome extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _ChatRowChromeParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData case _ChatRowChromeParentData()) return;
    child.parentData = _ChatRowChromeParentData();
  }

  RenderBox get _body => lastChild!;

  static _ChatRowChromeParentData _pd(RenderBox child) =>
      child.parentData! as _ChatRowChromeParentData;

  /// Number of chrome items above the body.
  int get chromeCount => childCount - 1;

  ChatRowChromeEffect _resolve(RenderBox child) {
    final local = _pd(child).offset.dy;
    final metrics = switch (parentData) {
      final ChatMessageParentData viewport => ChatRowChromeMetrics(
        top: viewport.paintTop + local,
        extent: child.size.height,
        header: viewport.headerZone,
        activity: viewport.scrollActivity,
      ),
      _ => ChatRowChromeMetrics(top: local, extent: child.size.height),
    };
    return _pd(child).delegate.resolve(metrics);
  }

  /// The effect chrome item [index] (counting from the top) resolves to now,
  /// from the same metrics paint and hit testing use. For tests and
  /// diagnostics.
  ///
  /// Throws a [RangeError] unless `0 <= index < chromeCount`.
  ChatRowChromeEffect debugChromeEffect(int index) {
    RangeError.checkValidIndex(index, this, 'index', chromeCount);
    var child = firstChild!;
    for (var i = 0; i < index; i++) {
      child = childAfter(child)!;
    }
    return _resolve(child);
  }

  @override
  void performLayout() {
    assert(childCount >= 1, 'ChatRowChrome needs a body');
    final cc = BoxConstraints.tightFor(width: constraints.maxWidth);
    final body = _body;
    var y = 0.0;
    for (var child = firstChild!; child != body; child = childAfter(child)!) {
      child.layout(cc, parentUsesSize: true);
      _pd(child).offset = Offset(0, y);
      y += child.size.height;
    }
    body.layout(cc, parentUsesSize: true);
    _pd(body).offset = Offset(0, y);
    size = constraints.constrain(
      Size(constraints.maxWidth, y + body.size.height),
    );
    if (parentData case final ChatMessageParentData viewportPd) {
      viewportPd.messageBodyTop = y;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final cc = BoxConstraints.tightFor(width: constraints.maxWidth);
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      height += child.getDryLayout(cc).height;
    }
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    bool hit(RenderBox child) => result.addWithPaintOffset(
      offset: _pd(child).offset,
      position: position,
      hitTest: (innerResult, transformed) =>
          child.hitTest(innerResult, position: transformed),
    );

    // The body is the interactive part, so it is tested first.
    if (hit(_body)) return true;
    for (
      var child = childBefore(_body);
      child != null;
      child = childBefore(child)
    ) {
      if (!_resolve(child).hitTestable) continue;
      if (hit(child)) return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final body = _body;
    context.paintChild(body, offset + _pd(body).offset);

    for (var child = firstChild!; child != body; child = childAfter(child)!) {
      final pd = _pd(child);
      paintChildWithOpacity(
        context,
        child,
        offset + pd.offset,
        _resolve(child).opacity,
        pd.opacityLayer,
      );
    }
  }

  @override
  void dispose() {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      _pd(child).opacityLayer.layer = null;
    }
    super.dispose();
  }
}
