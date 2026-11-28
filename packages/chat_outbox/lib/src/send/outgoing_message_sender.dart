import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The host's transport for outgoing messages: it asks the server to
/// publish one message and reports the server's answer.
///
/// The host registers it once at start (`ChatOutbox.registerSender`); the
/// outbox runs it as the publisher of every chat's publish jobs, after
/// their uploads. It is called once per attempt: again after a conflict
/// (within the same publish call) and after a retry or a restart (with the
/// same client message id, the idempotency key the server deduplicates
/// by). The outbox does the rest: the row's position, the conflict loop,
/// the outcome the engine reads, the denial feedback.
abstract interface class OutgoingMessageSender<M> {
  /// Publishes [request]'s message and answers what the server said.
  ///
  /// A throw fails the message as `unknown` (a retry calls again); a
  /// server's refusal is an answer, not a throw.
  Future<OutgoingSendAnswer<M>> send(OutgoingSendRequest<M> request);
}

/// One attempt to publish an outgoing message, as the sender receives it.
@immutable
final class OutgoingSendRequest<M> {
  /// An attempt for message [clientMessageId] of [chatId].
  OutgoingSendRequest({
    required this.chatId,
    required this.clientMessageId,
    required this.payload,
    required Map<MediaItemId, PublishItemRefs> items,
    required this.attempt,
    this.proposedId,
  }) : items = Map.unmodifiable(items);

  /// The chat the message goes to.
  final String chatId;

  /// The message's identity, and the idempotency key of every attempt: the
  /// server applies a message once per client message id.
  final String clientMessageId;

  /// The host's message model, decoded from the job's payload.
  final M payload;

  /// Each media item, in the message's order, to where its upload put it;
  /// empty for a text. An item sent as remote has no file reference: its
  /// key is on the server already.
  final Map<MediaItemId, PublishItemRefs> items;

  /// The id to propose to the server, under a strategy that proposes one:
  /// the next server id (`tip+1`), read now. Null when the strategy keeps
  /// the server's id in the host's model instead.
  final int? proposedId;

  /// The attempt within this publish call, from 1; a conflict's repeated
  /// send is the next one.
  final int attempt;

  // The payload stays out: it is the host's message.
  @override
  String toString() =>
      'OutgoingSendRequest($chatId, $clientMessageId, attempt $attempt, '
      'proposedId $proposedId, ${items.length} items)';
}

/// What the server answered a sender: published ([OutgoingSendResult]),
/// [reuploadItems], [conflict], [rejected] or [denied].
@immutable
sealed class OutgoingSendAnswer<M> {
  /// The server published the message; see [OutgoingSendResult].
  const factory OutgoingSendAnswer.sent({
    int? serverMessageId,
    Map<MediaItemId, MediaKey> serverKeys,
    M? payloadAsStored,
    List<IChatMessage> missing,
  }) = OutgoingSendResult<M>;

  /// The server lost the uploads of [itemIds] (an expired reference): they
  /// upload once more and the message publishes again. A second request in
  /// one message's life fails it.
  factory OutgoingSendAnswer.reuploadItems(Iterable<MediaItemId> itemIds) =
      OutgoingSendAnswer$ReuploadItems<M>;

  /// The proposed id was taken: the server's next id is [nextId]. The
  /// outbox moves the row there and sends again, within the same publish
  /// call; see [OutgoingSendAnswer$Conflict].
  const factory OutgoingSendAnswer.conflict({
    required int nextId,
    List<IChatMessage> missing,
  }) = OutgoingSendAnswer$Conflict<M>;

  /// The server refused the message for [reason], a short code of the
  /// host's that the message's failure keeps; [retryable] when sending
  /// again may succeed.
  ///
  /// Codes starting with `chat.` are the outbox's own: an [ArgumentError]
  /// for one.
  factory OutgoingSendAnswer.rejected(String reason, {bool retryable}) =
      OutgoingSendAnswer$Rejected<M>;

  /// The server denied [action] in this chat for [reason]: the message
  /// fails as denied and the host's `onDenied` hears of it once.
  const factory OutgoingSendAnswer.denied(
    CapabilityAction action,
    DenialReason reason,
  ) = OutgoingSendAnswer$Denied<M>;

  const OutgoingSendAnswer._();

  /// The answer's stable name, for diagnostics.
  String get name;
}

/// The server published the message ([OutgoingSendAnswer.sent]).
///
/// [serverMessageId] is the id the server stored it at. Under a strategy
/// that proposes ids, null means the proposal; another id is an idempotent
/// replay (the server had the message already, at that id), and the outbox
/// trusts it: the row moves there. Under a strategy that proposes none the
/// server's id is the host's, in its model, and this may stay null.
/// [serverKeys] are the server's keys of the items, by item; the engine
/// aliases each item's local content to it. [payloadAsStored] is the
/// message as the server stored it (its text normalised, entities
/// trimmed), for the host's reconcile; null when it is the payload as sent.
///
/// [missing] are the confirmed messages between the chat's tip and
/// [serverMessageId] when the host has them (fetched, or from the answer):
/// they take their positions before the row, so it lands at the server's
/// id. Messages the chat already holds are skipped.
final class OutgoingSendResult<M> extends OutgoingSendAnswer<M> {
  /// See [OutgoingSendAnswer.sent].
  const OutgoingSendResult({
    this.serverMessageId,
    this.serverKeys = const {},
    this.payloadAsStored,
    this.missing = const [],
  }) : super._();

