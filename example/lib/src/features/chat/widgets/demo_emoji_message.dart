import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_header_panel.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_meta_pill.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_reactions_row.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_service_colors.dart';
import 'package:content_model/content_model.dart' show EmojiOnly;
import 'package:flutter/material.dart';

/// What desktop recolours the glyphs of a selected emoji-only message with
/// (`msgStickerOverlay`; the palette value is not in the sources at hand, so
/// this is the selection colour of the demo's bubbles).
const Color _kSelectedOverlay = Color(0xFF2B5278);

/// How strongly the overlay tints at full selection.
const double _kSelectedOverlayAlpha = 0.45;

/// An emoji-only message: the viewport's [ChatEmojiBody] without a bubble,
/// with the chrome the platform's family puts around it.
///
/// The three families differ almost completely (`ChatEmojiPolicy`,
/// [EmojiChrome]): where the pill sits and what shape it is, whether the time
/// is always shown, where a reply goes (above the text and beside the sticker,
/// beside both, or beside when it fits), the ticks' glyphs, the reactions row,
/// what a right-to-left chat mirrors and how selection shows.
///
/// The widget asks the body for its geometry, reserves the strip the platform
/// wants under it, then places the pill, header and reactions by pure geometry
/// ([EmojiChrome.layout]) in one box.
///
/// The host decides what the viewport does not: how the sticker plays
/// (`ChatBodyHost.playbackFor`) and what the open chat already played
/// (`ChatBodyHost.plays`, the body's ledger), and whether the row is shown to
/// the user (the ticker mode of the subtree: a covered route turns it off).
class DemoEmojiMessage extends StatefulWidget {
  /// Shows [emojiOnly] as the body of message [messageId].
  const DemoEmojiMessage({
    required this.messageId,
    required this.emojiOnly,
    required this.selection,
    required this.host,
    required this.createdAt,
    required this.isOutgoing,
    this.edited = false,
    this.header,
    this.reactions = const <EmojiReaction>[],
    this.views,
    this.sendState,
    this.isLastOwn = false,
    this.policy,
    this.wallpaper,
    super.key,
  });

  /// The message this is the body of.
  final int messageId;

  /// The emoji of the message (`UserChatMessage.emojiOnly`).
  final EmojiOnly emojiOnly;

  /// The selection facade the body registers with.
  final ChatSelectionController selection;

  /// The chat screen's seams to the asset cache and its sticker decisions.
  final ChatBodyHost host;

  /// Send time, for the pill.
  final DateTime createdAt;

  /// Whether the message is the user's: it aligns to the end edge and its pill
  /// carries the delivery state.
  final bool isOutgoing;

  /// Whether the time says the message was edited (`edited 09:05`, one string).
  final bool edited;

  /// A reply or forward header, or null.
  final EmojiHeaderData? header;

  /// The reactions under the message, in order.
  final List<EmojiReaction> reactions;

  /// The views of a channel post, or null.
  final int? views;

  /// The delivery state of an outgoing message; read when null. Ignored for an
  /// incoming message.
  final EmojiSendState? sendState;

  /// Whether this is the user's last message: desktop shows its time then.
  final bool isLastOwn;

  /// The platform family's emoji policy; the running platform's when null.
  final ChatEmojiPolicy? policy;

  /// The average colour of the chat's wallpaper, which the service colour of
  /// the pill and the headers derives from; null takes
  /// [EmojiServiceColors.defaultWallpaper]. The demo has no wallpaper.
  final Color? wallpaper;

  @override
  State<DemoEmojiMessage> createState() => _DemoEmojiMessageState();
}

