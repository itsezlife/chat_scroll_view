import 'package:chat_scroll_view/src/chat_widgets/chat_message_body_layout.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_message_change_transition.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Render object for [ChatMessageChangeTransition].
///
/// Layout size is always the **incoming** settled bubble. Background
/// grows/shrinks via [ChatMessageChangeParams] deltas at paint time; old/new
/// content are crossfaded inside a clip of the painted background.
class RenderChatMessageChangeTransition extends RenderBox
    with SlottedContainerRenderObjectMixin<ChatMessageChangeSlot, RenderBox> {
  /// Creates the change-transition render object.
  RenderChatMessageChangeTransition({
    required ChatMessageChangeParams params,
    required Color color,
    required BorderRadiusGeometry borderRadius,
    required EdgeInsetsGeometry padding,
    required double spacing,
    required TextDirection textDirection,
    List<BoxShadow>? boxShadow,
  }) : _params = params,
       _color = color,
       _borderRadius = borderRadius,
       _padding = padding,
       _spacing = spacing,
       _textDirection = textDirection,
       _boxShadow = boxShadow;

  ChatMessageChangeParams _params;
  Color _color;
  BorderRadiusGeometry _borderRadius;
  EdgeInsetsGeometry _padding;
  double _spacing;
  TextDirection _textDirection;
  List<BoxShadow>? _boxShadow;

  /// Last painted background rect (local) — for tests / recording the next
  /// transition's `oldBackground`.
  Rect lastPaintedBackground = Rect.zero;

  /// Append-only paint samples while [debugChatMessageChangeRecordPaints] is on.
  ///
  /// Cleared by diagnostic tests; each [paint] appends one sample so a
  /// one-frame flash is still observable after later paints overwrite
  /// [lastPaintedBackground].
  final List<ChatMessageChangePaintSample> debugPaintHistory =
      <ChatMessageChangePaintSample>[];

  /// Final layout rect of the bubble (`Offset.zero & settledSize`) after layout.
  ///
  /// Settled measure — not necessarily [size], which may expand to fit a
  /// larger painted background during shrink.
  Rect get finalBackgroundRect => Offset.zero & _settledSize;

  /// See [ChatMessageChangeTransition] / animation driver.
  ChatMessageChangeParams get params => _params;
  set params(ChatMessageChangeParams value) {
    if (_params == value) return;
    final relayout =
        _params.animateBackgroundBounds ||
        value.animateBackgroundBounds ||
        _params.progress != value.progress ||
        _params.holdPaintedBackground != value.holdPaintedBackground;
    _params = value;
    markNeedsPaint();
    if (relayout) markNeedsLayout();
  }

  /// Bubble fill.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  /// Bubble corners.
  BorderRadiusGeometry get borderRadius => _borderRadius;
  set borderRadius(BorderRadiusGeometry value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  /// Insets around the header + content + meta cluster.
  EdgeInsetsGeometry get padding => _padding;
  set padding(EdgeInsetsGeometry value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  /// Gap between last text line and meta when packed inline.
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  /// Resolves [padding]; taken from ambient [Directionality].
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Optional shadows painted under the bubble fill.
  List<BoxShadow>? get boxShadow => _boxShadow;
  set boxShadow(List<BoxShadow>? value) {
    if (_boxShadow == value) return;
    _boxShadow = value;
    markNeedsPaint();
  }

  EdgeInsets get _resolvedPadding => _padding.resolve(_textDirection);

  RenderBox? get _header => childForSlot(ChatMessageChangeSlot.header);
  RenderBox? get _content => childForSlot(ChatMessageChangeSlot.content);
  RenderBox? get _meta => childForSlot(ChatMessageChangeSlot.meta);
  RenderBox? get _outgoingContent =>
      childForSlot(ChatMessageChangeSlot.outgoingContent);
  RenderBox? get _outgoingMeta =>
      childForSlot(ChatMessageChangeSlot.outgoingMeta);

  @override
  Iterable<RenderBox> get children => <RenderBox>[
    ?_meta,
    ?_content,
    ?_header,
    ?_outgoingMeta,
    ?_outgoingContent,
  ];

  Offset _headerOffset = Offset.zero;
  Offset _contentOffset = Offset.zero;
  Offset _metaOffset = Offset.zero;
  Offset _outgoingContentOffset = Offset.zero;
  Offset _outgoingMetaOffset = Offset.zero;

  /// Settled (incoming) meta top-left after layout.
  Offset get metaOffset => _metaOffset;

  /// Painted meta top-left for the current [params] (tests / diagnostics).
  Offset get paintedMetaOffset => _params.metaPaintOffset(
    settledMeta: _metaOffset,
    finalRect: finalBackgroundRect,
    currentMetaWidth: _meta?.hasSize == true ? _meta!.size.width : null,
  );

  /// Incoming packed bubble size — settled measure used for deltas.
  ///
  /// [size] may be larger during a shrink morph so the painted old rect is not
  /// clipped by ancestors; deltas always apply against this settled rect.
  Size _settledSize = Size.zero;

  /// Incoming content top — used to lerp outgoing text Y when heights differ.
  double get _incomingContentTop => _contentOffset.dy;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final child = _content ?? _header ?? _meta;
    if (child == null) return null;
    final distance = child.getDistanceToActualBaseline(baseline);
    if (distance == null) return null;
    return distance + _offsetOf(child).dy;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _measureIncoming(constraints, dry: true).size;

  @override
  void performLayout() {
    final incoming = _measureIncoming(constraints, dry: false);
    _settledSize = incoming.size;
    _headerOffset = incoming.headerOffset;
    _contentOffset = incoming.contentOffset;
    _metaOffset = incoming.metaOffset;

    final header = _header;
    if (header != null) {
      _positionChild(header, _headerOffset);
    }
    final content = _content;
    if (content != null) {
      _positionChild(content, _contentOffset);
    }
    final meta = _meta;
    if (meta != null) {
      _positionChild(meta, _metaOffset);
    }

    _layoutOutgoing(constraints);

    // Settled = final measure (deltas apply against it).
    // Host [size] tracks the *painted* bubble during a change so list space
    // morphs with the fill — not max(settled, painted), which jumps to final
    // on expand while the fill is still small.
    final settledRect = Offset.zero & _settledSize;
    final painted = _params.paintedBackground(settledRect);
    final morphing =
        _params.holdPaintedBackground != null ||
        (_params.animateBackgroundBounds && _params.progress < 1);
    final hostExtent = morphing
        ? Size(painted.width, painted.height)
        : _settledSize;
    size = constraints.constrain(hostExtent);
  }

  ChatMessageBodyLayout _measureIncoming(
    BoxConstraints constraints, {
    required bool dry,
  }) {
    final padding = _resolvedPadding;
    final availableWidth = (constraints.maxWidth - padding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final childConstraints = BoxConstraints(maxWidth: availableWidth);

    final header = _header;
    final content = _content;
    final meta = _meta;
    final headerSize = header == null
        ? Size.zero
        : _layoutChild(header, childConstraints, dry: dry);
    final contentSize = content == null
        ? Size.zero
        : _layoutChild(content, childConstraints, dry: dry);
    final metaSize = meta == null
        ? Size.zero
        : _layoutChild(meta, childConstraints, dry: dry);

    // Body layout is relative to the padded origin; lift by padding.
    final inner = layoutChatMessageBody(
      constraints: BoxConstraints(maxWidth: availableWidth),
      padding: EdgeInsets.zero,
      spacing: _spacing,
      headerSize: headerSize,
      contentSize: contentSize,
      metaSize: metaSize,
      hasContent: content != null,
      hasMeta: meta != null,
      lastLineWidth: () {
        if (content == null) return 0.0;
        if (dry) return contentSize.width;
        return lastLineWidthOf(content, fallback: contentSize.width);
      },
    );

    final outer = constraints.constrain(
      Size(
        inner.size.width + padding.horizontal,
        inner.size.height + padding.vertical,
      ),
    );
    final origin = Offset(padding.left, padding.top);
    return ChatMessageBodyLayout(
      size: outer,
      headerOffset: origin + inner.headerOffset,
      contentOffset: origin + inner.contentOffset,
      metaOffset: origin + inner.metaOffset,
    );
  }

  void _layoutOutgoing(BoxConstraints constraints) {
    final outgoingContent = _outgoingContent;
    final outgoingMeta = _outgoingMeta;
    if (outgoingContent == null && outgoingMeta == null) {
      _outgoingContentOffset = Offset.zero;
      _outgoingMetaOffset = Offset.zero;
      return;
    }

    final padding = _resolvedPadding;
    final availableWidth = (constraints.maxWidth - padding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final childConstraints = BoxConstraints(maxWidth: availableWidth);

    final header = _header;
    final headerSize = header == null
        ? Size.zero
        : header.size; // already laid out with incoming
    final contentSize = outgoingContent == null
        ? Size.zero
        : _layoutChild(outgoingContent, childConstraints, dry: false);
    final metaSize = outgoingMeta == null
        ? Size.zero
        : _layoutChild(outgoingMeta, childConstraints, dry: false);

    final inner = layoutChatMessageBody(
      constraints: BoxConstraints(maxWidth: availableWidth),
      padding: EdgeInsets.zero,
      spacing: _spacing,
      headerSize: headerSize,
      contentSize: contentSize,
      metaSize: metaSize,
      hasContent: outgoingContent != null,
      hasMeta: outgoingMeta != null,
      lastLineWidth: () {
        if (outgoingContent == null) return 0.0;
        return lastLineWidthOf(outgoingContent, fallback: contentSize.width);
      },
    );

    final origin = Offset(padding.left, padding.top);
    // Keep header shared; only content/meta are outgoing layers.
    _outgoingContentOffset = origin + inner.contentOffset;
    _outgoingMetaOffset = origin + inner.metaOffset;

    if (outgoingContent != null) {
      _positionChild(outgoingContent, _outgoingContentOffset);
    }
    if (outgoingMeta != null) {
      _positionChild(outgoingMeta, _outgoingMetaOffset);
    }
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
    final finalRect = finalBackgroundRect;
    final paintedLocal = _params.paintedBackground(finalRect);
    lastPaintedBackground = paintedLocal;
    if (debugChatMessageChangeRecordPaints) {
      final metaW = _meta?.hasSize == true ? _meta!.size.width : 0.0;
      final metaPaint = _params.metaPaintOffset(
        settledMeta: _metaOffset,
        finalRect: finalRect,
        currentMetaWidth: metaW > 0 ? metaW : null,
      );
      debugPaintHistory.add(
        ChatMessageChangePaintSample(
          progress: _params.progress,
          animateBackgroundBounds: _params.animateBackgroundBounds,
          animateMessageText: _params.animateMessageText,
          finalRect: finalRect,
          paintedLocal: paintedLocal,
          metaPaint: metaPaint,
          metaWidth: metaW,
          holdingBackground: _params.holdPaintedBackground != null,
        ),
      );
    }
    final painted = paintedLocal.shift(offset);

    final radius = _borderRadius.resolve(_textDirection);
    final rrect = radius.toRRect(painted);

    final shadows = _boxShadow;
    if (shadows != null) {
      for (final shadow in shadows) {
        final paint = shadow.toPaint();
        context.canvas.drawRRect(rrect.shift(shadow.offset), paint);
      }
    }
    context.canvas.drawRRect(rrect, Paint()..color = _color);

    final clipLocal = _params.textClipRect(finalRect);
    final clip = clipLocal.shift(offset);
    context.canvas.save();
    context.canvas.clipRect(clip);

    // Header is shared chrome — paint once above the text crossfade.
    final header = _header;
    if (header != null) {
      context.paintChild(header, offset + _headerOffset);
    }

    final outgoingContent = _outgoingContent;
    final animatingText = _params.animateMessageText && outgoingContent != null;

    if (animatingText) {
      final outOpacity = _params.outgoingTextOpacity;
      final inOpacity = _params.incomingTextOpacity;

      var outContentPaint = offset + _outgoingContentOffset;
      if (_content != null) {
        final fromY = _outgoingContentOffset.dy;
        final toY = _incomingContentTop;
        final y = fromY * _params.oneMinusProgress + toY * _params.progress;
        outContentPaint = Offset(
          offset.dx + _outgoingContentOffset.dx,
          offset.dy + y,
        );
      }

      // Body text only — dual meta was painting two timestamps in the clip.
      if (outOpacity > 0) {
        _paintLayer(
          context,
          bounds: clip,
          opacity: outOpacity,
          paintChildren: () {
            context.paintChild(outgoingContent, outContentPaint);
          },
        );
      }

      if (inOpacity > 0) {
        final content = _content;
        if (content != null) {
          _paintLayer(
            context,
            bounds: clip,
            opacity: inOpacity,
            paintChildren: () {
              context.paintChild(content, offset + _contentOffset);
            },
          );
        }
      }
    } else {
      final content = _content;
      if (content != null) {
        context.paintChild(content, offset + _contentOffset);
      }
    }

    // Single incoming meta — paint offset from change params.
    final meta = _meta;
    if (meta != null) {
      final paintMeta = _params.metaPaintOffset(
        settledMeta: _metaOffset,
        finalRect: finalRect,
        currentMetaWidth: meta.hasSize ? meta.size.width : null,
      );
      context.paintChild(meta, offset + paintMeta);
    }

    context.canvas.restore();
  }

  void _paintLayer(
    PaintingContext context, {
    required Rect bounds,
    required double opacity,
    required VoidCallback paintChildren,
  }) {
    if (opacity >= 0.999) {
      paintChildren();
      return;
    }
    if (opacity <= 0.001) return;
    // Bound the layer to the text clip — unbounded saveLayer composited two
    // full-bubble text stacks and looked like stacked ghosts.
    context.canvas.saveLayer(
      bounds,
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    paintChildren();
    context.canvas.restore();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Prefer incoming (settled) children.
    for (final child in <RenderBox?>[_meta, _content, _header]) {
      if (child == null) continue;
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

  @override
  bool hitTestSelf(Offset position) => size.contains(position);
}

/// One [RenderChatMessageChangeTransition.paint] sample for diagnostics.
@immutable
class ChatMessageChangePaintSample {
  /// Creates a paint-history sample.
  const ChatMessageChangePaintSample({
    required this.progress,
    required this.animateBackgroundBounds,
    required this.animateMessageText,
    required this.finalRect,
    required this.paintedLocal,
    this.metaPaint = Offset.zero,
    this.metaWidth = 0,
    this.holdingBackground = false,
  });

  /// [ChatMessageChangeParams.progress] at paint time.
  final double progress;

  /// [ChatMessageChangeParams.animateBackgroundBounds] at paint time.
  final bool animateBackgroundBounds;

  /// [ChatMessageChangeParams.animateMessageText] at paint time.
  final bool animateMessageText;

  /// Layout rect (`Offset.zero & size`).
  final Rect finalRect;

  /// Rect actually drawn for the bubble fill.
  final Rect paintedLocal;

  /// Painted meta top-left at this sample.
  final Offset metaPaint;

  /// Laid-out meta width at this sample.
  final double metaWidth;

  /// True when [ChatMessageChangeParams.holdPaintedBackground] was set.
  final bool holdingBackground;

  /// True when this paint drew the full final rect while still claiming a
  /// text-change animation at p≈0 without background deltas or a hold —
  /// the flash.
  bool get isPreDeltaFullFinalFlash =>
      progress < 0.05 &&
      animateMessageText &&
      !animateBackgroundBounds &&
      (paintedLocal.height - finalRect.height).abs() < 1.0 &&
      (paintedLocal.width - finalRect.width).abs() < 1.0;

  /// True when the meta row extends past the painted bubble's right edge.
  bool get metaOverflowsPaintedBubble =>
      metaWidth > 0 && metaPaint.dx + metaWidth > paintedLocal.right + 0.5;

  @override
  String toString() =>
      'PaintSample(p=${progress.toStringAsFixed(3)}, '
      'animBg=$animateBackgroundBounds animText=$animateMessageText '
      'final=$finalRect painted=$paintedLocal '
      'meta=$metaPaint w=${metaWidth.toStringAsFixed(1)} '
      'hold=$holdingBackground '
      'flash=$isPreDeltaFullFinalFlash overflow=$metaOverflowsPaintedBubble)';
}
