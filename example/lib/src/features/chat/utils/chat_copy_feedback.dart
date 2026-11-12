import 'package:chat_scroll_view/chat_scroll_view.dart';

/// What was put on the clipboard, as far as confirming it goes.
enum ChatCopyKind {
  /// Selected messages, or one message from its menu.
  messages,

  /// A range of text selected inside a message.
  textSelection,

  /// A link's address, from the message menu or the link sheet.
  link,

  /// Code: a tap on a snippet or a block, or the menu's Copy code.
  code,
}

/// Whether a copy is confirmed with a toast, per platform family. The host
/// owns this (ADR 012: the viewport's facade only reports the copy); what a
/// copy leaves selected is the **selection policy**'s (`applyCopySuccess`).
///
/// Chosen by the selection policy ([ChatCopyFeedback.forPolicy]), the way
/// `ChatMessagesCopyFormat` is. The same kind of copy confirms the same way
/// whichever trigger made it (shortcut, menu row, selection bar).
///
/// | Kind | `$Mobile` | `$Desktop` |
/// | --- | --- | --- |
/// | messages | toast | none |
/// | text selection | toast | none |
/// | link | toast | none |
/// | code | toast | toast |
///
/// * Mobile: the action-mode Copy of selected messages toasts and always ends
///   the selection; the menu's Copy of a message toasts; a copy of selected
///   text ends the text selection and the message selection, and toasts; a
///   link toasts; a tap on code toasts.
/// * iOS: selected text is copied silently and the selection is cancelled;
///   the toast above is the mobile rule's. iOS has no Copy for several
///   messages.
/// * Desktop: copies of messages, of selected text and of a link write the
///   clipboard, show nothing and keep the selection. Code is the exception: a
///   tap on code toasts.
///
/// Desktop's Copy code row of the message menu has no counterpart in this
/// table; it follows the tap on code.
sealed class ChatCopyFeedback {
  /// A feedback rule.
  const ChatCopyFeedback();

  /// The rule of [policy]: Android and iOS under `$Mobile`, the desktop
  /// rule under `$Desktop`.
  ///
  /// [systemConfirms] is for a mobile platform whose system already shows its
  /// own clipboard toast (Android 12L and later, see [androidSystemConfirms]);
  /// the app then adds none.
  factory ChatCopyFeedback.forPolicy(
    ChatSelectionPolicy policy, {
    bool systemConfirms = false,
  }) => switch (policy) {
    ChatSelectionPolicy$Mobile() || ChatSelectionPolicy$TextOnly() =>
      ChatCopyFeedback$Mobile(systemConfirms: systemConfirms),
    ChatSelectionPolicy$Desktop() => const ChatCopyFeedback$Desktop(),
  };

  /// Whether an Android system at [sdkInt] shows its own clipboard toast:
  /// the negation of `(sdkInt < 31 || !hasBuiltInClipboardToasts) && sdkInt < 32`,
  /// so Android 12L and later, and Android 12 on One UI 4.0.
  static bool androidSystemConfirms({
    required int sdkInt,
    required bool hasBuiltInClipboardToasts,
  }) => !((sdkInt < 31 || !hasBuiltInClipboardToasts) && sdkInt < 32);

  /// Whether copying [kind] shows a "copied" toast.
  bool showsToast(ChatCopyKind kind);

  /// Ends what [selection] holds after a copy the host wrote itself, as the
  /// facade does after its own: the selection policy decides (a mobile copy
  /// ends the message and the text selection, a desktop copy keeps both).
  /// Nothing happens without a [selection].
  static void endSelection(ChatSelectionController? selection) {
    selection?.selectionPolicy.applyCopySuccess(
      clearTextSelection: selection.clearTextSelection,
      clearMessageSelection: selection.clear,
    );
  }
}

/// The mobile rule: every copy is confirmed.
final class ChatCopyFeedback$Mobile extends ChatCopyFeedback {
  /// The mobile rule; [systemConfirms] when the system shows the toast.
  const ChatCopyFeedback$Mobile({this.systemConfirms = false});

  /// Whether the system confirms a clipboard write by itself.
  final bool systemConfirms;

  @override
  bool showsToast(ChatCopyKind kind) => !systemConfirms;
}

/// The desktop rule: a copy is silent, except code.
final class ChatCopyFeedback$Desktop extends ChatCopyFeedback {
  /// The desktop rule.
  const ChatCopyFeedback$Desktop();

  @override
  bool showsToast(ChatCopyKind kind) => switch (kind) {
    ChatCopyKind.code => true,
    ChatCopyKind.messages ||
    ChatCopyKind.textSelection ||
    ChatCopyKind.link => false,
  };
}
