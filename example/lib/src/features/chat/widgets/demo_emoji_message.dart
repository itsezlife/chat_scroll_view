import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:content_model/content_model.dart'
    show ContentKey$Unicode, EmojiOnly;
import 'package:flutter/material.dart';

/// The translucent dark pill behind the time of a message without a bubble
/// (Android: the chat time background at 0.6 alpha).
const Color _kServiceColor = Color(0x99000000);
const Color _kServiceText = Color(0xFFFFFFFF);
const Color _kSelectedTint = Color(0xFF2B5278);

/// An emoji-only message: the viewport's [ChatEmojiBody] without a bubble,
/// with the chrome the host places around it:
///
/// - the **time pill** over the body's bottom trailing corner, on the service
///   colour, with a corner radius of 4 for the text layout and 12 for a
///   sticker;
/// - the **header** (a reply or forward) **beside** a sticker and **above** the
///   enlarged text, on the side away from the screen edge the message is
///   aligned to; and the text then wraps narrower for it;
/// - reactions would go below, as a sibling under this widget; the demo has
///   none.
///
/// The widget decides what the viewport does not: whether a lone unicode
/// emoji plays now. That is asked once, when this mounts, of the screen's
/// memory (`ChatBodyHost.plays`), and kept for the life of the mount.
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

  /// Whether the message is the user's: it aligns to the end edge, its header
  /// goes to its start side, and its pill carries the delivery ticks.
  final bool isOutgoing;

  /// Whether the pill says the message was edited.
  final bool edited;

  /// A reply or forward header, or null.
  final Widget? header;

  @override
  State<DemoEmojiMessage> createState() => _DemoEmojiMessageState();
}

class _DemoEmojiMessageState extends State<DemoEmojiMessage> {
  /// Whether a lone unicode emoji plays on this mount.
  ///
  /// The memory is asked at mount and not on each build: a build while the
  /// sticker plays would see the claim spent and hold it. An edit-morph twin
  /// does not register with the viewport and does not claim.
  late final bool _autoplay;

  @override
  void initState() {
    super.initState();
    _autoplay =
        ChatMarkdownBodyRegistration.allows(context) &&
        widget.emojiOnly.items.length == 1 &&
        widget.emojiOnly.items.single.key is ContentKey$Unicode &&
        widget.host.plays.claimFirstPlay(widget.messageId);
  }

  @override
  Widget build(BuildContext context) {
    final sticker = widget.host.stickerOf(widget.emojiOnly);
    final kind = ChatEmojiBody.layoutKindFor(
      widget.emojiOnly,
      sticker: sticker,
    );
    final isSticker = kind == ChatEmojiLayoutKind.sticker;
    final header = widget.header;
    final body = _surface(
      context,
      isSticker: isSticker,
      child: ChatEmojiBody(
        controller: widget.selection,
        messageId: widget.messageId,
        emojiOnly: widget.emojiOnly,
        embedFactory: widget.host.embedFactory,
        sticker: sticker,
        autoplay: _autoplay,
        hasHeader: header != null && !isSticker,
      ),
    );

    return switch ((isSticker, header)) {
      (true, final header?) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.isOutgoing) Flexible(child: header),
          body,
          if (!widget.isOutgoing) Flexible(child: header),
        ],
      ),
      (false, final header?) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: widget.isOutgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          Padding(padding: const EdgeInsets.only(bottom: 4), child: header),
          body,
        ],
      ),
      _ => body,
    };
  }

  // The body, the selection tint behind it and the pill over its bottom
  // trailing corner; the viewport reads the box as the message's surface.
  Widget _surface(
    BuildContext context, {
    required bool isSticker,
    required Widget child,
  }) {
    final radius = isSticker ? 12.0 : 4.0;
    final inset = (isSticker ? const ChatEmojiSizes().stickerInset : 0) + 4.0;
    final selected =
        ChatSelectionStateScope.maybeOf(context)?.selectProgress ?? 0;
    return ChatMessageSurfaceBounds(
      controller: widget.selection,
      messageId: widget.messageId,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _kSelectedTint.withValues(alpha: 0.6 * selected),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: <Widget>[
            child,
            PositionedDirectional(
              end: inset,
              bottom: inset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _kServiceColor,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: DemoMessageMeta(
                    createdAt: widget.createdAt,
                    color: _kServiceText,
                    showStatus: widget.isOutgoing,
                    edited: widget.edited,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A reply header in the service pill style the message chrome of a bubble-less
/// message uses: the quoted sender and a line of what they said.
class DemoReplyHeader extends StatelessWidget {
  /// A header quoting [sender]'s [text].
  const DemoReplyHeader({required this.sender, required this.text, super.key});

  /// Who wrote the quoted message.
  final String sender;

  /// One line of the quoted message.
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _kServiceColor,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            sender,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kServiceText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kServiceText,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
  );
}
