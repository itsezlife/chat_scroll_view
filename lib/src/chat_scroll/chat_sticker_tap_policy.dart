import 'dart:ui' show Offset, Rect;

import 'package:chat_scroll_view/src/chat_scroll/chat_selection_interaction.dart'
    show ChatInlineGesture;
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_policy.dart';

/// **Sticker tap policy**: where a tap on the sticker of an emoji-only body
/// counts, and which gestures play the animation again.
///
/// A pure strategy of the `$Mobile` / `$Desktop` shape, like
/// [ChatSelectionPolicy]; [ChatStickerTapPolicy.of] follows a selection policy.
/// The reference clients agree on the table below, so the two strategies
/// differ only in the long press.
///
/// | Gesture | Mobile | Desktop |
/// | --- | --- | --- |
/// | tap on the drawn sticker | replays (if not already playing) | replays (same) |
/// | tap beside it, inside the message cell | nothing: an ordinary message tap | same |
/// | tap outside | not this message's | same |
/// | long press | replays (the menu opens over a sticker that restarts) | none exists |
///
/// A tap on a sticker that is still playing its pass does not restart it; the
/// binding refuses (`AssetBinding.replay` returns false). Whether the tap also
/// starts an interaction effect is the host's: `ChatStickerActivated` is
/// emitted for every tap on a hit, playing or not.
///
/// ## Replay tap slop
///
/// [replayTapSlop] outsets the hit rectangle, in logical pixels. The reference
/// clients use none (a tap must land on the drawn sticker, 0 on every side),
/// so that is the default. It is a parameter so a host that wants a tap near
/// the sticker to count can say so by changing one value; the hit it widens is
/// the one `ChatInlineHit.sticker` reports, so a tap in the slop is also an
/// interaction, not only a replay.
sealed class ChatStickerTapPolicy {
  /// Base constructor for policy variants.
  const ChatStickerTapPolicy({this.replayTapSlop = 0})
    : assert(replayTapSlop >= 0, 'The replay tap slop cannot be negative.');

  /// Mobile: a long press also replays.
  ///
  /// [replaysOnLongPress] false follows the reference client that does not
  /// restart the sticker when its menu opens.
  const factory ChatStickerTapPolicy.mobile({
    double replayTapSlop,
    bool replaysOnLongPress,
  }) = ChatStickerTapPolicy$Mobile;

  /// Desktop: a click replays; there is no long press.
  const factory ChatStickerTapPolicy.desktop({double replayTapSlop}) =
      ChatStickerTapPolicy$Desktop;

  /// The strategy that goes with [selection]: mobile with mobile, desktop
  /// with desktop.
  factory ChatStickerTapPolicy.of(
    ChatSelectionPolicy selection, {
    double replayTapSlop = 0,
  }) => switch (selection) {
    ChatSelectionPolicy$Mobile() => ChatStickerTapPolicy.mobile(
      replayTapSlop: replayTapSlop,
    ),
    ChatSelectionPolicy$Desktop() => ChatStickerTapPolicy.desktop(
      replayTapSlop: replayTapSlop,
    ),
  };

  /// Logical pixels the hit rectangle is outset by on every side.
  final double replayTapSlop;

  /// Whether [point] counts as on the sticker drawn in [sticker].
  bool hits(Rect sticker, Offset point) =>
      sticker.inflate(replayTapSlop).contains(point);

  /// Whether [gesture], on a hit, plays the animation again.
  bool replaysOn(ChatInlineGesture gesture);
}

/// The mobile strategy; see [ChatStickerTapPolicy].
final class ChatStickerTapPolicy$Mobile extends ChatStickerTapPolicy {
  /// Creates the mobile strategy.
  const ChatStickerTapPolicy$Mobile({
    super.replayTapSlop,
    this.replaysOnLongPress = true,
  });

  /// Whether a long press restarts the sticker.
  final bool replaysOnLongPress;

  @override
  bool replaysOn(ChatInlineGesture gesture) => switch (gesture) {
    ChatInlineGesture.tap => true,
    ChatInlineGesture.longPress => replaysOnLongPress,
  };
}

/// The desktop strategy; see [ChatStickerTapPolicy].
final class ChatStickerTapPolicy$Desktop extends ChatStickerTapPolicy {
  /// Creates the desktop strategy.
  const ChatStickerTapPolicy$Desktop({super.replayTapSlop});

  @override
  bool replaysOn(ChatInlineGesture gesture) => switch (gesture) {
    ChatInlineGesture.tap => true,
    ChatInlineGesture.longPress => false,
  };
}
