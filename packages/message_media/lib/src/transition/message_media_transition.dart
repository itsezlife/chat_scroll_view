import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatSelectionController;
import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/chrome/media_options_affordance.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/gesture/media_viewer_request.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/message_media_hit_part.dart';
import 'package:message_media/src/paint/message_media_view.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:message_media/src/transition/media_layout_transition.dart';
import 'package:message_media/src/transition/media_transition_policy.dart';
import 'package:mpx_core/mpx_core.dart';

/// Builds what follows a media transition's frame: the bubble around
/// [media] and the caption, which cross-fades by the frame's progress.
typedef MessageMediaTransitionBuilder =
    Widget Function(
      BuildContext context,
      MediaTransitionFrame frame,
      Widget media,
    );

/// The clock of one message's media transitions: each new [layout] animates
/// from the frame on screen to it, under the [policy]'s
/// `MessageMediaPolicy.transition`.
///
/// One clock per message drives the cells, the media's size and, through
/// [builder], the bubble and the caption. The widget is the frame's size,
/// so the row it sits in reports an interpolated height each frame and the
/// viewport's anchor and follow-tail rules move the neighbours, as for an
/// edit morph; the viewport needs nothing else.
///
/// - **Revision.** A new [revision] starts a leg though the layout is the
///   same, for a change only the bubble shows (a caption edit).
/// - **Interrupt.** A [layout] that changes while a leg runs starts the
///   next leg from the frame reached, not from the old layout.
/// - **Items.** The cells that leave keep the item they draw until their
///   exit ends, though [items] no longer lists it.
/// - **Reduce motion.** With `MediaQuery.disableAnimations` (or tickers
///   muted) every change jumps to its end, as under a policy without
///   transitions (the desktop default).
/// - **First layout.** The first layout shows at rest: how a whole row
///   appears is the host's.
///
/// ## Diagnostics
///
/// Each change of [layout] reports `media` / `transitionStarted` (trace)
/// with the trigger, the entering and exiting counts, the duration in
/// milliseconds and whether reduce motion collapsed it; a change while a
/// leg runs first reports `transitionInterrupted` with the milliseconds it
/// had run. Both carry the [correlation]'s chat and scroll ids.
class MessageMediaTransition extends StatefulWidget {
  /// Animates [layout] of [items] under [policy].
  const MessageMediaTransition({
    required this.layout,
    required this.items,
    required this.policy,
    this.trigger,
    this.revision,
    this.builder,
    this.downloadContext,
    this.correlation = ChatCorrelation.none,
    this.chromeContext = MediaChromeContext.none,
    this.selectionProgress,
    this.selection,
    this.messageId,
    this.onOpenViewer,
    this.onItemMenu,
    super.key,
  });

  /// The layout to animate to (with its radii resolved,
  /// `MessageMediaPolicy.layout`).
  final MediaLayout layout;

  /// The items [layout] lays out.
  final List<MediaItem> items;

  /// The policy whose transition timings, cell builders and autoplay the
  /// media follows.
  final MessageMediaPolicy policy;

  /// What changed the layout, when the host knows it (a caption edit, the
  /// `invertMedia` toggle). Unset, the clock tells items from a re-layout
  /// of the same items and from a card change.
  final MediaTransitionTrigger? trigger;

  /// A change the media layout does not show (a caption edit that keeps
  /// the media's size): a new value starts a leg though [layout] is equal,
  /// so the bubble and the caption still move on the clock.
  final Object? revision;

  /// Builds the bubble around the media for each frame; unset, the media
  /// alone.
  final MessageMediaTransitionBuilder? builder;

  /// The class of conversation the media is shown in.
  final AutoDownloadContext? downloadContext;

  /// The chat and message the diagnostics events name.
  final ChatCorrelation correlation;

  /// What the message is drawn in, which the chrome slots weigh
  /// (`MessageMediaView.chromeContext`).
  final MediaChromeContext chromeContext;

  /// The selection checkbox's appearance, 0 to 1
  /// (`MessageMediaView.selectionProgress`).
  final Animation<double>? selectionProgress;

  /// See `MessageMediaView.selection`.
  final ChatSelectionController? selection;

  /// See `MessageMediaView.messageId`.
  final int? messageId;

  /// See `MessageMediaView.onOpenViewer`.
  final ValueChanged<MediaViewerRequest>? onOpenViewer;

  /// See `MessageMediaView.onItemMenu`.
  final void Function(MediaHitPart part, Rect rect)? onItemMenu;

