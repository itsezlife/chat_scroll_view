import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_edit_body.dart';
import 'package:flutter/material.dart';
import 'package:message_media/message_media.dart';

/// Builds a demo message widget for the widget-based [ChatScrollView].
///
/// Returns a shimmer placeholder while [message] is `null` (chunk loading),
/// and a [DemoMessageBubble] once the message has been fetched.
///
/// The bubble uses [ChatMessageBody] for text + time/status packing — the same
/// host API apps should wire inside their own `messageBuilder`.
///
/// [groupedMessages] is the per-chat map for album geometry; omit or pass an
/// empty map when the host has no media groups.
///
/// For run-grouped rendering (avatar on the **last** message, sender name on
/// the **first**) use [MessageRunLayout] from the viewport — see
/// `widget_chat_screen.dart`.
Widget buildDemoMessage(
  BuildContext context,
  int id,
  IChatMessage? message,
  ChatMessageStatus status,
  MessageRunLayout runLayout, {
  GroupedMessagesMap? groupedMessages,
}) {
  if (message == null) return const DemoShimmerBubble();
  return DemoMessageBubble(
    message: message,
    runLayout: runLayout,
    groupedMessages: groupedMessages,
  );
}

ChatMessageThemeData _layoutOf(BuildContext context) =>
    ChatScrollTheme.messageOf(context);

/// Senders treated as "team members" — right-aligned, distinct bubble color.
/// In a real chat this would be "is the current user" — the team list just
/// gives the demo two visually-distinct columns to compare.
const Set<String> _teamMembers = {
  'Hixie',
  'justinmc',
  'jonahwilliams',
  'chunhtai',
  'tvolkert',
  'goderbauer',
  'zanderso',
  'liyuqian',
  'aam',
  'gspencergoog',
  'mit-mit',
  'xster',
  'AlexV525',
  'maheshj01',
  'darshankawar',
  'gaaclarke',
  'knopp',
  'mraleph',
  'jmagman',
  'danagbemava-nc',
  'huycozy',
  'slightfoot',
  'guidezpl',
  'pedromassango',
  'abarth',
  'gnprice',
  'cbracken',
  'exaby73',
  'loic-sharma',
  'nt4f04uNd',
  'jason-simmons',
  'ColdPaleLight',
};

bool _isOutgoing(String sender) => _teamMembers.contains(sender);

const List<Color> _senderColors = <Color>[
  Color(0xFF42A5F5),
  Color(0xFF66BB6A),
  Color(0xFFEF5350),
  Color(0xFFAB47BC),
  Color(0xFFFF7043),
  Color(0xFF26C6DA),
  Color(0xFFFFCA28),
  Color(0xFFEC407A),
  Color(0xFF8D6E63),
  Color(0xFF78909C),
];

Color _colorForSender(String sender) =>
    _senderColors[sender.hashCode.abs() % _senderColors.length];

// --- Palette --------------------------------------------------------------

const Color _kOutgoingBg = Color(0xFF0B81F6);
const Color _kIncomingBg = Color(0xFF2A2A2C);
const Color _kOutgoingText = Color(0xFFFFFFFF);
const Color _kIncomingText = Color(0xFFE6E7EB);
const Color _kShimmer = Color(0xFF2C2C2E);

const TextStyle _kCaptionStyle = TextStyle(
  color: Color(0xFFE8E8ED),
  fontSize: 14,
  height: 1.2,
);

// --- Bubble ---------------------------------------------------------------

/// A single chat bubble — optional sender label, body text, time, and (for
/// outgoing) a delivery status icon.
///
/// Body text and meta are packed with [ChatMessageBody] (last-line fit /
/// shrink-wrap). The sender label stays above that cluster so run chrome does
/// not participate in meta packing.
///
/// When [message] is a media [UserChatMessage], paints a media placeholder
/// (single or one group row from [groupedMessages]) instead of the text body.
///
/// [runLayout] drives chrome: **sender name on first** in the run, **avatar
/// on last** (incoming), column top inset on first, and bubble corner
/// clustering via [ChatBubbleMetrics].
class DemoMessageBubble extends StatelessWidget {
  /// Renders [message] as an incoming or outgoing bubble row.
  const DemoMessageBubble({
    required this.message,
    this.runLayout = const MessageRunLayout(
      isFirstInSenderRun: true,
      isLastInSenderRun: true,
    ),
    this.groupedMessages,
    super.key,
  });

