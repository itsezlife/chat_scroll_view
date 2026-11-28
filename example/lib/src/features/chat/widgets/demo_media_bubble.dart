import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_received_link_preview.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_media_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart' show RichTextMarkdown;
import 'package:flutter/material.dart';
import 'package:message_media/message_media.dart';

/// The bubble of a message with media or a link preview: its items laid out
/// by the chat's message media policy, its caption (the message's text
/// body), its header and its time, composed by `MessageMediaBubbleLayout`.
///
/// The link preview comes from the message's payload through
/// [ChatReceivedLinkPreview.read]: a page the sender attached is drawn as it
/// came, a field without a page is looked up through the chat's resolver
/// ([ChatMediaHost.lookUp]) and drawn once it loads.
///
/// The host measures the caption (its plain text in the bubble's style), so
/// a policy that widens media to its caption gets the width
/// (`MediaLayoutInput.captionWidth`).
class DemoMediaBubble extends StatefulWidget {
  /// The bubble of the message [messageId].
  const DemoMediaBubble({
    required this.messageId,
    required this.items,
    required this.payload,
    required this.body,
    required this.host,
    required this.createdAt,
    required this.isOutgoing,
    required this.color,
    required this.metaColor,
    required this.textStyle,
    required this.borderRadius,
    required this.textPadding,
    this.edited = false,
    this.caption,
    this.header,
    this.selection,
    super.key,
  });

  /// The message's id.
  final int messageId;

  /// The message's media items.
  final List<MediaItem> items;

  /// The message's wire fields beside its body (its link preview,
  /// `invertMedia`).
  final Map<String, Object?> payload;

  /// The message's markdown body: the caption's text, and the links a link
  /// preview is looked up from.
  final String body;

  /// The chat's media seams.
  final ChatMediaHost host;

  /// When the message was sent.
  final DateTime createdAt;

  /// Whether the message was edited.
  final bool edited;

  /// Whether the message is the user's.
  final bool isOutgoing;

  /// The bubble's fill.
  final Color color;

  /// The time's colour beside text.
  final Color metaColor;

  /// The caption's text style, which the caption is measured in.
  final TextStyle textStyle;

  /// The bubble's corners.
  final BorderRadius borderRadius;

  /// The space around the caption and the header.
  final EdgeInsets textPadding;

  /// The caption: the message's registered text body; null without text.
  final Widget? caption;

  /// The sender's name above the media; null without one.
  final Widget? header;

  /// The chat's selection facade: the media registers as the message's
  /// non-text body with it.
  final ChatSelectionController? selection;

  @override
  State<DemoMediaBubble> createState() => _DemoMediaBubbleState();
}

