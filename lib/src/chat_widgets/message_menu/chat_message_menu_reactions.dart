import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_actions.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_slots.dart';
import 'package:flutter/material.dart';

/// Horizontal padding inside the reactions pill.
const double kChatMessageMenuReactionsPad = 4;

/// Gap between emoji slots.
const double kChatMessageMenuReactionsGapSlots = 2;

/// Reactions strip height.
const double kChatMessageMenuReactionsHeight = 44;

/// Vertical padding inside the pill (`(height - slot) / 2`).
const double kChatMessageMenuReactionsPadVertical = 4;

/// Gap between the reactions pill and the action card.
const double kChatMessageMenuReactionsGap = 12;

/// How far the reactions pill can extend past the action card on the start.
const double kChatMessageMenuReactionsStartOverhang = 24;

/// How far the reactions pill can extend past the action card on the end.
const double kChatMessageMenuReactionsEndOverhang = 48;

/// Horizontal reactions strip above the action card.
class ChatMessageMenuReactions extends StatelessWidget {
  /// Creates a reactions strip.
  const ChatMessageMenuReactions({
    required this.reactions,
    required this.onReaction,
    this.maxWidth,
    this.reactionBuilder,
    super.key,
  });

  /// Emoji strings to show.
  final List<String> reactions;

  /// Called when an emoji is tapped.
  final ValueChanged<String> onReaction;

  /// Optional width cap. Defaults to [kChatMessageMenuMaxWidth].
  final double? maxWidth;

  /// Optional custom slot. Null uses the package emoji slot.
  final ChatMessageMenuReactionBuilder? reactionBuilder;

  /// Slot size.
  static const double slot = 36;

  /// Content width for [count] emoji slots including padding.
  static double contentWidthForCount(int count) {
    if (count <= 0) return 0;
    return count * slot +
        (count - 1) * kChatMessageMenuReactionsGapSlots +
        kChatMessageMenuReactionsPad * 2;
  }

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final menuTheme = ChatScrollTheme.menuOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.all(
      Radius.circular(
        menuTheme.reactionsRadius ?? kChatMessageMenuReactionsHeight / 2,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final cap = math.min(
          maxWidth ?? kChatMessageMenuMaxWidth,
          MediaQuery.widthOf(context) - 12,
        );
        final maxAvailable = constraints.maxWidth.isFinite
            ? math.min(constraints.maxWidth, cap)
            : cap;
        final contentWidth = contentWidthForCount(reactions.length);
        final width = math.min(contentWidth, maxAvailable);
        final fits = contentWidth <= maxAvailable;

        Widget slots;
        if (fits) {
          slots = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < reactions.length; i++) ...<Widget>[
                if (i > 0)
                  const SizedBox(width: kChatMessageMenuReactionsGapSlots),
                reactionBuilder?.call(
                      context,
                      reactions[i],
                      () => onReaction(reactions[i]),
                    ) ??
                    _ReactionSlot(
                      emoji: reactions[i],
                      onTap: () => onReaction(reactions[i]),
                    ),
              ],
            ],
          );
        } else {
          slots = ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: kChatMessageMenuReactionsPad,
              vertical: kChatMessageMenuReactionsPadVertical,
            ),
            itemCount: reactions.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: kChatMessageMenuReactionsGapSlots),
            itemBuilder: (context, index) =>
                reactionBuilder?.call(
                  context,
                  reactions[index],
                  () => onReaction(reactions[index]),
                ) ??
                _ReactionSlot(
                  emoji: reactions[index],
                  onTap: () => onReaction(reactions[index]),
                ),
          );
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.35),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            borderRadius: radius,
            color:
                menuTheme.reactionsColor ??
                Color.alphaBlend(
                  colorScheme.onSurface.withValues(alpha: 0.08),
                  colorScheme.surface,
                ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: kChatMessageMenuReactionsHeight,
              child: Padding(
                padding: !fits
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(
                        horizontal: kChatMessageMenuReactionsPad,
                        vertical: kChatMessageMenuReactionsPadVertical,
                      ),
                child: slots,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReactionSlot extends StatelessWidget {
  const _ReactionSlot({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    borderRadius: const BorderRadius.all(
      Radius.circular(ChatMessageMenuReactions.slot / 2),
    ),
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(
        Radius.circular(ChatMessageMenuReactions.slot / 2),
      ),
      child: SizedBox(
        width: ChatMessageMenuReactions.slot,
        height: ChatMessageMenuReactions.slot,
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
      ),
    ),
  );
}
