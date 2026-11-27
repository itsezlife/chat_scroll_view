import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatSelectionController;
import 'package:content_model/content_model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/bubble/media_bubble_composition.dart';
import 'package:message_media/src/bubble/media_bubble_geometry.dart';
import 'package:message_media/src/chrome/media_options_affordance.dart';
import 'package:message_media/src/gesture/media_viewer_request.dart';
import 'package:message_media/src/layout/link_preview_card.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/message_media_hit_part.dart';
import 'package:message_media/src/paint/link_preview_card_view.dart';
import 'package:message_media/src/paint/message_media_body.dart'
    show LinkPreviewActivated;
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:message_media/src/transition/media_layout_transition.dart';
import 'package:message_media/src/transition/media_transition_policy.dart';
import 'package:message_media/src/transition/message_media_transition.dart';
import 'package:mpx_core/mpx_core.dart';

/// The optional media bubble's content: a message's media, its caption, its
/// header and the time over the media, placed by the message's
/// `invertMedia` and moved on the media's transition clock.
///
/// The host keeps the bubble itself (its fill, its tail by
/// [MediaBubbleShape.of], its reactions) and the text: the [caption] is the
/// message's own text body (the viewport's, which owns its selection), the
/// [header] the host's name, forward or reply header, the [time] the host's
/// pill. This widget is as large as the bubble's content and positions them.
///
/// ## Use
///
/// Lay the media out from the composition's input, so the corners know
/// which sides touch text:
///
/// ```dart
/// final input = composition.inputFor(baseInput);
/// final layout = policy.layout(input);
/// MessageMediaBubbleLayout(
///   layout: layout,
///   items: items,
///   policy: policy,
///   composition: composition,
///   caption: captionBody,
///   captionRevision: captionText,
/// );
/// ```
///
/// ## Widths
///
/// The caption is laid out at the layout's `MediaWidthMetrics.captionMaxWidth`
/// less [textPadding] (`widenMedia`: the bubble's max content width;
/// `wrapAtMedia`: the media's max width). The media widens to a wider
/// caption when the host passes the caption's measured width to the layout
/// (`MediaLayoutInput.captionWidth`); this widget never stretches media.
/// The header is laid out to the media's width and truncates there (its
/// own overflow); it never widens the bubble.
///
/// ## Time
///
/// When the time sits over the media ([MediaBubbleTime.overMedia]) [time]
/// is laid out tight at `MediaLayout.timePill`; elsewhere the host places
/// the time in its text and leaves [time] null.
///
/// ## Captions
///
/// An album has the one [caption], above or below. A file stack's files
/// keep their own captions ([fileCaptions]), each in its row's caption slot
/// (`MediaFileRow.captionSlot`, from `MediaLayoutInput.fileCaptionHeights`).
///
/// ## Transitions
///
/// One clock per message ([MessageMediaTransition]) moves the media, the
/// bubble and the caption. A change of [composition]'s `invertMedia`
/// reports the `invertMedia` trigger and slides the caption to its other
/// side; a caption added, removed or edited (a new [captionRevision])
/// reports `caption`, and the old caption cross-fades into the new by the
/// frame's progress. Policy timings, reduce motion and interrupts are the
/// clock's.
class MessageMediaBubbleLayout extends StatefulWidget {
  /// The bubble content of [layout] of [items], composed as [composition].
  const MessageMediaBubbleLayout({
    required this.layout,
    required this.items,
    required this.policy,
    required this.composition,
    this.caption,
    this.captionRevision,
    this.header,
    this.time,
    this.fileCaptions = const {},
    this.textPadding = const EdgeInsets.fromLTRB(10, 6, 10, 6),
    this.downloadContext,
    this.correlation = ChatCorrelation.none,
    this.chromeContext = MediaChromeContext.none,
    this.selectionProgress,
    this.selection,
    this.messageId,
    this.onOpenViewer,
    this.onItemMenu,
    this.onLinkPreview,
    this.linkPreviewColors = LinkPreviewCardColors.fallback,
    super.key,
  });

  /// The media laid out from `composition.inputFor(...)`, radii resolved
  /// (`MessageMediaPolicy.layout`).
  final MediaLayout layout;

  /// The items [layout] lays out.
  final List<MediaItem> items;

