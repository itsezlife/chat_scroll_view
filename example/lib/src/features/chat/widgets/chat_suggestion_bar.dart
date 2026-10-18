import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_directory.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// Receives what a picked suggestion puts in place of the query's token.
typedef ChatSuggestionPick =
    void Function(ComposerInputQuery query, RichText replacement);

/// The demo's panel for the `@` and `#` queries: a row of chips in the
/// composer's header strip.
abstract final class ChatSuggestions {
  /// The header for [query], or null when no panel is due: no query, a kind
  /// this host did not register, or nothing that matches.
  ///
  /// The panel is transient, so it takes the strip over a link preview or an
  /// edit while the token is open; they come back when it closes.
  static ComposerHeader? header(
    ComposerInputQuery? query, {
    required ChatSuggestionPick onPick,
  }) {
    if (query == null) return null;
    final chips = switch (query.kind.id) {
      ChatDirectory.usernameQuery => [
        for (final user in ChatDirectory.matchUsers(query.text))
          (label: user.mentionText, replacement: ChatDirectory.mention(user)),
      ],
      ChatDirectory.hashtagQuery => [
        for (final tag in ChatDirectory.matchTags(query.text))
          (label: '#$tag', replacement: ChatDirectory.hashtag(tag)),
      ],
      _ => const <({String label, RichText replacement})>[],
    };
    if (chips.isEmpty) return null;
    return ComposerHeader.suggestion(
      builder: (context) => _ChipRow(
        chips: [
          for (final chip in chips)
            _Chip(
              label: chip.label,
              onTap: () => onPick(query, chip.replacement),
            ),
        ],
      ),
    );
  }
}

class _Chip {
  const _Chip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips});

  final List<_Chip> chips;

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.composerOf(context);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: chips.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final chip = chips[index];
        // A tap that is not a focus change: the field keeps its caret, and
        // the keyboard stays up under the pick.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: chip.onTap,
          child: Center(
            child: Text(
              chip.label,
              maxLines: 1,
              style: TextStyle(
                color: tokens.replyName,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}