  /// Message to display — drives sender alignment and bubble styling.
  final IChatMessage message;

  /// Sender-run position from the viewport — do not recompute from neighbors.
  final MessageRunLayout runLayout;

  /// Per-chat grouped messages map for album rows; `null` skips group lookup.
  final GroupedMessagesMap? groupedMessages;

  @override
  Widget build(BuildContext context) {
    final content = switch (message) {
      UserChatMessage(:final content) => content,
      SystemChatMessage(:final content) => content,
      _ => 'Message #${message.id}',
    };
    final outgoing = _isOutgoing(message.sender);
    final layout = _layoutOf(context);
    final isFirstInRun = runLayout.isFirstInSenderRun;
    final isLastInRun = runLayout.isLastInSenderRun;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final bubble = _Bubble(
          sender: isFirstInRun ? message.sender : null,
          content: content,
          createdAt: message.createdAt,
          edited: message.updatedAt != message.createdAt,
          isOutgoing: outgoing,
          runLayout: runLayout,
          theme: layout,
          maxWidth: layout.bubbleCap(viewportWidth, hasAvatarGutter: !outgoing),
          message: message,
          groupedMessages: groupedMessages,
        );
        final Widget row;
        if (outgoing) {
          row = Align(alignment: AlignmentDirectional.centerEnd, child: bubble);
        } else {
          row = Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (isLastInRun)
                _Avatar(sender: message.sender, size: layout.avatarSize)
              else
                SizedBox(width: layout.avatarSize),
              SizedBox(width: layout.avatarGap),
              Flexible(child: bubble),
            ],
          );
        }

        return Align(
          alignment: layout.columnAlignment(
            viewportWidth: viewportWidth,
            outgoing: outgoing,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: layout.columnWidth(viewportWidth),
            ),
            child: Padding(
              padding: layout.padding.copyWith(
                top: layout.topInset(isFirstInRun: isFirstInRun),
                bottom: layout.bottomInset(isLastInRun: isLastInRun),
              ),
              child: row,
            ),
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.sender, required this.size});

  final String sender;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = sender.isEmpty
        ? '?'
        : sender.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colorForSender(sender),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontWeight: FontWeight.w700,
          fontSize: 14,
          height: 1,
        ),
      ),
    );
  }
}

