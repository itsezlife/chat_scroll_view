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

/// The copy path a `copyRefused` event names.
enum ChatCopyPath {
  /// The text selection's Copy (menu, toolbar or key).
  textSelection,

  /// A copy of the message-selection members.
  messageSelection,

  /// A tap or hold on an inline code span.
  inlineCode,

  /// A fenced code block's copy chrome.
  codeBlock,
}
