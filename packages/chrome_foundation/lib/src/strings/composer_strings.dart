import 'package:chrome_foundation/src/strings/draft_options_strings.dart';

/// Strings of the composer: field hint, action labels, the reply / edit
/// header and the draft options overlay.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. The action labels double as the semantic labels of the
/// corresponding buttons.
final class ComposerStrings {
  /// Composer strings with every member given.
  const ComposerStrings({
    required this.messageHint,
    required this.sendAction,
    required this.confirmEditAction,
    required this.recordVoiceAction,
    required this.attachAction,
    required this.showPanelAction,
    required this.showKeyboardAction,
    required this.dismissHeaderAction,
    required this.pastePlainAction,
    required this.replyTo,
    required this.editingMessage,
    required this.unavailableAction,
    required this.slowModeStarted,
    required this.slowModeEnded,
    required this.draftOptions,
    this.slowModeCountdown = minutesSeconds,
  });

  /// Hint of the empty message field.
  final String messageHint;

  /// Label of the send button.
  final String sendAction;

  /// Label of the button that confirms an edit.
  final String confirmEditAction;

  /// Label of the voice-recording button shown while the field is empty.
  final String recordVoiceAction;

  /// Label of the attach button.
  final String attachAction;

  /// Label of the toggle that opens the panel.
  final String showPanelAction;

  /// Label of the toggle that returns from the panel to the keyboard.
  final String showKeyboardAction;

  /// Label of the control that dismisses the reply or edit header.
  final String dismissHeaderAction;

  /// Label of the selection menu item that pastes the clipboard's plain text,
  /// without its formatting.
  final String pastePlainAction;

  /// Header line naming who a reply goes to: `replyTo('Alice')`.
  final String Function(String name) replyTo;

  /// Header line shown while editing a message.
  final String editingMessage;

  /// Label of an action the chat does not allow, drawn dimmed but still
  /// focusable, from the action's own [label]:
  /// `unavailableAction('Record voice message')` reads "Record voice
  /// message, not available".
  final String Function(String label) unavailableAction;

  /// What assistive technology announces, politely, when slow mode's
  /// countdown starts, from the wait as [slowModeCountdown] formats it:
  /// `slowModeStarted('0:30')` reads "Slow mode: you can send again in
  /// 0:30".
  final String Function(String countdown) slowModeStarted;

  /// What assistive technology announces, politely, when slow mode's
  /// countdown ends and the user may send again.
  final String slowModeEnded;

  /// The draft options overlay's copy.
  final DraftOptionsStrings draftOptions;

  /// The wait slow mode's countdown shows, from the time [remaining]:
  /// [minutesSeconds] (`m:ss`) unless the host formats it otherwise.
  final String Function(Duration remaining) slowModeCountdown;

  /// [remaining] as `m:ss`, the seconds rounded up, so a countdown reads
  /// `0:01` until the wait is over: `minutesSeconds(Duration(seconds: 90))`
  /// is `1:30`. Minutes are not wrapped into hours.
  static String minutesSeconds(Duration remaining) {
    const second = Duration.millisecondsPerSecond;
    final ms = remaining.inMilliseconds;
    final seconds = ms <= 0 ? 0 : (ms + second - 1) ~/ second;
    final minutes = seconds ~/ Duration.secondsPerMinute;
    final rest = seconds % Duration.secondsPerMinute;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}
