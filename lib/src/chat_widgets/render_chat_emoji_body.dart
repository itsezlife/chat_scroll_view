import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart'
    show CompositingEmbed, InlineEmbed, InlineEmbedPaintContext;
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_geometry.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_text.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_text_layout.dart';
import 'package:chat_scroll_view/src/util/trace_section.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_md/flutter_md.dart'
    show
        MarkdownPosition,
        MarkdownSelectionController,
        MarkdownSelectionSurface;
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

  /// Whether the leaf may come as a layer of its own (an embed that plays on
  /// a platform texture), so the body composites. Signalled to the listeners
  /// when it changes.
  bool get needsCompositing => false;

  /// Shows the leaf in [rect] of [context]: as a layer, or on
  /// `context.canvas` read at the call, so a layer added before it is
  /// followed by a new picture.
  void composite(PaintingContext context, Rect rect, Color? tint) =>
      paint(context.canvas, rect, tint);

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
///
/// An embed that is a [CompositingEmbed] (ADR 043) is composited: while it
/// plays it may be a texture layer instead of a paint.
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
  bool get needsCompositing => switch (embed) {
    final CompositingEmbed embed => embed.needsCompositing,
    _ => false,
  };

  @override
  void composite(PaintingContext context, Rect rect, Color? tint) {
    switch (embed) {
      case final CompositingEmbed embed:
        embed.composite(context, rect, InlineEmbedPaintContext(tint: tint));
      default:
        paint(context.canvas, rect, tint);
    }
  }

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

/// Where an emoji-only body's text selection lives: the facade's markdown
/// controller, the id the body registered its model under and that model.
@internal
@immutable
final class ChatEmojiSelectionBinding {
  /// Binds [text] to [controller] under [documentId].
  const ChatEmojiSelectionBinding({
    required this.controller,
    required this.documentId,
    required this.text,
  });

  /// The controller that owns the selection range.
  final MarkdownSelectionController controller;

  /// The id the model is registered under (the message id).
  final Object documentId;

  /// The registered model and its item ranges.
  final ChatEmojiText text;

  @override
  bool operator ==(Object other) =>
      other is ChatEmojiSelectionBinding &&
      identical(other.controller, controller) &&
      other.documentId == documentId &&
      identical(other.text, text);

  @override
  int get hashCode => Object.hash(controller, documentId, text);
}

/// The colour of the selection highlight when the scope set none: the markdown
/// engine's own default, so the two bodies agree.
const Color _kSelectionColor = Color(0x552196F3);