  /// The server's id of the message; see the class.
  final int? serverMessageId;

  /// The server's key of each item, by item.
  final Map<MediaItemId, MediaKey> serverKeys;

  /// The message as the server stored it; null when as sent.
  final M? payloadAsStored;

  /// Confirmed messages to place before the row; see the class.
  final List<IChatMessage> missing;

  @override
  String get name => 'sent';

  @override
  String toString() =>
      'OutgoingSendResult($serverMessageId, ${serverKeys.length} keys)';
}

/// [OutgoingSendAnswer.reuploadItems].
final class OutgoingSendAnswer$ReuploadItems<M> extends OutgoingSendAnswer<M> {
  /// See [OutgoingSendAnswer.reuploadItems].
  OutgoingSendAnswer$ReuploadItems(Iterable<MediaItemId> itemIds)
    : itemIds = Set.unmodifiable(itemIds),
      super._();

  /// The items to upload again.
  final Set<MediaItemId> itemIds;

  @override
  String get name => 'reuploadItems';

  @override
  String toString() =>
      'OutgoingSendAnswer.reuploadItems(${itemIds.length} items)';
}

/// [OutgoingSendAnswer.conflict].
///
/// [missing] are the confirmed messages from the chat's tip up to [nextId]
/// when the host has them: they take their positions before the row, so
/// its next proposal is [nextId]. Without them the row cannot move past
/// positions the chat does not hold, and the repeated send proposes the
/// same id again; after three conflicts the message fails, retryable.
final class OutgoingSendAnswer$Conflict<M> extends OutgoingSendAnswer<M> {
  /// See [OutgoingSendAnswer.conflict].
  const OutgoingSendAnswer$Conflict({
    required this.nextId,
    this.missing = const [],
  }) : super._();

  /// The server's next id.
  final int nextId;

  /// Confirmed messages to place before the row; see the class.
  final List<IChatMessage> missing;

  @override
  String get name => 'conflict';

  @override
  String toString() => 'OutgoingSendAnswer.conflict($nextId)';
}

/// [OutgoingSendAnswer.rejected].
final class OutgoingSendAnswer$Rejected<M> extends OutgoingSendAnswer<M> {
  /// See [OutgoingSendAnswer.rejected].
  OutgoingSendAnswer$Rejected(this.reason, {this.retryable = false})
    : super._() {
    if (reason.startsWith(reservedPrefix)) {
      throw ArgumentError.value(
        reason,
        'reason',
        'Codes starting with "$reservedPrefix" are the outbox\'s own.',
      );
    }
  }

  /// The prefix of the outbox's own rejection codes.
  static const String reservedPrefix = 'chat.';

  /// The host's code for why.
  final String reason;

  /// Whether sending again may succeed.
  final bool retryable;

  @override
  String get name => 'rejected';

  // The reason stays out: it comes from the server.
  @override
  String toString() => 'OutgoingSendAnswer.rejected(retryable: $retryable)';
}

/// [OutgoingSendAnswer.denied].
final class OutgoingSendAnswer$Denied<M> extends OutgoingSendAnswer<M> {
  /// See [OutgoingSendAnswer.denied].
  const OutgoingSendAnswer$Denied(this.action, this.reason) : super._();

  /// The action the server denied.
  final CapabilityAction action;

  /// Why.
  final DenialReason reason;

  @override
  String get name => 'denied';

  @override
  String toString() => 'OutgoingSendAnswer.denied(${action.name})';
}

/// What the host learns when the server published one of its outgoing
/// messages: the row to settle and the message as stored.
///
/// The host's duty, in the call: replace the outbox's row at [rowAt] with
/// the confirmed message (one `updateMessage` at that id, a message the
/// data source's `identityOf` answers null for), from [payloadAsStored]
/// when given (the reconcile of the rich-text wire, ADR 034), else
/// [payload]. When [rowAt] is null the row has left the list (the server
/// stored the message at an id the chat does not reach yet): the host
/// places the confirmed message at [position] as it does any message it
/// learns of.
@immutable
final class OutgoingSent<M> {
  /// The published message [clientMessageId] of [chatId].
  OutgoingSent({
    required this.chatId,
    required this.clientMessageId,
    required this.position,
    required this.payload,
    required Map<MediaItemId, MediaKey> serverKeys,
    this.rowAt,
    this.serverMessageId,
    this.payloadAsStored,
  }) : serverKeys = Map.unmodifiable(serverKeys);

  /// The chat.
  final String chatId;

  /// The message's identity.
  final String clientMessageId;

  /// The message's id in the chat from now on: the server's id under a
  /// strategy that proposes ids, the row's local id otherwise.
  final int position;

  /// The outbox's row to replace, at [position]; null when it left the
  /// list.
  final int? rowAt;

  /// The server's id of the message as its sender answered, if it did.
  final int? serverMessageId;

  /// The message as sent.
  final M payload;

  /// The message as the server stored it; null when as sent.
  final M? payloadAsStored;

  /// The server's key of each item, by item.
  final Map<MediaItemId, MediaKey> serverKeys;

  // The payloads stay out: they are the host's message.
  @override
  String toString() =>
      'OutgoingSent($chatId, $clientMessageId at $position, row $rowAt)';
}
