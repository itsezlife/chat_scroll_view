import 'package:chat_scroll_view/src/chat_widgets/chat_message_change_params.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_message_change_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

export 'package:chat_scroll_view/src/chat_widgets/chat_message_change_params.dart';
export 'package:chat_scroll_view/src/chat_widgets/render_chat_message_change_transition.dart'
    show RenderChatMessageChangeTransition, ChatMessageChangePaintSample;

/// Slots for [ChatMessageChangeTransition].
enum ChatMessageChangeSlot {
  /// Optional band above content (sender name).
  header,

  /// Incoming body text.
  content,

  /// Incoming meta (time / edited / status) — laid out at final width.
  meta,

  /// Outgoing body text retained for crossfade.
  outgoingContent,

  /// Outgoing meta retained for crossfade.
  outgoingMeta,
}

/// Builds the meta row; [editedOpacity] is the **visual** fade for “edited”.
///
/// Hosts must **reserve** edited-label width even when [editedOpacity] is 0
/// so bubble layout stays final for the whole change animation. Collapsing
/// the label out of the tree mid-flight changes layout size while deltas are
/// frozen.
typedef ChatMessageChangeMetaBuilder =
    Widget Function(BuildContext context, double editedOpacity);

/// Message change transition (edit morph).
///
/// Layout size jumps to the **incoming** settled bubble immediately. Background
/// bounds animate via paint deltas; old/new text crossfade inside a clip of
/// that painted background (250ms list-item cubic).
class ChatMessageChangeTransition extends StatefulWidget {
  /// Creates a change-transition bubble host.
  const ChatMessageChangeTransition({
    required this.contentIdentity,
    required this.content,
    required this.metaBuilder,
    required this.color,
    required this.borderRadius,
    required this.outgoing,
    this.header,
    this.edited = false,
    this.spacing = 8,
    this.padding = EdgeInsets.zero,
    this.boxShadow,
    super.key,
  });

  /// Changes when the body text (or other morph identity) changes.
  final Object contentIdentity;

  /// Optional sender / forward band.
  final Widget? header;

  /// Incoming body.
  final Widget content;

  /// Meta row; rebuilds with [editedOpacity] during edited-enter.
  final ChatMessageChangeMetaBuilder metaBuilder;

  /// When true, meta includes an “edited” label (drives edited-enter).
  final bool edited;

  /// Outgoing bubble — width deltas prefer the leading edge.
  final bool outgoing;

  /// Bubble fill.
  final Color color;

  /// Bubble corners.
  final BorderRadiusGeometry borderRadius;

  /// Insets around header + content + meta.
  final EdgeInsetsGeometry padding;

  /// Last-line packing gap for content + meta.
  final double spacing;

  /// Optional drop shadow under the painted bubble.
  final List<BoxShadow>? boxShadow;

  @override
  State<ChatMessageChangeTransition> createState() =>
      _ChatMessageChangeTransitionState();
}

