import 'package:chat_scroll_view/src/chat_scroll/chat_inline_hit.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_interaction.dart';
import 'package:content_model/content_model.dart' show DiagnosticOp;

/// The operations of the diagnostics events the selection facade emits
/// through `ChatDiagnostics.current`, under the `capabilities` category.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum ChatSelectionOp implements DiagnosticOp {
  /// A copy refused because the host's `ChatSelectionController.canCopy`
  /// answered false (info): the copy `path` (`textSelection`,
  /// `messageSelection`, `inlineCode` or `codeBlock`), with the message's
  /// scroll id and the facade's chat id.
  copyRefused,
}

/// The copy path a `copyRefused` event names: the one source a refusal's
/// [ChatCopyOrigin] is read from ([origin]), so the two never disagree.
enum ChatCopyPath {
  /// The text selection's Copy (menu, toolbar or key).
  textSelection(ChatCopyOrigin.textSelection),

  /// A copy of the message-selection members.
  messageSelection(ChatCopyOrigin.messageSelection),

  /// A tap or hold on an inline code span.
  inlineCode(ChatCopyOrigin.codeTap),

  /// A fenced code block's copy chrome.
  codeBlock(ChatCopyOrigin.codeTap);

  const ChatCopyPath(this.origin);

  /// The path of a copy of code of [kind].
  static ChatCopyPath ofCode(ChatCodeKind kind) => switch (kind) {
    ChatCodeKind.inline => inlineCode,
    ChatCodeKind.block => codeBlock,
  };

  /// The origin a [ChatCopyRefused] of this path carries: the coarser
  /// grouping hosts switch on.
  final ChatCopyOrigin origin;
}