  @override
  State<MessageMediaTransition> createState() => _MessageMediaTransitionState();
}

class _MessageMediaTransitionState extends State<MessageMediaTransition>
    with SingleTickerProviderStateMixin {
  // Made by the first change: most messages never change while shown.
  Ticker? _ticker;
  late MediaTransitionFrame _frame = MediaTransitionFrame.settled(
    widget.layout,
  );
  MediaLayoutTransition? _leg;
  Duration _elapsed = Duration.zero;

  /// The items of cells still fading out, which the host no longer lists.
  final Map<MediaItemId, MediaItem> _leaving = {};

  @override
  void didUpdateWidget(MessageMediaTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.layout == oldWidget.layout &&
        widget.revision == oldWidget.revision) {
      return;
    }
    final kept = {for (final item in widget.items) item.id};
    for (final item in oldWidget.items) {
      if (!kept.contains(item.id)) _leaving[item.id] = item;
    }
    _start(oldWidget.layout);
  }

  void _start(MediaLayout previous) {
    final trigger = widget.trigger ?? _triggerOf(previous, widget.layout);
    if (_leg != null) {
      _emit(MediaOp.transitionInterrupted, {
        'trigger': trigger,
        'elapsedMs': _elapsed.inMilliseconds,
      });
    }
    final transition = widget.policy.transition;
    final collapsed =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        !TickerMode.valuesOf(context).enabled;
    final leg = MediaLayoutTransition(
      from: _frame,
      to: widget.layout,
      policy: transition,
    );
    final runs = !collapsed && leg.duration > Duration.zero;
    _emit(MediaOp.transitionStarted, {
      'trigger': trigger,
      'entering': leg.entering.length,
      'exiting': leg.exiting.length,
      'durationMs': runs ? leg.duration.inMilliseconds : 0,
      'reduceMotion': collapsed && transition.animates,
    });
    _ticker?.stop();
    _elapsed = Duration.zero;
    if (!runs) {
      _settle();
      return;
    }
    _leg = leg;
    _frame = leg.frameAt(Duration.zero);
    (_ticker ??= createTicker(_tick)).start();
  }

  void _tick(Duration elapsed) {
    final leg = _leg;
    if (leg == null) return;
    _elapsed = elapsed;
    if (elapsed >= leg.duration) {
      _ticker?.stop();
      setState(_settle);
      return;
    }
    setState(() => _frame = leg.frameAt(elapsed));
  }

  void _settle() {
    _leg = null;
    _leaving.clear();
    _frame = MediaTransitionFrame.settled(widget.layout);
  }

  static MediaTransitionTrigger _triggerOf(MediaLayout a, MediaLayout b) {
    final before = {for (final cell in a.cells) cell.itemId};
    final after = {for (final cell in b.cells) cell.itemId};
    if (before.length != after.length || !before.containsAll(after)) {
      return MediaTransitionTrigger.items;
    }
    List<MediaBlock> cards(MediaLayout layout) => [
      for (final block in layout.blocks)
        if (block case MediaBlock$LinkPreview()) block,
    ];
    final cardsBefore = cards(a);
    final cardsAfter = cards(b);
    final cardChanged =
        cardsBefore.length != cardsAfter.length ||
        cardsBefore.indexed.any((e) => e.$2 != cardsAfter[e.$1]);
    return cardChanged
        ? MediaTransitionTrigger.card
        : MediaTransitionTrigger.descriptor;
  }

  void _emit(MediaOp op, Map<String, Object> fields) {
    ChatDiagnostics.current.emit(
      ChatEventLevel.trace,
      ChatEventCategory.media,
      op,
      correlation: ChatCorrelation(
        chatId: widget.correlation.chatId,
        scrollId: widget.correlation.scrollId,
        clientMessageId: widget.correlation.clientMessageId,
      ),
      fields: () => fields,
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final media = MessageMediaView(
      layout: frame.layout,
      items: [
        ...widget.items,
        for (final cell in frame.layout.exiting) ?_leaving[cell.itemId],
      ],
      policy: widget.policy,
      fades: frame.fades,
      downloadContext: widget.downloadContext,
      correlation: widget.correlation,
      chromeContext: widget.chromeContext,
      selectionProgress: widget.selectionProgress,
      selection: widget.selection,
      messageId: widget.messageId,
      onOpenViewer: widget.onOpenViewer,
      onItemMenu: widget.onItemMenu,
    );
    return switch (widget.builder) {
      final builder? => builder(context, frame, media),
      null => media,
    };
  }
}