class _ChatMessageChangeTransitionState
    extends State<ChatMessageChangeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _measureMetaKey = GlobalKey();
  final GlobalKey _renderKey = GlobalKey();

  ChatMessageChangeParams _params = ChatMessageChangeParams.settled;

  Widget? _outgoingContent;
  Widget? _outgoingMeta;

  double _lastMetaWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: kChatMessageChangeDuration)
          ..addListener(_onTick)
          ..addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(covariant ChatMessageChangeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final textChanged = oldWidget.contentIdentity != widget.contentIdentity;
    final editedEnter = !oldWidget.edited && widget.edited;
    if (textChanged || editedEnter) {
      _beginChange(
        outgoingContent: oldWidget.content,
        outgoingIdentity: oldWidget.contentIdentity,
        textChanged: textChanged,
        editedEnter: editedEnter,
      );
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  void _onTick() {
    final curved = kChatMessageChangeCurve.transform(
      _controller.value.clamp(0.0, 1.0),
    );
    setState(() {
      _params = chatMessageChangeAtProgress(_params, curved);
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    setState(() {
      _outgoingContent = null;
      _outgoingMeta = null;
      _params = ChatMessageChangeParams.settled;
    });
  }

  void _beginChange({
    required Widget outgoingContent,
    required Object outgoingIdentity,
    required bool textChanged,
    required bool editedEnter,
  }) {
    final ro =
        _renderKey.currentContext?.findRenderObject()
            as RenderChatMessageChangeTransition?;
    final oldBackground = ro != null && ro.hasSize
        ? (ro.lastPaintedBackground == Rect.zero
              ? ro.finalBackgroundRect
              : ro.lastPaintedBackground)
        : null;

    final oldMetaWidth = _lastMetaWidth;
    final oldMetaOffset = ro?.metaOffset;

    _controller.stop();
    setState(() {
      _outgoingContent = outgoingContent;
      // Meta is not dual-crossfaded — only body text is.
      // Incoming meta handles edited-enter via opacity + meta paint offset.
      _outgoingMeta = null;
      // Hold painted bg at the previous rect until post-frame installs deltas.
      // Without this, the first layout/paint draws the full final bubble.
      _params = ChatMessageChangeParams(
        progress: 0,
        deltas: ChatMessageChangeDeltas.zero,
        animateMessageText: textChanged,
        animateBackgroundBounds: false,
        animateEditedEnter: editedEnter,
        editedWidthDiff: 0,
        holdPaintedBackground: oldBackground,
        animateFromMetaOffset: oldMetaOffset,
        animateFromMetaWidth: oldMetaWidth,
        shouldAnimateMetaX: editedEnter || oldMetaOffset != null,
      );
    });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final render =
          _renderKey.currentContext?.findRenderObject()
              as RenderChatMessageChangeTransition?;
      if (render == null || !render.hasSize) {
        _controller.forward(from: 0);
        return;
      }
      final newBackground = render.finalBackgroundRect;
      final oldBg = oldBackground ?? newBackground;

      var newMetaWidth = _lastMetaWidth;
      final metaBox =
          _measureMetaKey.currentContext?.findRenderObject() as RenderBox?;
      if (metaBox != null && metaBox.hasSize) {
        newMetaWidth = metaBox.size.width;
      }

      final editedWidthDiff = editedEnter ? (newMetaWidth - oldMetaWidth) : 0.0;
      final settledMeta = render.metaOffset;

      setState(() {
        _params = beginChatMessageChange(
          oldBackground: oldBg,
          newBackground: newBackground,
          textChanged: textChanged,
          editedEnter: editedEnter,
          editedWidthDiff: editedWidthDiff,
          animateFromMetaOffset: oldMetaOffset,
          animateFromMetaWidth: oldMetaWidth,
          settledMetaOffset: settledMeta,
        );
      });
      _controller
        ..duration = kChatMessageChangeDuration
        ..forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final editedOpacity = _params.animateEditedEnter
        ? _params.editedLabelOpacity
        : (widget.edited ? 1.0 : 0.0);

    final incomingMeta = _MetaHost(
      key: _measureMetaKey,
      builder: widget.metaBuilder,
      editedOpacity: editedOpacity,
      showEdited: widget.edited || _params.animateEditedEnter,
    );

    // Track meta width after layout for the next edited-enter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box =
          _measureMetaKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        _lastMetaWidth = box.size.width;
      }
    });

    return _ChatMessageChangeTransition(
      key: _renderKey,
      params: _params,
      color: widget.color,
      borderRadius: widget.borderRadius,
      padding: widget.padding,
      spacing: widget.spacing,
      boxShadow: widget.boxShadow,
      header: widget.header,
      content: widget.content,
      meta: incomingMeta,
      outgoingContent: _outgoingContent,
      outgoingMeta: _outgoingMeta,
    );
  }
}

class _MetaHost extends StatelessWidget {
  const _MetaHost({
    required this.builder,
    required this.editedOpacity,
    required this.showEdited,
    super.key,
  });

  final ChatMessageChangeMetaBuilder builder;
  final double editedOpacity;
  final bool showEdited;

  @override
  Widget build(BuildContext context) =>
      builder(context, showEdited ? editedOpacity : 0);
}

class _ChatMessageChangeTransition
    extends
        SlottedMultiChildRenderObjectWidget<ChatMessageChangeSlot, RenderBox> {
  const _ChatMessageChangeTransition({
    required this.params,
    required this.color,
    required this.borderRadius,
    required this.padding,
    required this.spacing,
    required this.meta,
    required this.content,
    this.header,
    this.outgoingContent,
    this.outgoingMeta,
    this.boxShadow,
    super.key,
  });

  final ChatMessageChangeParams params;
  final Color color;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final List<BoxShadow>? boxShadow;
  final Widget? header;
  final Widget content;
  final Widget meta;
  final Widget? outgoingContent;
  final Widget? outgoingMeta;

  @override
  Iterable<ChatMessageChangeSlot> get slots => ChatMessageChangeSlot.values;

  @override
  Widget? childForSlot(ChatMessageChangeSlot slot) => switch (slot) {
    ChatMessageChangeSlot.header => header,
    ChatMessageChangeSlot.content => content,
    ChatMessageChangeSlot.meta => meta,
    ChatMessageChangeSlot.outgoingContent => outgoingContent,
    ChatMessageChangeSlot.outgoingMeta => outgoingMeta,
  };

  @override
  SlottedContainerRenderObjectMixin<ChatMessageChangeSlot, RenderBox>
  createRenderObject(BuildContext context) => RenderChatMessageChangeTransition(
    params: params,
    color: color,
    borderRadius: borderRadius,
    padding: padding,
    spacing: spacing,
    boxShadow: boxShadow,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderChatMessageChangeTransition renderObject,
  ) {
    renderObject
      ..params = params
      ..color = color
      ..borderRadius = borderRadius
      ..padding = padding
      ..spacing = spacing
      ..boxShadow = boxShadow
      ..textDirection = Directionality.of(context);
  }
}
