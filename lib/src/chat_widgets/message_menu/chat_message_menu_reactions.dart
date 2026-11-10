import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_actions.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_slots.dart';
import 'package:flutter/material.dart';

/// Horizontal reactions strip above the action card.
class ChatMessageMenuReactions extends StatelessWidget {
  /// Creates a reactions strip.
  const ChatMessageMenuReactions({
    required this.reactions,
    required this.onReaction,
    this.maxWidth,
    this.reactionBuilder,
    this.surfaceBuilder,
    super.key,
  });

  /// Emoji strings to show.
  final List<String> reactions;

  /// Called when an emoji is tapped.
  final ValueChanged<String> onReaction;

  /// Optional width cap. Defaults to [ChatMessageMenuCard.defaultMaxWidth].
  final double? maxWidth;

  /// Optional custom slot. Null uses the package emoji slot.
  final ChatMessageMenuReactionBuilder? reactionBuilder;

  /// The host's surface for the strip, or null for the package pill.
  final ChatMessageMenuSurfaceBuilder? surfaceBuilder;

  /// Slot size.
  static const double slot = 36;

  /// Horizontal padding inside the reactions pill.
  static const double pad = 4;

  /// Gap between emoji slots.
  static const double gapSlots = 2;

  /// Reactions strip height.
  static const double height = 44;

  /// Vertical padding inside the pill (`(height - slot) / 2`).
  static const double padVertical = 4;

  /// Gap between the reactions pill and the action card.
  static const double gap = 12;

  /// How far the reactions pill can extend past the action card on the start.
  static const double startOverhang = 24;

  /// How far the reactions pill can extend past the action card on the end.
  static const double endOverhang = 48;

  /// Content width for [count] emoji slots including padding.
  static double contentWidthForCount(int count) {
    if (count <= 0) return 0;
    return count * slot + (count - 1) * gapSlots + pad * 2;
  }

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final menuTheme = ChatScrollTheme.menuOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.all(
      Radius.circular(menuTheme.reactionsRadius ?? height / 2),
    );

    // Sized from the screen, not from the room it is given, so the strip
    // reports its width to a menu that shrink-wraps its rows.
    final maxAvailable = math.max<double>(
      0,
      math.min(
        maxWidth ?? ChatMessageMenuCard.defaultMaxWidth,
        MediaQuery.widthOf(context) - 12,
      ),
    );
    final contentWidth = contentWidthForCount(reactions.length);
    final width = math.min(contentWidth, maxAvailable);
    final fits = contentWidth <= maxAvailable;

    Widget slots;
    if (fits) {
      slots = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < reactions.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: gapSlots),
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
          horizontal: pad,
          vertical: padVertical,
        ),
        itemCount: reactions.length,
        separatorBuilder: (_, _) => const SizedBox(width: gapSlots),
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

    final content = SizedBox(
      width: width,
      height: ChatMessageMenuReactions.height,
      child: Padding(
        padding: !fits
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(
                horizontal: pad,
                vertical: padVertical,
              ),
        child: slots,
      ),
    );
    if (surfaceBuilder case final builder?) {
      return builder(
        context,
        radius.topLeft.x,
        Material(type: MaterialType.transparency, child: content),
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
        child: content,
      ),
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