class _DemoMediaBubbleState extends State<DemoMediaBubble> {
  ChatReceivedLinkPreview _received = ChatReceivedLinkPreview.none;
  LinkPreviewRequest? _lookup;
  MediaLayoutInput? _input;
  MediaLayout? _layout;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(DemoMediaBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload ||
        oldWidget.body != widget.body ||
        oldWidget.messageId != widget.messageId ||
        !identical(oldWidget.host, widget.host)) {
      _lookup?.removeListener(_onLookup);
      _lookup = null;
      _read();
    }
  }

  @override
  void dispose() {
    // The host owns the lookup: a bubble scrolled away leaves it running.
    _lookup?.removeListener(_onLookup);
    super.dispose();
  }

  void _read() {
    _received = ChatReceivedLinkPreview.read(
      widget.payload,
      body: RichTextMarkdown.decode(widget.body),
      resolveWithoutField: DemoConfig.resolveHistoryLinkPreviews,
      scrollId: '${widget.messageId}',
    );
    if (_received case ChatReceivedLinkPreview$Resolve(:final candidates)) {
      _lookup = widget.host.lookUp(widget.messageId, candidates)
        ..addListener(_onLookup);
    }
  }

  void _onLookup() {
    if (mounted) setState(() {});
  }

  // The page the card shows and the sender's options, or null for no card.
  MediaLinkPreviewInput? _cardOf(TextDirection direction) {
    final (page, options) = switch (_received) {
      ChatReceivedLinkPreview$Show(
        preview: MessageLinkPreview(:final page?, :final options),
      ) =>
        (page, options),
      ChatReceivedLinkPreview$Resolve(:final options) =>
        switch (_lookup?.value) {
          LinkPreviewState$Loaded(:final page) => (page, options),
          _ => (null, null),
        },
      _ => (null, null),
    };
    return switch (page) {
      final page? => MediaLinkPreviewInput(
        page: page,
        messageId: '${widget.messageId}',
        options: options,
        textDirection: direction,
      ),
      null => null,
    };
  }

  // The caption's laid-out width in the bubble's style, wrapped at
  // [maxWidth], with its padding.
  double? _captionWidthOf(double maxWidth) {
    if (widget.caption == null) return null;
    final text = RichTextMarkdown.decode(widget.body).plain;
    if (text.isEmpty) return null;
    final painter = TextPainter(
      text: TextSpan(text: text, style: widget.textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth - widget.textPadding.horizontal);
    final width = painter.width + widget.textPadding.horizontal;
    painter.dispose();
    return width;
  }

  // The layout of [input], laid out again only when the input changes.
  MediaLayout _layoutOf(MediaLayoutInput input) {
    if (_layout case final layout? when input == _input) return layout;
    _input = input;
    return _layout = widget.host.policy.layout(input);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final direction = Directionality.of(context);
      final screen = MediaQuery.sizeOf(context);
      final maxWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : screen.width;
      final invertMedia = LinkPreviewWire.readInvertMedia(widget.payload);
      final composition = MediaBubbleComposition(
        invertMedia: invertMedia,
        hasCaption: widget.caption != null,
        hasHeader: widget.header != null,
      );
      final correlation = ChatCorrelation(
        chatId: widget.host.chatId,
        scrollId: '${widget.messageId}',
      );
      final input = composition.inputFor(
        MediaLayoutInput(
          text: MediaLayoutText.of(context),
          items: widget.items,
          availableWidth: screen.width,
          displaySize: screen,
          maxContentWidth: maxWidth,
          captionWidth: _captionWidthOf(maxWidth),
          linkPreview: _cardOf(direction),
          isOutgoing: widget.isOutgoing,
          showsAvatar: !widget.isOutgoing,
          chrome: MediaLayoutChrome(
            timeWidth: widget.isOutgoing ? 48 : 32,
            timeHeight: 13,
            bubbleRadius: widget.borderRadius.topLeft.x,
          ),
          correlation: correlation,
        ),
      );
      final layout = _layoutOf(input);
      final meta = DemoMessageMeta(
        createdAt: widget.createdAt,
        color: widget.metaColor,
        showStatus: widget.isOutgoing,
        edited: widget.edited,
      );
      final placement = MediaBubbleTime.of(layout, input);
      final caption = switch ((widget.caption, placement)) {
        (final caption?, MediaBubbleTime.inText) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            caption,
            Align(alignment: AlignmentDirectional.centerEnd, child: meta),
          ],
        ),
        (final caption, _) => caption,
      };
      final content = MessageMediaBubbleLayout(
        layout: layout,
        items: widget.items,
        policy: widget.host.policy,
        composition: composition,
        caption: caption,
        captionRevision: widget.body,
        header: widget.header,
        time: switch (placement) {
          MediaBubbleTime.overMedia => _TimePill(
            createdAt: widget.createdAt,
            outgoing: widget.isOutgoing,
            edited: widget.edited,
          ),
          MediaBubbleTime.underCard => Align(
            alignment: AlignmentDirectional.bottomEnd,
            child: meta,
          ),
          MediaBubbleTime.inLastFileRow || MediaBubbleTime.inText => null,
        },
        textPadding: widget.textPadding,
        downloadContext: widget.host.downloadContext,
        correlation: correlation,
        selection: widget.selection,
        messageId: widget.messageId,
        onOpenViewer: switch (widget.host.onOpenViewer) {
          final open? => (request) => open(context, request, widget.items),
          null => null,
        },
        onItemMenu: switch (widget.host.onItemMenu) {
          final menu? => (part, rect) => menu(
            context,
            widget.messageId,
            part,
            rect,
          ),
          null => null,
        },
        onLinkPreview: switch (widget.host.onLinkPreview) {
          final open? => (part, page) => open(widget.messageId, part, page),
          null => null,
        },
        linkPreviewColors: LinkPreviewCardColors(
          accent: widget.isOutgoing
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF64B5F6),
          text: widget.textStyle.color,
          outgoing: widget.isOutgoing,
        ),
      );
      final bubble = DecoratedBox(
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: widget.borderRadius,
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: switch (placement) {
          // The last file row keeps room for the time at its end.
          MediaBubbleTime.inLastFileRow => Stack(
            children: [
              content,
              PositionedDirectional(end: 10, bottom: 8, child: meta),
            ],
          ),
          _ => content,
        },
      );
      return switch (widget.selection) {
        final controller? => ChatMessageSurfaceBounds(
          controller: controller,
          messageId: widget.messageId,
          shape: RoundedRectangleBorder(borderRadius: widget.borderRadius),
          child: bubble,
        ),
        null => bubble,
      };
    },
  );
}

/// The time over the media: the meta on a dark pill, laid out in the rect
/// the layout reports.
class _TimePill extends StatelessWidget {
  const _TimePill({
    required this.createdAt,
    required this.outgoing,
    required this.edited,
  });

  final DateTime createdAt;
  final bool outgoing;
  final bool edited;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x80000000),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Center(
      // The time is status chrome: a click on it is no tap of the row.
      child: ChatMessageTapBarrier(
        child: DemoMessageMeta(
          createdAt: createdAt,
          color: const Color(0xFFFFFFFF),
          showStatus: outgoing,
          edited: edited,
        ),
      ),
    ),
  );
}
