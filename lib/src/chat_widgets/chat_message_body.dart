import 'package:chat_scroll_view/src/chat_widgets/render_chat_message_body.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

export 'package:chat_scroll_view/src/chat_widgets/render_chat_message_body.dart'
    show RenderChatMessageBody;

/// Named slots occupied by [ChatMessageBody] children.
///
/// Slot identity is stable across rebuilds; do not reorder or rename values.
enum ChatMessageBodySlot {
  /// Optional band above content that contributes to outer width (sender name,
  /// forward label, and similar in-bubble chrome).
  header,

  /// Body (typically [Text] / [RichText], or any shrink-wrapping subtree).
  content,

  /// Trailing meta (time, delivery ticks, edited label) — host-owned widgets.
  meta,
}

/// Shrink-wrapping in-bubble layout: optional header, body, trailing meta.
///
/// ## Contract
///
/// - **Inline**: when the last text line plus [spacing] plus [meta] width fits
///   in the padded max width, [meta] sits on that line (bottom-trailing) and
///   the outer height stays equal to [header] + [content] height.
/// - **Wrap**: otherwise [meta] drops to the next row under [content]; height
///   grows by [meta]'s height (no extra vertical gap).
/// - **Shrink-wrap**: under loose constraints (`minWidth == 0`), width is the
///   minimum that fits [header] and the packed content/meta cluster — not the
///   incoming `maxWidth`. A wider [header] trails [meta] at the body's end.
/// - **Wrap vs inline** uses the padded max width from constraints, not
///   [header] width (Telegram `maxWidth` vs `lastLineWidth + timeMore`).
///
/// Slots are real children ([SlottedMultiChildRenderObjectWidget]). The body
/// is not painted with an internal [TextPainter], so selection, semantics,
/// and hit-testing work on the host widgets.
///
/// ## Last-line measurement
///
/// After laying out [content], the last [RenderParagraph] under that subtree
/// supplies the trailing edge of its last line (glyph boxes). If no paragraph
/// exists, [content]'s width is used (conservative — may prefer wrap).
///
/// Dry layout uses that same width proxy (no line metrics), which may
/// overestimate wrap height — safe for scroll size estimates.
///
/// ## Composition
///
/// Reply previews, media, and attachment overlays are **outside** this widget.
/// Stack them above in the host bubble; keep [ChatMessageBody] for the optional
/// name/forward band + text + meta cluster.
///
/// ```dart
/// ChatMessageBody(
///   spacing: 4,
///   header: Text(senderName),
///   content: Text(message.text),
///   meta: Row(
///     mainAxisSize: MainAxisSize.min,
///     children: [Text(timeLabel), statusIcon],
///   ),
/// )
/// ```
///
/// See also:
///
///  * [DatedMessage], day separator stacked above a message body.
///  * [ChatMessageThemeData], column / bubble width caps for the host.
class ChatMessageBody
    extends
        SlottedMultiChildRenderObjectWidget<ChatMessageBodySlot, RenderBox> {
  /// Creates a content + meta body layout.
  ///
  /// [meta] is required. Omit [content] (or pass null) for meta-only sizing
  /// (e.g. a compact time chip without body text). Optional [header] widens
  /// the body when it exceeds the packed content/meta width.
  const ChatMessageBody({
    required this.meta,
    this.header,
    this.content,
    this.spacing = 4.0,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// Optional band above [content]. Null means no header contribution.
  final Widget? header;

  /// Body widget. Null means meta-only sizing.
  final Widget? content;

  /// Trailing meta (time / status). Prefer `mainAxisSize: min` rows.
  final Widget meta;

  /// Horizontal gap between the last text line and [meta] when packed inline.
  final double spacing;

  /// Insets around the header + content + meta cluster (resolved with
  /// [Directionality]).
  final EdgeInsetsGeometry padding;

  @override
  Iterable<ChatMessageBodySlot> get slots => ChatMessageBodySlot.values;

  @override
  Widget? childForSlot(ChatMessageBodySlot slot) => switch (slot) {
    ChatMessageBodySlot.header => header,
    ChatMessageBodySlot.content => content,
    ChatMessageBodySlot.meta => meta,
  };

  @override
  SlottedContainerRenderObjectMixin<ChatMessageBodySlot, RenderBox>
  createRenderObject(BuildContext context) => RenderChatMessageBody(
    spacing: spacing,
    padding: padding,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderChatMessageBody renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..padding = padding
      ..textDirection = Directionality.of(context);
  }
}
