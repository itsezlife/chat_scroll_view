import 'package:chat_scroll_view/src/chat_scroll/chat_row_chrome_delegate.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_row_chrome_transition.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_opacity_paint.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart'
    show ChatMessageParentData;
import 'package:flutter/foundation.dart';
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
  }) : followsTransition = false;

  /// An item that follows the row's viewport-driven transition frame
  /// ([RenderChatRowChrome.transition]). The viewport builds the unread
  /// separator this way.
  @internal
  const ChatRowChromeItem.transitioning({
    required this.child,
    this.delegate = const ChatRowChromeDelegate.opaque(),
  }) : followsTransition = true;

  /// Resolves the child's opacity and hit-testability on every paint and hit
  /// test. Replacing it with a delegate that is not `==` repaints the row
  /// without relayout.
  final ChatRowChromeDelegate delegate;

  /// The chrome widget. It gets the row's full width and picks its own
  /// height, which stays reserved whatever [delegate] resolves.
  final Widget child;

  /// Whether the row's transition frame drives this item's slot, opacity,
  /// and scale.
  @internal
  final bool followsTransition;
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
/// Inside the viewport, the unread separator item also follows the
/// viewport's enter / exit transition ([RenderChatRowChrome.transition]).
/// Its slot shrinks to a fraction of its height, keeping the item's bottom
/// part and clipping the rest. The transition also scales its opacity and
/// its paint size, and the item takes no input until the transition ends.
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
  }) : assert(
         chrome.where((item) => item.followsTransition).length <= 1,
         'A row has one transition frame, so at most one item follows it',
       ),
       super(
         children: <Widget>[
           for (final item in chrome)
             _ChatRowChromeDelegateData(
               delegate: item.delegate,
               followsTransition: item.followsTransition,
               child: RepaintBoundary(child: item.child),
             ),
           RepaintBoundary(child: body),
         ],
       );

  @override
  RenderChatRowChrome createRenderObject(BuildContext context) =>
      RenderChatRowChrome();
}

/// Writes a chrome child's delegate and transition flag into its parent
/// data, so they travel with the child through reorders and updates.
class _ChatRowChromeDelegateData
    extends ParentDataWidget<_ChatRowChromeParentData> {
  const _ChatRowChromeDelegateData({
    required this.delegate,
    required this.followsTransition,
    required super.child,
  });

  final ChatRowChromeDelegate delegate;
  final bool followsTransition;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData! as _ChatRowChromeParentData;
    if (pd.followsTransition != followsTransition) {
      pd.followsTransition = followsTransition;
      renderObject.parent?.markNeedsLayout();
    }
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

  /// Whether [RenderChatRowChrome.transition] drives this child.
  bool followsTransition = false;

  /// Top of the child's slot in the row. Equals `offset.dy` unless a
  /// transition shrinks the slot, which then keeps the child's bottom part.
  double slotTop = 0;

  /// Height of the child's slot: its laid-out height times the transition
  /// extent.
  double slotExtent = 0;

  /// Retained [OpacityLayer] while the child paints partially transparent.
  final LayerHandle<OpacityLayer> opacityLayer = LayerHandle<OpacityLayer>();

  /// Retained clip while a transition shrinks the slot below the child.
  final LayerHandle<ClipRectLayer> clipLayer = LayerHandle<ClipRectLayer>();

  /// Retained transform while a transition scales the child.
  final LayerHandle<TransformLayer> transformLayer =
      LayerHandle<TransformLayer>();

  void _dropLayers() {
    opacityLayer.layer = null;
    clipLayer.layer = null;
    transformLayer.layer = null;
  }

  @override
  void detach() {
    _dropLayers();
    super.detach();
  }
}

/// Render object for [ChatRowChrome].
///
/// Children are the chrome items in stack order, then the body as the last
/// child. The body is always present.
///
/// ## Children and effects
///
/// Each chrome child's parent data carries its delegate and whether it
/// follows [transition]. The effect of an item is its delegate's
/// [ChatRowChromeEffect], with the opacity multiplied by the transition
/// frame and input switched off while the frame is set.
/// [debugChromeEffect] reports that combined effect.
///
/// ## Transition
///
/// [transition] is set by the viewport before each layout and drives only
/// the item built with [ChatRowChromeItem.transitioning]. `null` means at
/// rest.
///
/// ## Layout
///
/// Chrome slots stack top to bottom, then the body. A slot is the item's
/// height times the frame's extent, and the item is placed so its bottom
/// edge meets the slot's bottom. The summed slot heights become
/// [ChatMessageParentData.messageBodyTop] inside the viewport.
///
/// ## Hit testing and paint
///
/// The body is hit-tested and painted first. A transitioning item paints
/// clipped to its slot while the slot is shorter than the item, and scaled
/// about its center while the scale is below `1`. [applyPaintTransform]
/// applies the same scale, so global geometry matches what is painted.
class RenderChatRowChrome extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _ChatRowChromeParentData> {
  // --- Children and effects --------------------------------------------------

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

