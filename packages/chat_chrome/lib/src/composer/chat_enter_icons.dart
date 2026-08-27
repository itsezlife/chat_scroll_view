import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:morphnext/morphnext.dart';

/// Emoji-button face for emoji-button animated states.
enum ChatEnterEmojiIconState {
  /// Panel closed, default.
  smile,

  /// Panel open — tap returns to IME.
  keyboard,

  /// Panel closed, empty field, last page was stickers.
  sticker,

  /// Panel closed, empty field, last page was GIFs.
  gif,
}

/// Resolves the emoji-button face from panel / text / last-page state.
ChatEnterEmojiIconState resolveEmojiIconState({
  required bool panelOpen,
  required bool textEmpty,
  required KeyboardPanelTab? lastTab,
}) {
  if (panelOpen) return ChatEnterEmojiIconState.keyboard;
  if (textEmpty && lastTab == KeyboardPanelTab.stickers) {
    return ChatEnterEmojiIconState.sticker;
  }
  if (textEmpty && lastTab == KeyboardPanelTab.gifs) {
    return ChatEnterEmojiIconState.gif;
  }
  return ChatEnterEmojiIconState.smile;
}

/// Maps [ChatEnterEmojiIconState] to a Material icon.
IconData emojiIconFor(ChatEnterEmojiIconState state) => switch (state) {
  ChatEnterEmojiIconState.smile => Icons.emoji_emotions_outlined,
  ChatEnterEmojiIconState.keyboard => Icons.keyboard_alt_outlined,
  ChatEnterEmojiIconState.sticker => Icons.sticky_note_2_outlined,
  ChatEnterEmojiIconState.gif => Icons.gif_box_outlined,
};

/// 44×44 icon button used on the composer row.
///
/// When [morph] is true, [icon] changes morph via [AnimatedMorphIcon]
/// (interruptible spring). Static chrome (attach, send, mic) keeps a plain
/// [Icon].
class ChatEnterIconButton extends StatelessWidget {
  /// Creates a circular hit target with centered [icon].
  const ChatEnterIconButton({
    required this.icon,
    required this.onPressed,
    this.onPressedDown,
    this.onLongPress,
    this.color,
    this.size = 44,
    this.iconSize = 24,
    this.morph = false,
    super.key,
  });

  /// Material icon.
  final IconData icon;

  /// Icon tint; defaults to panel icons color.
  final Color? color;

  /// Outer frame (button frames are 44).
  final double size;

  /// Drawn glyph size (frame ≠ drawable).
  final double iconSize;

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Fires on pointer-down **before** focus/IME can react.
  ///
  /// Used by the emoji toggle to arm soft-input suppress before the
  /// composer [TextField] can win a keyboard token on the same gesture.
  final VoidCallback? onPressedDown;

  /// Optional long-press.
  final VoidCallback? onLongPress;

  /// Spring-morph glyph transitions ([AnimatedMorphIcon]).
  final bool morph;

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    final tint = color ?? colors.messagePanelIcons;
    return SizedBox(
      width: size,
      height: size,
      // InkWell with canRequestFocus:false — never steal or donate focus to
      // the composer field (ExcludeFocus on IconButton caused the opposite:
      // first tap focused the TextField and opened the soft keyboard).
      child: Material(
        type: MaterialType.transparency,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: onPressed == null
              ? null
              : (_) => onPressedDown?.call(),
          child: InkWell(
            canRequestFocus: false,
            customBorder: const CircleBorder(),
            onTap: onPressed,
            onLongPress: onLongPress,
            child: Center(
              child: morph
                  ? AnimatedMorphIcon(
                      icon: icon,
                      size: iconSize,
                      color: tint,
                      spring: MorphSprings.snappy,
                    )
                  : Icon(icon, size: iconSize, color: tint),
            ),
          ),
        ),
      ),
    );
  }
}

/// Send plane vs mic swap (empty-field mic).
class ChatEnterSendMicButton extends StatelessWidget {
  /// Creates the trailing action.
  const ChatEnterSendMicButton({
    required this.hasText,
    required this.onSend,
    this.onMic,
    this.sending = false,
    this.isEditing = false,
    super.key,
  });

  /// Non-empty trimmed field → send; empty → mic.
  final bool hasText;

  /// Send / confirm edit.
  final VoidCallback? onSend;

  /// Mic tap (optional; null disables).
  final VoidCallback? onMic;

  /// Disables send while in-flight.
  final bool sending;

  /// Edit mode uses check instead of send.
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    if (hasText || isEditing) {
      return ChatEnterIconButton(
        icon: isEditing ? Icons.check_rounded : Icons.send_rounded,
        color: colors.messagePanelSend,
        onPressed: sending ? null : onSend,
      );
    }
    return ChatEnterIconButton(icon: Icons.mic_none_rounded, onPressed: onMic);
  }
}
