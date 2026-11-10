import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';

/// What the message menu needs to offer a message's emoji packs: which packs
/// a message's custom emoji come from ([of], each pack once, in order), and
/// where a pack's title is looked up ([source]).
///
/// The menu offers "This message contains emoji from N packs" below its
/// actions when [of] names any, and hands the packs to
/// `MessageMenuActions.onEmojiPacks`.
@immutable
final class MessageEmojiPacks {
  /// Answers [of] for a message id, and titles from [source].
  const MessageEmojiPacks({required this.of, required this.source});

  /// The packs of the custom emoji of the message with the given id.
  final List<PackId> Function(int messageId) of;

  /// Where the title of a lone pack is looked up.
  final PackSource source;
}

/// The menu's "contains emoji" entry: a block of its own under the action
/// card.
///
/// One pack is named by its title once its source has it (looked up when
/// the entry shows; a placeholder holds its place meanwhile), several by
/// their count. The name or count is bold in the accent colour; 13 px text,
/// padding 13 by 8. The entry leaves out the pack's cover emoji before a lone
/// title.
class MessageContainsEmojiButton extends StatefulWidget {
  /// The entry for [packs] (at least one), titled from [source].
  const MessageContainsEmojiButton({
    required this.packs,
    required this.source,
    required this.onTap,
    this.surfaceBuilder,
    super.key,
  });

  /// The packs the message's custom emoji come from.
  final List<PackId> packs;

  /// Where a lone pack's title is looked up.
  final PackSource source;

  /// Opens the packs.
  final VoidCallback onTap;

  /// The surface of the entry's card, or null for the package card.
  final ChatMessageMenuSurfaceBuilder? surfaceBuilder;

  /// The words before the name or count.
  static const String lead = 'This message contains emoji from ';

  @override
  State<MessageContainsEmojiButton> createState() =>
      _MessageContainsEmojiButtonState();
}

class _MessageContainsEmojiButtonState
    extends State<MessageContainsEmojiButton> {
  PackId? get _lone => switch (widget.packs) {
    [final only] => only,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    if (_lone case final id?) {
      widget.source.changes.addListener(_changed);
      // Peek first: a pack held already is named in the first frame.
      if (widget.source.peek(id) case PackLookup$Found()) return;
      widget.source.lookup(id).ignore();
    }
  }

  @override
  void dispose() {
    if (_lone != null) widget.source.changes.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = TextStyle(fontSize: 13, color: colors.onSurface);
    final accent = TextStyle(
      fontWeight: FontWeight.w600,
      color: colors.primary,
    );
    final InlineSpan named = switch (_lone) {
      final id? => switch (widget.source.peek(id)) {
        PackLookup$Found(:final pack) => TextSpan(
          children: [
            TextSpan(text: pack.title, style: accent),
            const TextSpan(text: ' pack.'),
          ],
        ),
        // A loading bar where the title will be.
        _ => TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                width: 64,
                height: 12,
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
            const TextSpan(text: ' pack.'),
          ],
        ),
      },
      null => TextSpan(
        children: [
          TextSpan(text: '${widget.packs.length} Packs', style: accent),
          const TextSpan(text: '.'),
        ],
      ),
    };
    return ChatMessageMenuCard(
      surfaceBuilder: widget.surfaceBuilder,
      // Its own ink layer: a host surface is not a Material.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  const TextSpan(text: MessageContainsEmojiButton.lead),
                  named,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