class _DemoEmojiMessageState extends State<DemoEmojiMessage> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy ?? ChatEmojiPolicy.forPlatform();
    final chrome = EmojiChrome.of(policy);
    final colors = EmojiServiceColors.of(policy, wallpaper: widget.wallpaper);
    final sticker = widget.host.stickerOf(widget.emojiOnly);
    final direction = Directionality.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final selected =
        ChatSelectionStateScope.maybeOf(context)?.selectProgress ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : viewport.width;
        final outgoing = widget.isOutgoing;
        final state = outgoing
            ? (widget.sendState ?? EmojiSendState.read)
            : EmojiSendState.none;

        ChatEmojiGeometry geometry(double reserve, {required bool hasHeader}) =>
            ChatEmojiBody.geometryFor(
              emojiOnly: widget.emojiOnly,
              policy: policy,
              sticker: sticker,
              viewport: viewport,
              maxWidth: rowWidth,
              direction: direction,
              hasHeader: hasHeader,
              bottomReserve: reserve,
            );

        final kind = ChatEmojiBody.layoutKindFor(
          widget.emojiOnly,
          sticker: sticker,
        );
        final isSticker = kind == ChatEmojiLayoutKind.sticker;
        // A header narrows the wrap of the text layout by the policy's rule.
        final hasHeader = widget.header != null && !isSticker;
        final bare = geometry(0, hasHeader: hasHeader);

        final time = emojiMetaTime(widget.createdAt, edited: widget.edited);
        final metrics = measureEmojiMeta(
          chrome: chrome,
          time: time,
          views: widget.views,
          direction: direction,
        );
        final pill = chrome.pill(
          metrics: metrics,
          outgoing: outgoing,
          kind: kind,
          state: state,
        );
        final reserve = chrome.bottomReserve(
          kind: kind,
          outgoing: outgoing,
          contentHeight: bare.content.height,
          pill: pill.size,
        );
        final body = geometry(reserve, hasHeader: hasHeader);

        final headerData = widget.header;
        final headerMeasure = headerData == null
            ? null
            : EmojiHeaderMeasure.of(
                headerData,
                chrome,
                // A line may take what the row leaves, less the panel's own
                // padding.
                maxLine:
                    (isSticker
                            ? rowWidth - body.size.width - 24
                            : rowWidth - 24)
                        .clamp(40, double.infinity),
                direction: direction,
              );
        final reactionsSize = widget.reactions.isEmpty
            ? null
            : EmojiReactionsRow.measure(widget.reactions, direction);

        var layout = chrome.layout(
          EmojiChromeInput(
            body: body,
            outgoing: outgoing,
            rowWidth: rowWidth,
            pill: pill,
            headerShape: headerMeasure?.data.shape,
            header: headerMeasure?.size,
            reactions: reactionsSize,
          ),
        );
        if (chrome.mirrorsInRtl && direction == TextDirection.rtl) {
          layout = layout.mirrored(rowWidth);
        }
        final bounds = layout.bounds;
        Rect inBox(Rect rect) => rect.shift(-bounds.topLeft);

        final showsMeta = chrome.showsMeta(
          outgoing: outgoing,
          kind: kind,
          emojiOnly: widget.emojiOnly,
          hovered: _hovered,
          isLastOwn: widget.isLastOwn,
          state: state,
        );

        Widget emojiBody = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: rowWidth),
          child: ChatEmojiBody(
            controller: widget.selection,
            messageId: widget.messageId,
            emojiOnly: widget.emojiOnly,
            embedFactory: widget.host.embedFactory,
            sticker: sticker,
            playback: isSticker
                ? widget.host.playbackFor(widget.emojiOnly.items.single.key)
                : null,
            playLedger: widget.host.plays,
            isActive: TickerMode.valuesOf(context).enabled,
            hasHeader: hasHeader,
            policy: policy,
            bottomReserve: reserve,
          ),
        );
        if (chrome.selection == EmojiSelectionStyle.glyphRecolour &&
            selected > 0) {
          emojiBody = ColorFiltered(
            colorFilter: ColorFilter.mode(
              _kSelectedOverlay.withValues(
                alpha: _kSelectedOverlayAlpha * selected,
              ),
              BlendMode.srcATop,
            ),
            child: emojiBody,
          );
        }

        final bodyRect = inBox(layout.body);
        final pillRect = layout.pill == null ? null : inBox(layout.pill!);
        final headerRect = layout.header == null ? null : inBox(layout.header!);
        final reactionsRect = layout.reactions == null
            ? null
            : inBox(layout.reactions!);

        return ChatMessageSurfaceBounds(
          controller: widget.selection,
          messageId: widget.messageId,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: SizedBox.fromSize(
              size: bounds.size,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  if (headerRect != null && headerMeasure != null)
                    Positioned.fromRect(
                      rect: headerRect,
                      child: EmojiHeaderPanel(
                        chrome: chrome,
                        colors: colors,
                        measure: headerMeasure,
                      ),
                    ),
                  Positioned(
                    left: bodyRect.left,
                    top: bodyRect.top,
                    child: emojiBody,
                  ),
                  if (pillRect != null && showsMeta)
                    Positioned.fromRect(
                      rect: pillRect,
                      child: EmojiMetaPill(
                        chrome: chrome,
                        layout: pill,
                        colors: colors,
                        time: time,
                        views: widget.views,
                      ),
                    ),
                  if (reactionsRect != null)
                    Positioned.fromRect(
                      rect: reactionsRect,
                      child: EmojiReactionsRow(
                        chrome: chrome,
                        colors: colors,
                        reactions: widget.reactions,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