/// Colored bubble chrome around the message body.
///
/// Uses [ChatMessageBody] so short lines keep time/status on the same visual
/// row, long last lines wrap meta underneath, and the bubble width shrinks to
/// the text + meta cluster instead of always filling [maxWidth].
///
/// Media rows replace the text body with a media placeholder; meta packing
/// stays on text-only messages via [DemoMessageEditBody].
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.sender,
    required this.content,
    required this.createdAt,
    required this.edited,
    required this.isOutgoing,
    required this.runLayout,
    required this.theme,
    required this.maxWidth,
    required this.message,
    required this.groupedMessages,
  });

  /// `null` suppresses the sender label — non-first messages in a run.
  final String? sender;

  /// Plain message body shown in the content slot of [ChatMessageBody].
  final String content;

  /// Send timestamp; formatted by meta for the meta slot.
  final DateTime createdAt;

  /// When true, meta shows an “edited” label (demo: `updatedAt != createdAt`).
  final bool edited;

  /// When true, right-column colors and a delivery tick in meta.
  final bool isOutgoing;

  /// Run position — drives [ChatBubbleMetrics] corner clustering.
  final MessageRunLayout runLayout;

  /// Layout + bubble chrome tokens from [ChatScrollTheme.messageOf].
  final ChatMessageThemeData theme;

  /// Cap from [ChatMessageThemeData.bubbleCap]; not a forced width.
  final double maxWidth;

  /// Source message — media fields select placeholder vs text body.
  final IChatMessage message;

  /// Per-chat map for group-row geometry.
  final GroupedMessagesMap? groupedMessages;

  @override
  Widget build(BuildContext context) {
    final bg = isOutgoing ? _kOutgoingBg : _kIncomingBg;
    final textColor = isOutgoing ? _kOutgoingText : _kIncomingText;
    final metaColor = isOutgoing
        ? _kOutgoingText.withValues(alpha: 0.78)
        : _kIncomingText.withValues(alpha: 0.55);
    final radius = ChatBubbleMetrics.bubbleBorderRadius(
      theme: theme,
      outgoing: isOutgoing,
      run: runLayout,
    );
    final padding = ChatBubbleMetrics.bubbleContentPadding(theme: theme);

    final mediaBody = _buildMediaBody(bubbleRadius: theme.bubbleRadius);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (sender != null) ...<Widget>[
                Text(
                  sender!,
                  style: TextStyle(
                    color: _colorForSender(sender!),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              if (mediaBody case final media?)
                media
              else
                DemoMessageEditBody(
                  content: content,
                  createdAt: createdAt,
                  edited: edited,
                  showStatus: isOutgoing,
                  sizeAlignment: isOutgoing
                      ? AlignmentDirectional.topEnd
                      : AlignmentDirectional.topStart,
                  metaColor: metaColor,
                  textStyle: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Placeholder single or group row, or `null` for text-only messages.
  ///
  /// Album members (`groupId` set) never fall back to the single-media path:
  /// until the map has a mosaic (≥2 members), the row is empty.
  Widget? _buildMediaBody({required double bubbleRadius}) {
    if (message case UserChatMessage(
      :final id,
      :final aspectRatio?,
      :final groupId,
      :final caption,
      :final invertMedia,
    )) {
      if (groupId case final gid?) {
        final entry = groupedMessages?.group(gid);
        if (entry == null) {
          return const SizedBox.shrink();
        }
        return _GroupRowMedia(
          messageId: id,
          entry: entry,
          mosaicWidth: maxWidth,
          bubbleRadius: bubbleRadius,
        );
      }
      return _SingleMedia(
        aspectRatio: aspectRatio,
        maxWidth: maxWidth,
        bubbleRadius: bubbleRadius,
        caption: caption,
        captionAbove: invertMedia,
      );
    }
    return null;
  }
}

/// Single photo/video placeholder with optional plain caption.
class _SingleMedia extends StatelessWidget {
  const _SingleMedia({
    required this.aspectRatio,
    required this.maxWidth,
    required this.bubbleRadius,
    required this.caption,
    required this.captionAbove,
  });

  final double aspectRatio;
  final double maxWidth;
  final double bubbleRadius;
  final String? caption;
  final bool captionAbove;

  @override
  Widget build(BuildContext context) {
    final media = MessageMediaPlaceholder.single(
      aspectRatio: aspectRatio,
      maxWidth: maxWidth,
      bubbleRadius: bubbleRadius,
    );
    return switch (caption) {
      final text? when text.isNotEmpty => GroupRowCaption(
        caption: GroupCaptionSlot(
          text: text,
          above: captionAbove,
          height: _measureCaptionHeight(text, maxWidth),
        ),
        style: _kCaptionStyle,
        child: media,
      ),
      _ => media,
    };
  }
}

/// One album member as a group row (cell + optional caption on the owner).
class _GroupRowMedia extends StatelessWidget {
  const _GroupRowMedia({
    required this.messageId,
    required this.entry,
    required this.mosaicWidth,
    required this.bubbleRadius,
  });

  final int messageId;
  final GroupedMessagesEntry entry;
  final double mosaicWidth;
  final double bubbleRadius;

  @override
  Widget build(BuildContext context) {
    final index = entry.messageIds.indexOf(messageId);
    if (index < 0) {
      return const SizedBox.shrink();
    }

    final mosaic = MosaicLayout.project(
      positions: entry.messages.positions,
      mosaicWidth: mosaicWidth,
      bubbleRadius: bubbleRadius,
    );
    if (index >= mosaic.cells.length) {
      return const SizedBox.shrink();
    }

    final captionText = entry.captionText ?? '';
    final captionHeight = switch (entry.messages.captionIndex) {
      final i? when i == index && captionText.isNotEmpty =>
        _measureCaptionHeight(captionText, mosaicWidth),
      _ => 0.0,
    };

    final rows = GroupRowLayout.compute(
      mosaic: mosaic,
      messages: entry.messages,
      captionText: entry.captionText,
      captionHeight: captionHeight,
    );
    final row = rows[index];
    final cell = mosaic.cells[index];

    return SizedBox(
      width: mosaic.size.width,
      child: GroupRowCaption(
        caption: row.caption,
        style: _kCaptionStyle,
        child: SizedBox(
          width: mosaic.size.width,
          height: row.mediaHeight,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: cell.rect.left),
              child: MessageMediaPlaceholder.cell(cell: cell),
            ),
          ),
        ),
      ),
    );
  }
}

double _measureCaptionHeight(String text, double maxWidth) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _kCaptionStyle),
    textDirection: TextDirection.ltr,
    maxLines: 3,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

