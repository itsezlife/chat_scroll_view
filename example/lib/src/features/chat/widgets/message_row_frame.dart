import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/widgets/cached_label.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The slots of a [MessageRowFrame].
enum MessageRowSlot {
  /// The message bubble.
  bubble,

  /// The sender's avatar beside an incoming bubble, or none.
  avatar,
}

/// Places a message bubble in the message column, as a native chat cell does:
/// one render object for the column, the run insets, the avatar gutter and
/// the side the bubble sits on.
///
/// The same layout as widgets took an `Align`, a `ConstrainedBox`, a
/// `Padding`, a `Row` with spacers and a `Flexible`, all under a
/// `LayoutBuilder` for the bubble cap: a dozen elements built for every row
/// a scroll brings in. The frame reads the viewport width from its
/// constraints instead.
class MessageRowFrame
    extends SlottedMultiChildRenderObjectWidget<MessageRowSlot, RenderBox> {
  /// Frames [bubble] for a row of [theme], with [avatar] beside it when the
  /// row is incoming and the last of its run.
  const MessageRowFrame({
    required this.theme,
    required this.outgoing,
    required this.runLayout,
    required this.bubble,
    this.avatar,
    super.key,
  });

  /// Column, inset and avatar tokens.
  final ChatMessageThemeData theme;

  /// Whether the bubble sits at the column's end and has no avatar gutter.
  final bool outgoing;

  /// The row's place in its sender run: its top and bottom insets.
  final MessageRunLayout runLayout;

  /// The bubble, constrained to the theme's bubble cap.
  final Widget bubble;

  /// The avatar of an incoming row; null leaves its gutter empty.
  final Widget? avatar;

  @override
  Iterable<MessageRowSlot> get slots => MessageRowSlot.values;

  @override
  Widget? childForSlot(MessageRowSlot slot) => switch (slot) {
    MessageRowSlot.bubble => bubble,
    MessageRowSlot.avatar => avatar,
  };

  @override
  RenderMessageRowFrame createRenderObject(BuildContext context) =>
      RenderMessageRowFrame(
        theme: theme,
        outgoing: outgoing,
        runLayout: runLayout,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMessageRowFrame renderObject,
  ) {
    renderObject
      ..theme = theme
      ..outgoing = outgoing
      ..runLayout = runLayout
      ..textDirection = Directionality.of(context);
  }
}

/// Render object of [MessageRowFrame].
class RenderMessageRowFrame extends RenderBox
    with SlottedContainerRenderObjectMixin<MessageRowSlot, RenderBox> {
  /// A frame for a row of [theme].
  RenderMessageRowFrame({
    required ChatMessageThemeData theme,
    required bool outgoing,
    required MessageRunLayout runLayout,
    required TextDirection textDirection,
  }) : _theme = theme,
       _outgoing = outgoing,
       _runLayout = runLayout,
       _textDirection = textDirection;

  ChatMessageThemeData _theme;
  set theme(ChatMessageThemeData value) {
    if (value == _theme) return;
    _theme = value;
    markNeedsLayout();
  }

  bool _outgoing;
  set outgoing(bool value) {
    if (value == _outgoing) return;
    _outgoing = value;
    markNeedsLayout();
  }

  MessageRunLayout _runLayout;
  set runLayout(MessageRunLayout value) {
    if (value == _runLayout) return;
    _runLayout = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox? get _bubble => childForSlot(MessageRowSlot.bubble);
  RenderBox? get _avatar => childForSlot(MessageRowSlot.avatar);

  @override
  // The avatar first, as it leads the row: paint and semantics order.
  Iterable<RenderBox> get children => [?_avatar, ?_bubble];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BoxParentData) child.parentData = BoxParentData();
  }

  static void _place(RenderBox child, double x, double y) =>
      (child.parentData! as BoxParentData).offset = Offset(x, y);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  void performLayout() => size = _layout(constraints, dry: false);

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final theme = _theme;
    final width = constraints.maxWidth;
    final columnWidth = theme.columnWidth(width);
    final alignment = theme
        .columnAlignment(viewportWidth: width, outgoing: _outgoing)
        .resolve(_textDirection);
    final columnLeft = alignment.alongOffset(Offset(width - columnWidth, 0)).dx;
    final top = theme.topInset(isFirstInRun: _runLayout.isFirstInSenderRun);
    final bottom = theme.bottomInset(isLastInRun: _runLayout.isLastInSenderRun);
    final left = columnLeft + theme.padding.left;
    final inner = math.max<double>(0, columnWidth - theme.padding.horizontal);
    final gutter = _outgoing ? 0.0 : theme.avatarSize + theme.avatarGap;
    final cap = BoxConstraints(
      maxWidth: math.min(
        theme.bubbleCap(width, hasAvatarGutter: !_outgoing),
        math.max<double>(0, inner - gutter),
      ),
    );

    final bubble = _bubble;
    final bubbleSize = switch (bubble) {
      null => Size.zero,
      final b when dry => b.getDryLayout(cap),
      final b => (b..layout(cap, parentUsesSize: true)).size,
    };
    final avatar = _avatar;
    final avatarSize = switch (avatar) {
      null => Size.zero,
      final a when dry => a.getDryLayout(const BoxConstraints()),
      final a => (a..layout(const BoxConstraints(), parentUsesSize: true)).size,
    };
    final rowHeight = math.max(bubbleSize.height, avatarSize.height);

    final contentHeight = top + rowHeight + bottom;
    final size = constraints.constrain(Size(width, contentHeight));
    if (!dry) {
      final ltr = _textDirection == TextDirection.ltr;
      // Height the parent forces beyond the content is shared out by the
      // column alignment, as an `Align` around the column would.
      final rowTop =
          top +
          alignment.alongOffset(Offset(0, size.height - contentHeight)).dy;
      // The bubble sits on the row's bottom edge, beside the gutter or at
      // the column's end.
      final bubbleTop = rowTop + rowHeight - bubbleSize.height;
      final double bubbleLeft;
      if (_outgoing) {
        bubbleLeft = ltr ? left + inner - bubbleSize.width : left;
      } else {
        bubbleLeft = ltr
            ? left + gutter
            : left + inner - gutter - bubbleSize.width;
      }
      if (bubble != null) _place(bubble, bubbleLeft, bubbleTop);
      if (avatar != null) {
        _place(
          avatar,
          ltr ? left : left + inner - avatarSize.width,
          rowTop + rowHeight - avatarSize.height,
        );
      }
    }
    return size;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      switch (_bubble) {
        final b? => switch (b.getDistanceToActualBaseline(baseline)) {
          final d? => d + (b.parentData! as BoxParentData).offset.dy,
          null => null,
        },
        null => null,
      };

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [?_bubble, ?_avatar]) {
      final offset = (child.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, local) => child.hitTest(result, position: local),
      );
      if (hit) return true;
    }
    return false;
  }
}

