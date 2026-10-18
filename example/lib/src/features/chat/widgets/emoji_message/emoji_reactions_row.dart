import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_meta_pill.dart'
    show measureEmojiLine;
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_service_colors.dart';
import 'package:flutter/widgets.dart';

/// One reaction under a message: an emoji and how many chose it.
@immutable
final class EmojiReaction {
  /// A reaction of [emoji], chosen by [count] people.
  const EmojiReaction(this.emoji, this.count, {this.chosen = false});

  /// The reaction's emoji.
  final String emoji;

  /// How many chose it.
  final int count;

  /// Whether the user is one of them.
  final bool chosen;
}

/// The row of reaction chips under an emoji-only message, on the service
/// colour: Android's chip is 26 dp high with a 4 dp gap (1.7); iOS's gap is 4 pt
/// (2.6); the chip's inner metrics are not in the sources at hand, so Android's
/// serve the three.
class EmojiReactionsRow extends StatelessWidget {
  /// Draws [reactions].
  const EmojiReactionsRow({
    required this.chrome,
    required this.colors,
    required this.reactions,
    super.key,
  });

  /// A chip's height (`ReactionsLayoutInBubble:361`).
  static const double chipHeight = 26;

  /// The gap between chips (`ReactionsLayoutInBubble:388`).
  static const double gap = 4;

  /// A chip's padding before the emoji and after the count.
  static const double unverifiedPadding = 8;

  /// The emoji's size in a chip.
  static const double unverifiedEmojiSize = 16;

  /// The gap between the emoji and the count.
  static const double unverifiedInnerGap = 4;

  /// The platform's chrome.
  final EmojiChrome chrome;

  /// The service colours.
  final EmojiServiceColors colors;

  /// The reactions, in order.
  final List<EmojiReaction> reactions;

  static TextStyle _style(Color color, {bool bold = false}) => TextStyle(
    color: color,
    fontSize: 13,
    height: 1.17,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    decoration: TextDecoration.none,
  );

  /// The row's size.
  static Size measure(List<EmojiReaction> reactions, TextDirection direction) {
    var width = 0.0;
    for (final reaction in reactions) {
      width += _chipWidth(reaction, direction);
    }
    width += gap * (reactions.length - 1);
    return Size(width, chipHeight);
  }

  // One extra logical pixel: a laid-out count can come out a fraction wider
  // than the ceiled measure of the same text.
  static double _chipWidth(EmojiReaction reaction, TextDirection direction) =>
      1 +
      unverifiedPadding * 2 +
      unverifiedEmojiSize +
      unverifiedInnerGap +
      measureEmojiLine(
        '${reaction.count}',
        _style(const Color(0xFFFFFFFF)),
        direction,
      ).width;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: <Widget>[
        for (var i = 0; i < reactions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: gap),
          SizedBox(
            width: _chipWidth(reactions[i], direction),
            height: chipHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: reactions[i].chosen
                    ? colors.text.withValues(alpha: 0.9)
                    : colors.panel,
                borderRadius: BorderRadius.circular(chipHeight / 2),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: unverifiedPadding,
                ),
                child: Row(
                  textDirection: TextDirection.ltr,
                  children: <Widget>[
                    SizedBox(
                      width: unverifiedEmojiSize,
                      child: Text(
                        reactions[i].emoji,
                        style: const TextStyle(
                          fontSize: unverifiedEmojiSize - 2,
                          height: 1,
                          decoration: TextDecoration.none,
                        ),
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                    const SizedBox(width: unverifiedInnerGap),
                    Text(
                      '${reactions[i].count}',
                      style: _style(
                        reactions[i].chosen
                            ? const Color(0xFF3E6D8F)
                            : colors.text,
                        bold: reactions[i].chosen,
                      ),
                      textScaler: TextScaler.noScaling,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
