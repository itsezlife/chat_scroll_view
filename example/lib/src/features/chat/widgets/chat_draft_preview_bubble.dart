import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_draft_options.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_outgoing_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:content_model/content_model.dart'
    show
        ChatCorrelation,
        LinkPreviewState$Loaded,
        LinkPreviewState$None,
        LinkPreviewState$Pending,
        MessageLinkPreview;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/widgets.dart';

/// The draft options' live preview: the draft drawn as the chat draws a
/// message it sent, by the chat's own bubble ([DemoMessageBubble]) over the
/// chat's [bodies], so the card follows the chat's media policy and an
/// option change moves on its media transition.
///
/// - **The message.** The draft's text is detected and encoded as a send
///   would (`ChatBodyMarkdown.send`), so its links are links; its link
///   preview fields are the preview's options with the page once loaded. A
///   pending page draws no card.
/// - **Not selectable.** Presses do not reach the bubble: neither the text
///   nor the card can be selected or tapped through.
/// - **Link taps.** A tap is read against the bubble's text; a link hit
///   goes to `DraftOptionsPreview.onLinkTap` with its outline moved into
///   the bubble's coordinates ([deliverLinkTap]). The overlay decides
///   whether it chooses the link.
/// - **Wallpaper.** Where the chat's wallpaper is scoped, it is drawn under
///   the bubble on Android and the desktops ([showsWallpaper]); iOS shows
///   the bubble alone.
class ChatDraftPreviewBubble extends StatefulWidget {
  /// The bubble of [preview], from [sender] (an outgoing sender of the
  /// demo).
  const ChatDraftPreviewBubble({
    required this.preview,
    required this.bodies,
    this.sender = 'Hixie',
    this.chatId,
    bool? showsWallpaper,
    super.key,
  }) : _showsWallpaper = showsWallpaper;

  /// The draft as the overlay shows it now.
  final DraftOptionsPreview preview;

  /// The chat's message bodies and media.
  final ChatBodyHost bodies;

  /// Who the draft is drawn as sent by.
  final String sender;

  /// The chat the events name.
  final String? chatId;

  final bool? _showsWallpaper;

  /// Whether the wallpaper is drawn under the bubble: Android and the
  /// desktops unless given.
  bool get showsWallpaper =>
      _showsWallpaper ??
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS => false,
        _ => true,
      };

  /// The id the draft's message is registered under with the preview's own
  /// selection controller.
  static const int messageId = 1;

  /// Hands a link hit of [url] to [preview]'s link tap, its [contour] (in
  /// the text body's coordinates) moved by [shift] into the bubble's. A hit
  /// without a contour is still handed on, with an empty one, and reported
  /// as the `onLinkTap` hook missing its outline.
  static void deliverLinkTap(
    DraftOptionsPreview preview, {
    required String url,
    required Path? contour,
    required Offset shift,
    ChatCorrelation Function()? correlation,
  }) {
    if (contour == null) {
      ChatDraftOptionsDiagnostics.wiringMissing(
        ChatDraftOptionsHook.onLinkTap,
        correlation,
      );
    }
    preview.onLinkTap(url, contour?.shift(shift) ?? Path());
  }

  @override
  State<ChatDraftPreviewBubble> createState() => _ChatDraftPreviewBubbleState();
}

class _ChatDraftPreviewBubbleState extends State<ChatDraftPreviewBubble> {
  // The preview's own: its text registers here, away from the chat's
  // selection, so a press in the overlay touches nothing of the chat's.
  // Under the desktop policy every registered body keeps its surface while
  // nothing is selected, so its links answer a hit query; no gesture ever
  // reaches it to select.
  late final ChatSelectionController _selection = ChatSelectionController(
    chatId: widget.chatId,
    policy: const ChatSelectionPolicy.desktop(),
  );

  // Fixed for the open, so the time in the bubble does not tick.
  final DateTime _sentAt = DateTime.now();

  // Whether a mouse points at a link of the text: the preview's link cursor
  // shows there.
  var _overLink = false;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  UserChatMessage _message() {
    final preview = widget.preview;
    final linkPreview = switch (preview.page) {
      LinkPreviewState$Loaded(:final page) => MessageLinkPreview(
        options: preview.part.options,
        page: page,
      ),
      LinkPreviewState$Pending() || LinkPreviewState$None() => null,
    };
    final outgoing = ChatOutgoingMessage(
      body: ChatBodyMarkdown.send(preview.text),
      linkPreview: linkPreview,
      invertMedia: preview.part.invertMedia,
    );
    return UserChatMessage(
      id: ChatDraftPreviewBubble.messageId,
      sender: widget.sender,
      createdAt: _sentAt,
      updatedAt: _sentAt,
      content: outgoing.body,
      payload: outgoing.toJson()..remove('body'),
    );
  }

  void _onHover(PointerHoverEvent event) {
    final hit = _selection.resolveInlineHit(
      ChatDraftPreviewBubble.messageId,
      event.position,
    );
    final overLink = switch (hit) {
      ChatInlineHit$Link() => true,
      _ => false,
    };
    if (overLink != _overLink) setState(() => _overLink = overLink);
  }

  void _onTapUp(TapUpDetails details) {
    final hit = _selection.resolveInlineHit(
      ChatDraftPreviewBubble.messageId,
      details.globalPosition,
    );
    if (hit case ChatInlineHit$Link(:final url, :final contourPath)) {
      final box = context.findRenderObject();
      final origin = box is RenderBox
          ? box.localToGlobal(Offset.zero)
          : Offset.zero;
      // The contour is in the text body's coordinates; the touch origin is
      // the tap in the same, so the body stands at the tap less it.
      final body = switch (hit.touchOrigin) {
        final local? => details.globalPosition - local,
        null => origin,
      };
      ChatDraftPreviewBubble.deliverLinkTap(
        widget.preview,
        url: url,
        contour: contourPath,
        shift: body - origin,
        correlation: () => ChatCorrelation(chatId: widget.chatId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bubble = MouseRegion(
      cursor: _overLink ? widget.preview.linkCursor : MouseCursor.defer,
      onHover: _onHover,
      onExit: (_) {
        if (_overLink) setState(() => _overLink = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: DemoMessageBubble(
              message: _message(),
              selection: _selection,
              host: widget.bodies,
              // The media would answer the text's link hits too.
              registersMedia: false,
            ),
          ),
        ),
      ),
    );
    final wallpaper = ChatWallpaperTheme.maybeOf(context);
    return switch (wallpaper) {
      final wallpaper? when widget.showsWallpaper => Stack(
        children: [
          Positioned.fill(
            child: ChatWallpaperView(
              wallpaper: wallpaper,
              motion: ChatWallpaperMotionScope.maybeOf(context),
            ),
          ),
          bubble,
        ],
      ),
      _ => bubble,
    };
  }
}