/// A sender's avatar: a disc in the sender's colour with their initial.
///
/// One render object for what a `MouseRegion`, a `GestureDetector`, a
/// `Container` and a `Text` drew before. A tap calls [onTap]; a long press
/// is taken and dropped, so pressing the avatar never selects the message.
class MessageAvatar extends LeafRenderObjectWidget {
  /// An avatar of [size] for [sender] in [color].
  const MessageAvatar({
    required this.sender,
    required this.size,
    required this.color,
    this.onTap,
    super.key,
  });

  /// Whose avatar; its first character is drawn.
  final String sender;

  /// Diameter.
  final double size;

  /// Disc colour.
  final Color color;

  /// Called on a tap; null when the avatar takes none.
  final VoidCallback? onTap;

  static const TextStyle _initialStyle = TextStyle(
    color: Color(0xFFFFFFFF),
    fontWeight: FontWeight.w700,
    fontSize: 14,
    height: 1,
  );

  TextPainter _initial(BuildContext context) => CachedLabel.painterFor(
    sender.isEmpty ? '?' : sender.characters.first.toUpperCase(),
    DefaultTextStyle.of(context).style.merge(_initialStyle),
    scaler: MediaQuery.textScalerOf(context),
    direction: Directionality.of(context),
  );

  // A message being selected takes no avatar tap.
  VoidCallback? _tap(BuildContext context) =>
      (ChatSelectionStateScope.maybeOf(context)?.canPerformActions ?? true)
      ? onTap
      : null;

  @override
  RenderMessageAvatar createRenderObject(BuildContext context) =>
      RenderMessageAvatar(
        size: size,
        color: color,
        initial: _initial(context),
        onTap: _tap(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMessageAvatar renderObject,
  ) {
    renderObject
      ..diameter = size
      ..color = color
      ..initial = _initial(context)
      ..onTap = _tap(context);
  }
}

/// Render object of [MessageAvatar].
class RenderMessageAvatar extends RenderBox implements MouseTrackerAnnotation {
  /// An avatar disc of [size].
  RenderMessageAvatar({
    required double size,
    required Color color,
    required TextPainter initial,
    VoidCallback? onTap,
  }) : _diameter = size,
       _color = color,
       _initial = initial,
       _onTap = onTap;

  double _diameter;
  set diameter(double value) {
    if (value == _diameter) return;
    _diameter = value;
    markNeedsLayout();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  TextPainter _initial;
  set initial(TextPainter value) {
    if (identical(value, _initial)) return;
    _initial = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  VoidCallback? _onTap;
  set onTap(VoidCallback? value) {
    if ((value == null) == (_onTap == null)) {
      _onTap = value;
      return;
    }
    _onTap = value;
    markNeedsSemanticsUpdate();
  }

  late final TapGestureRecognizer _tapRecognizer = TapGestureRecognizer(
    debugOwner: this,
  )..onTap = _handleTap;

  late final LongPressGestureRecognizer _longPress = LongPressGestureRecognizer(
    debugOwner: this,
  )..onLongPress = () {};

  void _handleTap() => _onTap?.call();

  @override
  void dispose() {
    _tapRecognizer.dispose();
    _longPress.dispose();
    super.dispose();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(Size.square(_diameter));

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is! PointerDownEvent) return;
    if (_onTap != null) _tapRecognizer.addPointer(event);
    _longPress.addPointer(event);
  }

  @override
  MouseCursor get cursor =>
      _onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic;

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  @override
  bool get validForMouseTracker => attached;

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = offset & size;
    context.canvas.drawOval(rect, Paint()..color = _color);
    _initial.paint(
      context.canvas,
      rect.center - Offset(_initial.width / 2, _initial.height / 2),
    );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _initial.plainText
      ..textDirection = _initial.textDirection;
    if (_onTap != null) config.onTap = _handleTap;
  }
}
