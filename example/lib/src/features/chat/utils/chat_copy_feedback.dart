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

/// Whether a copy is confirmed with a toast, per platform family, after the
/// reference clients. The host owns this (ADR 012: the viewport's facade only
/// reports the copy); what a copy leaves selected is the **selection
/// policy**'s (`applyCopySuccess`).
///
/// Chosen by the selection policy ([ChatCopyFeedback.forPolicy]), the way
/// `ChatMessagesCopyFormat` is. The same kind of copy confirms the same way
/// whichever trigger made it (shortcut, menu row, selection bar): neither
/// reference client tells triggers apart.
///
/// | Kind | `$Mobile` | `$Desktop` |
/// | --- | --- | --- |
/// | messages | toast | none |
/// | text selection | toast | none |
/// | link | toast | none |
/// | code | toast | toast |
///
/// * Android (`ChatActivity.java`): the action-mode Copy of selected messages
///   toasts (`ACTION_TEXT_COPIED`, `:3722`) and always ends the selection
///   (`:3724`); the menu's Copy of a message toasts (`ACTION_MESSAGE_COPIED`,
///   `:33157`); a copy of selected text ends the text selection
///   (`TextSelectionHelper.java:1736`) and the message selection, and toasts
///   (`onTextCopied`, `:8654-8659`); a link toasts (`ACTION_LINK_COPIED`,
///   `:35973`, `:44215`); a tap on code toasts (`URLSpanMono`, `:36293`).
/// * iOS: the menu's Copy toasts (`ChatInterfaceStateContextMenus.swift:1352`);
///   selected text is copied silently and the selection is cancelled
///   (`ChatController.swift:4318`, `TextSelectionNode.swift:773-774`), so the
///   toast below is the Android client's. iOS has no Copy for several
///   messages.
/// * Desktop (`tdesktop/Telegram/SourceFiles`): `HistoryInner::copySelectedText`
///   (`history/history_inner_widget.cpp:3952`), `ListWidget::copySelectedText`
///   (`history/view/history_view_list_widget.cpp:3566`), `copyContextText`
///   (`history_inner_widget.cpp:4058`) and `AddCopyLinkAction`
///   (`history/view/history_view_context_menu.cpp:1427`) write the clipboard,
///   show nothing and keep the selection. Code is the exception:
///   `MonospaceClickHandler::onClick` (`core/click_handler_types.cpp:586`,
///   `lng_text_copied`) and `UiIntegration::copyPreOnClick`
///   (`core/ui_integration.cpp:452`, `lng_code_copied`).
///
/// Unverified: Desktop's Copy code row of the message menu has no reference
/// counterpart (its menu has no such row); it follows the tap on code.
sealed class ChatCopyFeedback {
  /// A feedback rule.
  const ChatCopyFeedback();

  /// The rule of [policy]: Android and iOS under `$Mobile`, the desktop
  /// client's under `$Desktop`.
  ///
  /// [systemConfirms] is for a mobile platform whose system already shows its
  /// own clipboard toast (Android 12L and later:
  /// `AndroidUtilities.shouldShowClipboardToast`, `AndroidUtilities.java:3598`,
  /// which `UndoView.showWithAction` consults); the app then adds none.
  factory ChatCopyFeedback.forPolicy(
    ChatSelectionPolicy policy, {
    bool systemConfirms = false,
  }) => switch (policy) {
    ChatSelectionPolicy$Mobile() => ChatCopyFeedback$Mobile(
      systemConfirms: systemConfirms,
    ),
    ChatSelectionPolicy$Desktop() => const ChatCopyFeedback$Desktop(),
  };

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

/// The Android client's rule, which the iOS client's matches wherever it has a
/// Copy: every copy is confirmed.
final class ChatCopyFeedback$Mobile extends ChatCopyFeedback {
  /// The mobile rule; [systemConfirms] when the system shows the toast.
  const ChatCopyFeedback$Mobile({this.systemConfirms = false});

  /// Whether the system confirms a clipboard write by itself.
  final bool systemConfirms;

  @override
  bool showsToast(ChatCopyKind kind) => !systemConfirms;
}

/// The desktop client's rule: a copy is silent, except code.
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
