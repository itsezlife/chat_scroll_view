/// Strings of the composer: field hint, action labels and the reply / edit
/// header.
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
}