  /// The policy whose transition, cells and chrome the media follows; its
  /// corner policy's `bubbleInset` insets the media.
  final MessageMediaPolicy policy;

  /// What the bubble holds besides the media.
  final MediaBubbleComposition composition;

  /// The message's caption: its text body; null without one.
  final Widget? caption;

  /// The caption's content identity (its text, or an edit revision): a new
  /// value cross-fades the old caption into the new.
  final Object? captionRevision;

  /// The header (name, forward, reply), laid out to the media's width.
  final Widget? header;

  /// The host's time pill, laid out at `MediaLayout.timePill`.
  final Widget? time;

  /// Each file's own caption in a file stack, by item.
  final Map<MediaItemId, Widget> fileCaptions;

  /// The space around a text row (header, caption).
  final EdgeInsets textPadding;

  /// The class of conversation the media is shown in.
  final AutoDownloadContext? downloadContext;

  /// The chat and message the diagnostics events name.
  final ChatCorrelation correlation;

  /// What the message is drawn in, which the chrome slots weigh.
  final MediaChromeContext chromeContext;

  /// The selection checkbox's appearance, 0 to 1.
  final Animation<double>? selectionProgress;

  /// See `MessageMediaView.selection`.
  final ChatSelectionController? selection;

  /// See `MessageMediaView.messageId`.
  final int? messageId;

  /// See `MessageMediaView.onOpenViewer`.
  final ValueChanged<MediaViewerRequest>? onOpenViewer;

  /// See `MessageMediaView.onItemMenu`.
  final void Function(MediaHitPart part, Rect rect)? onItemMenu;

  /// See `MessageMediaView.onLinkPreview`.
  final LinkPreviewActivated? onLinkPreview;

  /// See `MessageMediaView.linkPreviewColors`.
  final LinkPreviewCardColors linkPreviewColors;

  @override
  State<MessageMediaBubbleLayout> createState() =>
      _MessageMediaBubbleLayoutState();
}

class _MessageMediaBubbleLayoutState extends State<MessageMediaBubbleLayout> {
  // Where the host's time goes: the pill over the media, or the slot a
  // card that ends the bubble keeps for it (its own line, or its bottom
  // inset).
  static Rect? _timeSlotOf(MediaLayout layout) =>
      layout.timePill ??
      switch (layout.blocks) {
        [
          ...,
          MediaBlock$LinkPreview(card: LinkPreviewCard(:final timeSlot?)),
        ] =>
          timeSlot,
        _ => null,
      };

  /// Counts the changes only the bubble shows (caption, invertMedia).
  int _revision = 0;

  /// Counts the legs the clock starts, so the bubble knows where one
  /// begins.
  int _leg = 0;

  MediaTransitionTrigger? _trigger;

  /// The caption leaving while the new one fades in; null when none does.
  Widget? _outgoingCaption;

  /// Whether the caption fades on the leg running.
  bool _captionFades = false;

  @override
  void didUpdateWidget(MessageMediaBubbleLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    final inverted =
        widget.composition.invertMedia != oldWidget.composition.invertMedia;
    final captionChanged =
        (widget.caption == null) != (oldWidget.caption == null) ||
        widget.captionRevision != oldWidget.captionRevision;
    _trigger = inverted
        ? MediaTransitionTrigger.invertMedia
        : captionChanged
        ? MediaTransitionTrigger.caption
        : null;
    final layoutChanged = widget.layout != oldWidget.layout;
    if (inverted || captionChanged) _revision++;
    if (inverted || captionChanged || layoutChanged) {
      _leg++;
      _captionFades = captionChanged;
      _outgoingCaption = captionChanged ? oldWidget.caption : null;
    }
  }

  @override
  Widget build(BuildContext context) => MessageMediaTransition(
    layout: widget.layout,
    items: widget.items,
    policy: widget.policy,
    trigger: _trigger,
    revision: _revision,
    downloadContext: widget.downloadContext,
    correlation: widget.correlation,
    chromeContext: widget.chromeContext,
    selectionProgress: widget.selectionProgress,
    selection: widget.selection,
    messageId: widget.messageId,
    onOpenViewer: widget.onOpenViewer,
    onItemMenu: widget.onItemMenu,
    onLinkPreview: widget.onLinkPreview,
    linkPreviewColors: widget.linkPreviewColors,
    builder: _bubble,
  );