  /// The delegate's effect, scaled by [transition] for the item that follows
  /// it. An item mid-transition takes no input.
  ChatRowChromeEffect _effect(RenderBox child) {
    final effect = _resolve(child);
    return switch (_frameOf(child)) {
      null => effect,
      final frame => ChatRowChromeEffect(
        opacity: effect.opacity * frame.opacity,
        hitTestable: false,
      ),
    };
  }

  /// The effect chrome item [index] (counting from the top) resolves to now,
  /// from the same metrics paint and hit testing use, [transition] included.
  /// For tests and diagnostics.
  ///
  /// Throws a [RangeError] unless `0 <= index < chromeCount`.
  ChatRowChromeEffect debugChromeEffect(int index) {
    RangeError.checkValidIndex(index, this, 'index', chromeCount);
    var child = firstChild!;
    for (var i = 0; i < index; i++) {
      child = childAfter(child)!;
    }
    return _effect(child);
  }

  // --- Transition ------------------------------------------------------------

  ChatRowChromeTransitionFrame? _transition;

  /// The frame the chrome item built with [ChatRowChromeItem.transitioning]
  /// follows, or `null` when it rests: full slot, delegate opacity, no
  /// scale.
  ///
  /// The viewport sets it before every layout of the row, from its row
  /// chrome transition clock. A changed extent relayouts the row; a changed
  /// opacity or scale only repaints it. Rows without a transitioning item
  /// ignore it.
  @internal
  ChatRowChromeTransitionFrame? get transition => _transition;

  @internal
  set transition(ChatRowChromeTransitionFrame? value) {
    final old = _transition;
    if (old == value) return;
    _transition = value;
    if ((old?.extent ?? 1) != (value?.extent ?? 1)) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  /// Whether a chrome item follows [transition].
  @internal
  bool get hasTransitioningItem {
    for (
      var child = firstChild;
      child != null && child != lastChild;
      child = childAfter(child)
    ) {
      if (_pd(child).followsTransition) return true;
    }
    return false;
  }

  ChatRowChromeTransitionFrame? _frameOf(RenderBox child) =>
      _pd(child).followsTransition ? _transition : null;

  /// Scale by [scale] about [child]'s center, in row coordinates.
  Matrix4 _scaleAbout(RenderBox child, double scale) {
    final center = _pd(child).offset + child.size.center(Offset.zero);
    return Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  // --- Layout ----------------------------------------------------------------

  @override
  void performLayout() {
    assert(childCount >= 1, 'ChatRowChrome needs a body');
    final cc = BoxConstraints.tightFor(width: constraints.maxWidth);
    final body = _body;
    var y = 0.0;
    for (var child = firstChild!; child != body; child = childAfter(child)!) {
      child.layout(cc, parentUsesSize: true);
      final height = child.size.height;
      final slot = height * (_frameOf(child)?.extent ?? 1);
      _pd(child)
        ..slotTop = y
        ..slotExtent = slot
        ..offset = Offset(0, y + slot - height);
      y += slot;
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
      height += child.getDryLayout(cc).height * (_frameOf(child)?.extent ?? 1);
    }
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  // --- Hit testing and paint -------------------------------------------------

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
      if (!_effect(child).hitTestable) continue;
      if (hit(child)) return true;
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final scale = _frameOf(child)?.scale ?? 1;
    if (scale != 1) transform.multiply(_scaleAbout(child, scale));
    final offset = _pd(child).offset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final body = _body;
    context.paintChild(body, offset + _pd(body).offset);

    for (var child = firstChild!; child != body; child = childAfter(child)!) {
      _paintChrome(context, offset, child);
    }
  }

  /// Paints chrome [child] at its resolved opacity. Under a [transition] it
  /// also scales about its center and clips to its slot while the slot is
  /// shorter than the child; each wrapper keeps its layer only while needed.
  void _paintChrome(PaintingContext context, Offset offset, RenderBox child) {
    final pd = _pd(child);
    final opacity = _effect(child).opacity;
    final frame = _frameOf(child);
    void faded(PaintingContext context, Offset offset) => paintChildWithOpacity(
      context,
      child,
      offset + pd.offset,
      opacity,
      pd.opacityLayer,
    );

    if (frame == null || opacity <= kChatOpacityPaintSkip) {
      pd
        ..clipLayer.layer = null
        ..transformLayer.layer = null;
      faded(context, offset);
      return;
    }

    void scaled(PaintingContext context, Offset offset) {
      if (frame.scale == 1) {
        pd.transformLayer.layer = null;
        faded(context, offset);
        return;
      }
      pd.transformLayer.layer = context.pushTransform(
        needsCompositing,
        offset,
        _scaleAbout(child, frame.scale),
        faded,
        oldLayer: pd.transformLayer.layer,
      );
    }

    if (pd.slotExtent >= child.size.height) {
      pd.clipLayer.layer = null;
      scaled(context, offset);
      return;
    }
    pd.clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTWH(0, pd.slotTop, size.width, pd.slotExtent),
      scaled,
      oldLayer: pd.clipLayer.layer,
    );
  }

  @override
  void dispose() {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      _pd(child)._dropLayers();
    }
    super.dispose();
  }
}
