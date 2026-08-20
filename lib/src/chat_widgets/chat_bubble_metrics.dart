import 'package:chat_scroll_view/src/chat_scroll/chat_sender_run_layout.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_message_theme.dart';
import 'package:flutter/painting.dart';

/// Pure bubble chrome metrics derived from [ChatMessageThemeData] and
/// [MessageRunLayout].
///
/// Hosts resolve corners and content insets here — do not walk neighbors in
/// [ChatMessageBuilder]. Pin flags map as:
///
/// - `pinTop` → `!run.isFirstInSenderRun` (same-run message above)
/// - `pinBottom` → `!run.isLastInSenderRun` (same-run message below)
///
/// Horizontal asymmetry for **corners** follows Telegram’s outer / inner
/// model via [BorderRadiusDirectional]. Content padding stays symmetric
/// (see [bubbleContentPadding]) until a real tail path exists.
abstract final class ChatBubbleMetrics {
  /// Clustered outer-corner radius for [theme].
  static double nearRadius(ChatMessageThemeData theme) => theme.nearRadius;

  /// Bubble [BorderRadiusDirectional] for [outgoing] placement in [run].
  ///
  /// Incoming shrinks `*Start` when pinned; outgoing shrinks `*End`. Round
  /// clustering only — no tail path geometry.
  static BorderRadiusDirectional bubbleBorderRadius({
    required ChatMessageThemeData theme,
    required bool outgoing,
    required MessageRunLayout run,
  }) {
    final large = Radius.circular(theme.bubbleRadius);
    final near = Radius.circular(theme.nearRadius);
    final pinTop = !run.isFirstInSenderRun;
    final pinBottom = !run.isLastInSenderRun;

    if (outgoing) {
      return BorderRadiusDirectional.only(
        topStart: large,
        bottomStart: large,
        topEnd: pinTop ? near : large,
        bottomEnd: pinBottom ? near : large,
      );
    }
    return BorderRadiusDirectional.only(
      topEnd: large,
      bottomEnd: large,
      topStart: pinTop ? near : large,
      bottomStart: pinBottom ? near : large,
    );
  }

  /// In-bubble content [EdgeInsetsDirectional] for text chrome.
  ///
  /// Uses [ChatMessageThemeData.bubblePadding] + [ChatMessageThemeData.extraTextX]
  /// on **both** horizontal sides. Telegram’s larger incoming `textX` (`17`
  /// vs `11`) compensates for the `TYPE_TEXT` **tail path** that sticks past
  /// the round rect — this package paints round corners only, so copying that
  /// +6 on the outer side over-pads incoming bubbles. Keep insets symmetric
  /// until a real tail geometry exists; [EdgeInsetsDirectional] still flips
  /// correctly under RTL.
  static EdgeInsetsDirectional bubbleContentPadding({
    required ChatMessageThemeData theme,
  }) {
    final base = theme.bubblePadding;
    final horizontal = base.start + theme.extraTextX;
    return EdgeInsetsDirectional.fromSTEB(
      horizontal,
      base.top,
      horizontal,
      base.bottom,
    );
  }

  /// Media content [BorderRadiusDirectional] inset from the bubble chrome.
  ///
  /// Same outer/inner pin mapping as [bubbleBorderRadius].
  static BorderRadiusDirectional mediaContentRadius({
    required ChatMessageThemeData theme,
    required bool outgoing,
    required MessageRunLayout run,
  }) {
    final large = Radius.circular(theme.mediaLargeRadius);
    final near = Radius.circular(theme.mediaNearRadius);
    final pinTop = !run.isFirstInSenderRun;
    final pinBottom = !run.isLastInSenderRun;

    if (outgoing) {
      return BorderRadiusDirectional.only(
        topStart: large,
        bottomStart: large,
        topEnd: pinTop ? near : large,
        bottomEnd: pinBottom ? near : large,
      );
    }
    return BorderRadiusDirectional.only(
      topEnd: large,
      bottomEnd: large,
      topStart: pinTop ? near : large,
      bottomStart: pinBottom ? near : large,
    );
  }
}