  Widget _bubble(
    BuildContext context,
    MediaTransitionFrame frame,
    Widget media,
  ) {
    final layout = frame.layout;
    final fading = _captionFades && frame.progress < 1;
    final progress = frame.progress;
    final fileSlots = <MediaItemId, Rect>{
      for (final block in layout.blocks)
        if (block case MediaBlock$FileStack(:final rows))
          for (final row in rows) row.itemId: ?row.captionSlot,
    };
    return _MediaBubble(
      media: media,
      header: widget.header,
      caption: switch (widget.caption) {
        final caption? => Opacity(
          opacity: fading ? progress : 1,
          child: caption,
        ),
        null => null,
      },
      outgoingCaption: switch (_outgoingCaption) {
        final caption? when fading => Opacity(
          opacity: 1 - progress,
          child: caption,
        ),
        _ => null,
      },
      time: switch (_timeSlotOf(layout)) {
        final _? => widget.time,
        null => null,
      },
      fileCaptions: switch ([
        for (final MapEntry(:key, :value) in widget.fileCaptions.entries)
          if (fileSlots[key] case final slot?)
            Positioned(
              left: slot.left,
              top: slot.top,
              width: slot.width,
              child: value,
            ),
      ]) {
        [] => null,
        final positioned => SizedBox.fromSize(
          size: layout.size,
          child: Stack(clipBehavior: Clip.none, children: positioned),
        ),
      },
      timePill: _timeSlotOf(layout),
      captionMaxWidth: layout.widthMetrics?.captionMaxWidth,
      mediaInset: widget.policy.corners.bubbleInset,
      textPadding: widget.textPadding,
      hasCaption: widget.caption != null,
      above: widget.composition.textFirst(hasItems: widget.items.isNotEmpty),
      leg: _leg,
      progress: progress,
    );
  }
}

// --- The bubble's render ---

/// A child of the bubble's render.
enum _Part { media, fileCaptions, header, outgoingCaption, caption, time }

class _MediaBubble
    extends SlottedMultiChildRenderObjectWidget<_Part, RenderBox> {
  const _MediaBubble({
    required this.media,
    required this.header,
    required this.caption,
    required this.outgoingCaption,
    required this.time,
    required this.fileCaptions,
    required this.timePill,
    required this.captionMaxWidth,
    required this.mediaInset,
    required this.textPadding,
    required this.hasCaption,
    required this.above,
    required this.leg,
    required this.progress,
  });

  final Widget media;
  final Widget? header;
  final Widget? caption;
  final Widget? outgoingCaption;
  final Widget? time;
  final Widget? fileCaptions;
  final Rect? timePill;
  final double? captionMaxWidth;
  final double mediaInset;
  final EdgeInsets textPadding;
  final bool hasCaption;
  final bool above;
  final int leg;
  final double progress;

  @override
  Iterable<_Part> get slots => _Part.values;

  @override
  Widget? childForSlot(_Part slot) => switch (slot) {
    _Part.media => media,
    _Part.fileCaptions => fileCaptions,
    _Part.header => header,
    _Part.caption => caption,
    _Part.outgoingCaption => outgoingCaption,
    _Part.time => time,
  };

  @override
  _RenderMediaBubble createRenderObject(BuildContext context) =>
      _RenderMediaBubble()..update(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMediaBubble renderObject,
  ) => renderObject.update(this);
}