/// Lays out and paints the items of an emoji-only body by its
/// [ChatEmojiLayoutSpec].
///
/// It wraps at the spec's limit of the incoming maximum width and shrinks to
/// the widest line, then adds the strip the host reserved. The text scale
/// plays no part: sizes come from the spec.
///
/// ## Text selection
///
/// With a [selection] binding the box is also a `MarkdownSelectionSurface`:
/// the same contract the markdown body's render object implements, so the
/// facade's range, the per-body scope's gestures, handles and toolbar work on
/// it unchanged. It answers from the item squares ([ChatEmojiTextLayout]); an
/// emoji is one atomic item, so every position it hands out is an item edge.
/// The highlight is painted under the items, never over an embed.
///
/// ## Texture
///
/// The box composites while any leaf [ChatEmojiLeaf.needsCompositing] (an
/// embed that plays, ADR 043): each leaf is then shown through the painting
/// context, so a frame on a platform texture is a texture layer after the
/// highlight and the items before it, and the items after it go on a new
/// picture. Otherwise every leaf paints on the canvas.
@internal
final class RenderChatEmojiBody extends RenderBox
    implements MarkdownSelectionSurface {
  /// Creates the render object.
  RenderChatEmojiBody({
    required List<ChatEmojiLeaf> leaves,
    required ChatEmojiLayoutSpec spec,
    Color? tint,
    ChatEmojiSelectionBinding? selection,
  }) : _leaves = leaves,
       _spec = spec,
       _tint = tint,
       _selection = selection;

  List<ChatEmojiLeaf> _leaves;
  ChatEmojiLayoutSpec _spec;
  Color? _tint;
  ChatEmojiSelectionBinding? _selection;
  ChatEmojiGeometry? _geometry;
  ChatEmojiTextLayout? _textLayout;
  bool _disposed = false;
  // Whether a leaf may come as a layer of its own, so the box composites.
  bool _leavesComposite = false;

  final Paint _highlightPaint = Paint();

  // Selection-handle leader layers, pushed during paint so the scope's
  // handles follow the content as the list scrolls (the markdown render
  // object's mechanism: one LeaderLayer per link, kept across paints).
  LayerLink? _startHandleLink;
  Offset? _startHandleLocal;
  LayerLink? _endHandleLink;
  Offset? _endHandleLocal;
  final LayerHandle<LeaderLayer> _startHandleLayer = LayerHandle<LeaderLayer>();
  final LayerHandle<LeaderLayer> _endHandleLayer = LayerHandle<LeaderLayer>();

  /// The items, in order. Another list repaints and lays out again.
  List<ChatEmojiLeaf> get leaves => _leaves;
  set leaves(List<ChatEmojiLeaf> value) {
    if (identical(_leaves, value)) return;
    if (attached) _unlisten();
    _leaves = value;
    if (attached) {
      _listen();
      _leafChanged();
    } else {
      markNeedsPaint();
    }
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

  /// The text selection this box is the surface of, or null for a box that is
  /// not selectable text (the sticker layout).
  ChatEmojiSelectionBinding? get selection => _selection;
  set selection(ChatEmojiSelectionBinding? value) {
    if (_selection == value) return;
    if (attached) _detachSelection();
    _selection = value;
    _textLayout = null;
    if (attached) _attachSelection();
    markNeedsLayout();
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

  /// The square of the item at [index], in this box's coordinates, or null
  /// before layout or for an index there is no item at.
  Rect? itemRect(int index) {
    final rects = _geometry?.items;
    return rects != null && index >= 0 && index < rects.length
        ? rects[index]
        : null;
  }

  /// The square of each selected item, in reading order, in this box's
  /// coordinates: the per-item boxes of the selection, for a highlight that
  /// wants them apart. Empty with no selection.
  List<Rect> get selectedItemBoxes => switch (_selectedRange) {
    final range? => _textLayout?.boxesForRange(range.start, range.end) ?? [],
    null => const <Rect>[],
  };

  /// One box per line over the selected items, in this box's coordinates:
  /// what the highlight paints.
  List<Rect> get selectedLineBoxes => switch (_selectedRange) {
    final range? =>
      _textLayout?.lineBoxesForRange(range.start, range.end) ?? [],
    null => const <Rect>[],
  };

  TextRange? get _selectedRange {
    final binding = _selection;
    if (binding == null) return null;
    final range = binding.controller.rangeFor(binding.documentId, 0);
    return range == null || range.isCollapsed ? null : range;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
    _leavesComposite = _leaves.any((leaf) => leaf.needsCompositing);
    _attachSelection();
  }

  @override
  void detach() {
    _unlisten();
    _detachSelection();
    super.detach();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _listen() {
    for (final leaf in _leaves) {
      leaf.addListener(_leafChanged);
    }
  }

  void _unlisten() {
    for (final leaf in _leaves) {
      leaf.removeListener(_leafChanged);
    }
  }

  void _leafChanged() {
    markNeedsPaint();
    final composites = _leaves.any((leaf) => leaf.needsCompositing);
    if (composites == _leavesComposite) return;
    _leavesComposite = composites;
    markNeedsCompositingBitsUpdate();
  }

  void _onSelectionChange() {
    if (!_disposed) markNeedsPaint();
  }

  void _attachSelection() {
    final binding = _selection;
    if (binding == null) return;
    // The same heal the markdown render object does: a mounted surface has
    // its document in the registry, whoever put it there first.
    binding.controller
      ..addListener(_onSelectionChange)
      ..putDocument(binding.documentId, binding.text.markdown)
      ..attachSurface(this);
  }

  void _detachSelection() {
    final binding = _selection;
    if (binding == null) return;
    binding.controller
      ..removeListener(_onSelectionChange)
      ..detachSurface(this);
    _startHandleLink = _endHandleLink = null;
    _startHandleLocal = _endHandleLocal = null;
    _startHandleLayer.layer = null;
    _endHandleLayer.layer = null;
  }

  ChatEmojiGeometry _geometryFor(double maxWidth) =>
      ChatEmojiGeometry.of(_spec, maxWidth: maxWidth);

  @override
  void performLayout() {
    final geometry = _geometry = _geometryFor(constraints.maxWidth);
    size = constraints.constrain(geometry.size);
    _textLayout = switch (_selection) {
      final binding? => ChatEmojiTextLayout(
        text: binding.text,
        items: geometry.items,
        direction: geometry.direction,
      ),
      null => null,
    };
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
  bool get alwaysNeedsCompositing =>
      _leavesComposite ||
      (_startHandleLink != null && _startHandleLocal != null) ||
      (_endHandleLink != null && _endHandleLocal != null);

  @override
  void paint(PaintingContext context, Offset offset) {
    final geometry = _geometry;
    if (geometry == null) return;
    final canvas = context.canvas;
    // The highlight sits under the items: an embed or a glyph is drawn as
    // itself, with no tint over it.
    if (_selection case final binding?) {
      _highlightPaint.color =
          binding.controller.selectionColor ?? _kSelectionColor;
      Trace.begin(TraceSection.paintSelection);
      for (final box in selectedLineBoxes) {
        canvas.drawRect(box.shift(offset), _highlightPaint);
      }
      Trace.end(TraceSection.paintSelection);
    }
    final count = math.min(_leaves.length, geometry.items.length);
    for (var i = 0; i < count; i++) {
      final rect = geometry.items[i].shift(offset);
      // A leaf that composites may add a layer, which ends the picture: the
      // leaves after it read the context's canvas afresh.
      if (_leavesComposite) {
        _leaves[i].composite(context, rect, _tint);
      } else {
        _leaves[i].paint(canvas, rect, _tint);
      }
    }
    _paintHandleLeaders(context, offset);
  }

  void _paintHandleLeaders(PaintingContext context, Offset offset) {
    final startLink = _startHandleLink;
    final startLocal = _startHandleLocal;
    if (startLink != null && startLocal != null) {
      _startHandleLayer.layer = LeaderLayer(
        link: startLink,
        offset: offset + startLocal,
      );
      context.pushLayer(_startHandleLayer.layer!, _paintNothing, Offset.zero);
    } else {
      _startHandleLayer.layer = null;
    }
    final endLink = _endHandleLink;
    final endLocal = _endHandleLocal;
    if (endLink != null && endLocal != null) {
      _endHandleLayer.layer = LeaderLayer(
        link: endLink,
        offset: offset + endLocal,
      );
      context.pushLayer(_endHandleLayer.layer!, _paintNothing, Offset.zero);
    } else {
      _endHandleLayer.layer = null;
    }
  }

  // --- MarkdownSelectionSurface ---------------------------------------------

  @override
  Object get documentId => _selection!.documentId;

  @override
  Rect get globalBounds => localToGlobal(Offset.zero) & size;

  // The direction the lines start from, which orients the handles.
  @override
  TextDirection get textDirection => _spec.direction;

  @override
  MarkdownPosition? positionForGlobal(Offset globalPosition) =>
      hitForGlobal(globalPosition)?.$1;

  @override
  (MarkdownPosition, TextAffinity)? hitForGlobal(Offset globalPosition) {
    final binding = _selection;
    final hit = _textLayout?.hitAt(globalToLocal(globalPosition));
    if (binding == null || hit == null) return null;
    return (
      MarkdownPosition(
        documentId: binding.documentId,
        blockIndex: 0,
        offset: hit.offset,
      ),
      hit.affinity,
    );
  }

  @override
  bool hitsSelectableGlyphs(Offset globalPosition) {
    if (_selection == null || !hasSize) return false;
    return _textLayout?.hitsItem(globalToLocal(globalPosition)) ?? false;
  }

  // An emoji is never a link or copy chrome: the facade answers its tap as an
  // embed or sticker hit instead.
  @override
  bool isLinkAtGlobal(Offset globalPosition) => false;

  @override
  Rect? caretRectFor(MarkdownPosition position, TextAffinity affinity) {
    final binding = _selection;
    if (binding == null ||
        position.documentId != binding.documentId ||
        position.blockIndex != 0) {
      return null;
    }
    return _textLayout?.caretRect(position.offset, affinity);
  }

  @override
  (int, int, int)? wordBoundaryForGlobal(Offset globalPosition) {
    final word = _textLayout?.wordAt(globalToLocal(globalPosition));
    return word == null ? null : (0, word.start, word.end);
  }

  @override
  List<Rect> localSelectionRects() => selectedLineBoxes;

  @override
  List<Rect> globalSelectionRects() {
    final origin = localToGlobal(Offset.zero);
    return [for (final rect in selectedLineBoxes) rect.shift(origin)];
  }

  @override
  List<Rect> localBoxesForRange(
    int blockIndex,
    int startOffset,
    int endOffset,
  ) => blockIndex == 0
      ? _textLayout?.boxesForRange(startOffset, endOffset) ?? const <Rect>[]
      : const <Rect>[];

  @override
  void setSelectionHandleLayers({
    LayerLink? startLink,
    Offset? startLocal,
    LayerLink? endLink,
    Offset? endLocal,
  }) {
    final changed =
        !identical(startLink, _startHandleLink) ||
        startLocal != _startHandleLocal ||
        !identical(endLink, _endHandleLink) ||
        endLocal != _endHandleLocal;
    _startHandleLink = startLink;
    _startHandleLocal = startLocal;
    _endHandleLink = endLink;
    _endHandleLocal = endLocal;
    if (!changed || _disposed || !attached) return;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get hasSelectionHandleLeaders =>
      _startHandleLink != null || _endHandleLink != null;

  @override
  void clearSelectionHandleLayersIfLinked({
    required LayerLink startLink,
    required LayerLink endLink,
  }) {
    final clearStart = identical(_startHandleLink, startLink);
    final clearEnd = identical(_endHandleLink, endLink);
    if (!clearStart && !clearEnd) return;
    setSelectionHandleLayers(
      startLink: clearStart ? null : _startHandleLink,
      startLocal: clearStart ? null : _startHandleLocal,
      endLink: clearEnd ? null : _endHandleLink,
      endLocal: clearEnd ? null : _endHandleLocal,
    );
  }

  @override
  void repaintSelection() {
    if (!_disposed && attached) markNeedsPaint();
  }
}

/// A no-op paint callback for pushing childless [LeaderLayer]s.
void _paintNothing(PaintingContext context, Offset offset) {}
