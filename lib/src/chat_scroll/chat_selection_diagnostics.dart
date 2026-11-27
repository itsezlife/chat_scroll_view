import 'package:chat_scroll_view/src/chat_scroll/chat_inline_hit.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_interaction.dart';
import 'package:content_model/content_model.dart'
    show
        ChatCorrelation,
        ChatDiagnostics,
        ChatEventCategory,
        ChatEventLevel,
        DiagnosticOp;

/// The operations of the diagnostics events the selection facade and the
/// viewport's selection pointer emit through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum ChatSelectionOp implements DiagnosticOp {
  /// A copy refused because the host's `ChatSelectionController.canCopy`
  /// answered false (info): the copy `path` (`textSelection`,
  /// `messageSelection`, `inlineCode` or `codeBlock`), with the message's
  /// scroll id and the facade's chat id.
  copyRefused,

  /// A tap or secondary click on a body part (`ChatInlineHit.bodyPart`)
  /// arbitrated (debug, `media` category): the `part` when the part id names
  /// itself ([ChatDiagnosablePart]), its `role`, the `mode` (`normal` or
  /// `selection`) and the [ChatBodyPartOutcome] as `outcome`, with the chat
  /// id, the message's scroll id and the media item's id when the part
  /// names one.
  hit,
}

/// What the viewport did with a tap on a body part; the `outcome` of a
/// [ChatSelectionOp.hit] event.
enum ChatBodyPartOutcome {
  /// The message's membership toggled (message selection).
  toggle,

  /// The part was reported to the body and the host (`ChatBodyPartActivated`).
  activate,

  /// The message menu was requested, the request carrying the part.
  menu,

  /// The tap dismissed a live text selection and did nothing else.
  dismiss,

  /// Nothing: a message that cannot be selected, or no menu callback.
  none,
}

/// A body part id that can name itself in a diagnostics event.
///
/// The viewport keeps a part id opaque; one that implements this lends the
/// [ChatSelectionOp.hit] event its `part` field and its media item
/// correlation. Neither may carry user content.
abstract interface class ChatDiagnosablePart {
  /// The part's kind as a log names it (`content`, `status`, `body`): a short
  /// fixed word, never text from the message.
  String get diagnosticName;

  /// The string form of the media item the part belongs to, or null for a
  /// part of no item.
  String? get diagnosticItemId;
}

/// Emits the [ChatSelectionOp.hit] event for a tap on [hit] the viewport
/// arbitrated as [outcome]; [inSelection] is the mode when the tap landed.
void emitBodyPartHit({
  required ChatInlineHit$BodyPart hit,
  required bool inSelection,
  required ChatBodyPartOutcome outcome,
  String? chatId,
}) {
  final named = switch (hit.partId) {
    final ChatDiagnosablePart part => part,
    _ => null,
  };
  ChatDiagnostics.current.emit(
    ChatEventLevel.debug,
    ChatEventCategory.media,
    ChatSelectionOp.hit,
    correlation: ChatCorrelation(
      chatId: chatId,
      scrollId: hit.messageId.toString(),
      mediaItemId: named?.diagnosticItemId,
    ),
    fields: () => {
      if (named != null) 'part': named.diagnosticName,
      'role': hit.role,
      'mode': inSelection ? 'selection' : 'normal',
      'outcome': outcome,
    },
  );
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