class _RenderMediaBubble extends RenderBox
    with SlottedContainerRenderObjectMixin<_Part, RenderBox> {
  Rect? _timePill;
  double? _captionMaxWidth;
  double _mediaInset = 0;
  EdgeInsets _textPadding = EdgeInsets.zero;
  bool _hasCaption = false;
  bool _above = false;
  int _leg = 0;
  double _progress = 1;

  /// The leg the text state [_from] belongs to.
  int? _fromLeg;

  /// The text state the running leg started from.
  MediaBubbleText? _from;

  /// The text state last laid out.
  MediaBubbleText? _shown;

  /// Where the time pill was put, in the bubble's coordinates; null when
  /// the time does not sit on the media.
  Rect? _timeRect;

  void update(_MediaBubble widget) {
    _timePill = widget.timePill;
    _captionMaxWidth = widget.captionMaxWidth;
    _mediaInset = widget.mediaInset;
    _textPadding = widget.textPadding;
    _hasCaption = widget.hasCaption;
    _above = widget.above;
    _leg = widget.leg;
    _progress = widget.progress;
    // Every input moves with the clock: lay out again each frame.
    markNeedsLayout();
  }

  RenderBox? _child(_Part part) => childForSlot(part);

  @override
  void performLayout() {
    final padding = _textPadding;
    final media = _child(_Part.media);
    media?.layout(const BoxConstraints(), parentUsesSize: true);
    final mediaSize = media?.size ?? Size.zero;
    final mediaRow = mediaSize.isEmpty
        ? 0.0
        : mediaSize.width + 2 * _mediaInset;

    final captionRow = switch (_captionMaxWidth) {
      final width? => math.max(width, mediaRow),
      null when constraints.hasBoundedWidth => constraints.maxWidth,
      null => mediaRow,
    };
    final captionConstraints = BoxConstraints(
      maxWidth: math.max(0, captionRow - padding.horizontal),
    );
    final caption = _child(_Part.caption);
    caption?.layout(captionConstraints, parentUsesSize: true);
    final outgoing = _child(_Part.outgoingCaption);
    outgoing?.layout(captionConstraints, parentUsesSize: true);

    final target = MediaBubbleText(
      caption: caption?.size ?? outgoing?.size ?? Size.zero,
      presence: _hasCaption ? 1 : 0,
      above: _above ? 1 : 0,
    );
    if (_fromLeg != _leg) {
      // A leg begins where the last frame was, mid-flight or at rest.
      _from = _shown ?? target;
      _fromLeg = _leg;
    }
    final shown = switch (_from) {
      final from? when _progress < 1 => MediaBubbleText.lerp(
        from,
        target,
        _progress,
      ),
      _ => target,
    };
    _shown = shown;

    final headerWidth = mediaSize.isEmpty ? captionRow : mediaRow;
    final header = _child(_Part.header);
    header?.layout(
      BoxConstraints(maxWidth: math.max(0, headerWidth - padding.horizontal)),
      parentUsesSize: true,
    );

    final geometry = MediaBubbleGeometry.compute(
      media: mediaSize,
      mediaInset: _mediaInset,
      textPadding: padding,
      text: shown,
      header: header?.size,
    );
    _place(media, geometry.media.topLeft);
    _place(caption, geometry.caption.topLeft);
    _place(outgoing, geometry.caption.topLeft);
    if (geometry.header case final rect?) _place(header, rect.topLeft);

    // Each file's caption sits in its row's slot, in the media's frame.
    final fileCaptions = _child(_Part.fileCaptions);
    fileCaptions?.layout(BoxConstraints.tight(mediaSize));
    _place(fileCaptions, geometry.media.topLeft);

    final time = _child(_Part.time);
    _timeRect = switch (_timePill) {
      final pill? when time != null => pill.shift(geometry.media.topLeft),
      _ => null,
    };
    if (time != null) {
      switch (_timeRect) {
        case final rect?:
          time.layout(BoxConstraints.tight(rect.size));
          _place(time, rect.topLeft);
        case null:
          time.layout(BoxConstraints.tight(Size.zero));
      }
    }
    size = constraints.constrain(geometry.size);
  }

  static void _place(RenderBox? child, Offset offset) {
    if (child == null) return;
    (child.parentData! as BoxParentData).offset = offset;
  }

  /// The children in paint order (hit-test order reversed).
  Iterable<RenderBox> get _paintOrder sync* {
    if (_child(_Part.media) case final child?) yield child;
    if (_child(_Part.fileCaptions) case final child?) yield child;
    if (_child(_Part.header) case final child?) yield child;
    if (_child(_Part.outgoingCaption) case final child?) yield child;
    if (_child(_Part.caption) case final child?) yield child;
    if (_timeRect != null) {
      if (_child(_Part.time) case final child?) yield child;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _paintOrder) {
      final data = child.parentData! as BoxParentData;
      context.paintChild(child, offset + data.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _paintOrder.toList().reversed) {
      final data = child.parentData! as BoxParentData;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason:
            'The bubble lays its media out from a transition frame and its '
            'caption from its measured size.',
      ),
      'No dry layout.',
    );
    return Size.zero;
  }
}