// --- Shimmer placeholder --------------------------------------------------

/// Placeholder shown for a message whose chunk is still loading. Mirrors the
/// real bubble layout — avatar circle + bubble silhouette — so the chat
/// doesn't jump when data lands.
class DemoShimmerBubble extends StatelessWidget {
  /// Placeholder silhouette matching [DemoMessageBubble] layout dimensions.
  const DemoShimmerBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = _layoutOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: layout.columnAlignment(
          viewportWidth: constraints.maxWidth,
          outgoing: false,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: layout.columnWidth(constraints.maxWidth),
          ),
          child: Padding(
            // Placeholders use a slightly roomier vertical rhythm than live
            // bubbles (`runGap: 2`) so stacked shimmers remain easy to scan
            // while loading.
            padding: layout.padding.copyWith(top: 6, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: _kShimmer,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: layout.avatarSize,
                    height: layout.avatarSize,
                  ),
                ),
                SizedBox(width: layout.avatarGap),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: _kShimmer,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: SizedBox(width: 240, height: 52),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Chunk-error tile -----------------------------------------------------

/// Failure tile shown in place of an entire chunk whose fetch errored. One
/// per chunk (not 64 per-message slots), tapping "Retry" cancels the
/// running backoff and re-fetches the chunk immediately.
class DemoChunkErrorTile extends StatelessWidget {
  /// One tile covering the id range `[firstId, lastId]` for a failed chunk.
  const DemoChunkErrorTile({
    required this.firstId,
    required this.lastId,
    required this.onRetry,
    this.attempt = 0,
    super.key,
  });

  /// First message id in the failed chunk (inclusive).
  final int firstId;

  /// Last message id in the failed chunk (inclusive).
  final int lastId;

  /// Failed fetch attempts since the last success — shown when greater than 1.
  final int attempt;

  /// Cancels backoff and immediately re-fetches the chunk.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final label = attempt > 1
        ? 'Failed to load messages $firstId–$lastId (attempt $attempt)'
        : 'Failed to load messages $firstId–$lastId';
    final layout = _layoutOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: layout.columnWidth(constraints.maxWidth),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              layout.padding.left,
              8,
              layout.padding.right,
              8,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF3A2A2A),
                border: Border.all(color: const Color(0xFF6B3A3A)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: Color(0xFFE57373),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFE6E7EB),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE57373),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Empty state ----------------------------------------------------------

/// Full-viewport empty state. Shown when the data source reports
/// [ChatDataSource.isEmpty] — the conversation has no messages.
class DemoEmptyState extends StatelessWidget {
  /// Centered copy shown when [ChatDataSource.isEmpty] is true.
  const DemoEmptyState({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.forum_outlined, size: 48, color: Color(0xFF6E7280)),
        SizedBox(height: 12),
        Text(
          'No messages yet',
          style: TextStyle(
            color: Color(0xFFE6E7EB),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Start the conversation below.',
          style: TextStyle(color: Color(0xFF8E94A2), fontSize: 13),
        ),
      ],
    ),
  );
}

// --- Initial loading skeleton --------------------------------------------

/// Full-viewport skeleton shown before the first chunk lands. A stack of
/// shimmer bubbles standing in for the message list, plus a small spinner —
/// fills the viewport so the user sees layout structure immediately instead
/// of waiting on a blank screen.
class DemoInitialSkeleton extends StatelessWidget {
  /// Shimmer stack shown while [ChatDataSource.isInitialLoading] is true.
  const DemoInitialSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: <Widget>[
      SizedBox(height: 24),
      DemoShimmerBubble(),
      DemoShimmerBubble(),
      DemoShimmerBubble(),
      DemoShimmerBubble(),
      SizedBox(height: 24),
      SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8E94A2)),
        ),
      ),
      SizedBox(height: 32),
    ],
  );
}
