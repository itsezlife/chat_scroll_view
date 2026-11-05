import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart' show InlineEmbedResolver;
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Lays out the bodies of the messages just past the screen, in the
/// direction the list travels, between frames, so a row that scrolls in
/// paints text already laid out ([MarkdownPainterCache]).
///
/// A row's body was laid out in the frame the row was built in, the largest
/// part of what a row costs. Here it is laid out in the gaps between frames,
/// a slice at a time, each under [_slice] so the next frame is not delayed.
/// Rows already built are skipped by the cache; so are messages not loaded,
/// emoji-only ones, which draw no markdown body, and bodies too long to lay
/// out within one gap.
///
/// [child] is the list: the prepared width is read from this widget's box.
class BodyPrefill extends StatefulWidget {
  /// Prepares the bodies [controller] scrolls toward into [cache].
  const BodyPrefill({
    required this.cache,
    required this.controller,
    required this.dataSource,
    required this.selection,
    required this.child,
    this.embedResolver,
    super.key,
  });

  /// Where the prepared bodies go; the bodies take them from it.
  final MarkdownPainterCache cache;

  /// The list's controller: its visible range and travel.
  final ChatScrollController controller;

  /// Where the messages come from.
  final ChatDataSource dataSource;

  /// The selection the bodies register with.
  final ChatSelectionController selection;

  /// The bodies' inline embed resolver.
  final InlineEmbedResolver? embedResolver;

  /// The list.
  final Widget child;

  @override
  State<BodyPrefill> createState() => _BodyPrefillState();
}

class _BodyPrefillState extends State<BodyPrefill> {
  /// How many messages past the screen are kept prepared: the build zone
  /// and the lead of a fast fling.
  static const int _lookahead = 24;

  /// The most one slice spends: a frame at 120 Hz leaves this much slack
  /// after the work of a scrolling frame.
  static const Duration _slice = Duration(milliseconds: 2);

  /// The longest source a body may have to be prepared. Laying out takes up
  /// to a few microseconds a character on a phone, and one body is laid out
  /// whole: a longer one would overrun the gap between two frames and delay
  /// the next. It is laid out in the frame its row is built in instead.
  static const int _maxLength = 2000;

  /// +1 when the list last travelled toward older messages, -1 toward newer.
  int _travel = 1;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addScrollListener(_onScroll);
  }

  @override
  void didUpdateWidget(BodyPrefill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeScrollListener(_onScroll);
      widget.controller.addScrollListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeScrollListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ChatScrollEvent event) {
    if (event case ChatViewportScrolled(:final delta) when delta != 0) {
      // A positive delta reveals older messages, which have lower ids.
      _travel = delta > 0 ? 1 : -1;
      _schedule();
    }
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // Animation priority: an idle task would wait until the fling it is for
    // has stopped.
    SchedulerBinding.instance.scheduleTask(_prepare, Priority.animation);
  }

  void _prepare() {
    _scheduled = false;
    if (!mounted) return;
    final range = widget.controller.visibleRange.value;
    final box = context.findRenderObject();
    if (range == null || box is! RenderBox || !box.hasSize) return;

    final clock = Stopwatch()..start();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final embeds = ChatMarkdownBody.adaptedEmbedResolver(widget.embedResolver);
    final widths = <bool, double>{};
    final step = -_travel;
    var id = _travel > 0 ? range.firstId - 1 : range.lastId + 1;
    for (var i = 0; i < _lookahead; i++, id += step) {
      if (clock.elapsed > _slice) {
        _schedule();
        return;
      }
      final message = widget.dataSource.getMessage(id);
      if (message case UserChatMessage(
        :final markdownBody?,
        emojiOnly: null,
      ) when markdownBody.markdown.length <= _maxLength &&
          !widget.cache.holds(markdownBody)) {
        final outgoing = isDemoOutgoing(message.sender);
        widget.cache.prepare(
          markdownBody,
          theme: ChatMarkdownBody.resolvedTheme(
            context,
            controller: widget.selection,
            messageId: id,
            theme: demoBubbleMarkdownTheme(context, outgoing: outgoing),
          ),
          maxWidth: widths[outgoing] ??= _bodyWidth(
            box.size.width,
            outgoing: outgoing,
          ),
          embedResolver: embeds,
          devicePixelRatio: dpr,
        );
      }
    }
  }

  /// The width a bubble gives its body in a list [width] wide: the row
  /// frame's cap less the bubble's padding (`MessageRowFrame`,
  /// `ChatMessageChangeTransition`).
  double _bodyWidth(double width, {required bool outgoing}) {
    final theme = ChatScrollTheme.messageOf(context);
    final inner = math.max<double>(
      0,
      theme.columnWidth(width) - theme.padding.horizontal,
    );
    final gutter = outgoing ? 0.0 : theme.avatarSize + theme.avatarGap;
    final cap = math.min(
      theme.bubbleCap(width, hasAvatarGutter: !outgoing),
      math.max<double>(0, inner - gutter),
    );
    final padding = ChatBubbleMetrics.bubbleContentPadding(
      theme: theme,
    ).resolve(Directionality.of(context));
    return math.max<double>(0, cap - padding.horizontal);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
