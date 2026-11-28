import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:chat_outbox/src/outbox/outbox_projection.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// What the outbox holds for one chat right now, for a debug panel and a
/// diagnostics journal: the id strategy and the tip, the provisional tail
/// row by row, the publisher, the send in flight and the counters.
///
/// Holds no user content: no payload (only its length), no message text, no
/// file names or URLs. Every section is declared whether or not this outbox
/// knows it yet; a section it does not know is null, so a reader renders the
/// same shape every time. [toMap] is the structured form to render or
/// journal, not a `toString`.
@immutable
final class OutboxDebugSnapshot {
  /// A snapshot of [chatId]; [tail] is copied.
  OutboxDebugSnapshot({
    required this.chatId,
    required List<OutboxDebugRow> tail,
    this.strategy,
    this.tip,
    this.publisherRegistered,
    this.sendInFlight,
    this.counters = const OutboxDebugCounters(),
  }) : tail = List.unmodifiable(tail);

  /// The chat.
  final String chatId;

  /// The id strategy's name; null when none is set.
  final String? strategy;

  /// The newest server message's id the tail sits after; null when unknown.
  final int? tip;

  /// The provisional tail in order, lowest position first.
  final List<OutboxDebugRow> tail;

  /// Whether the host's sender is registered as the chat publisher; null
  /// when unknown.
  final bool? publisherRegistered;

  /// Whether a send of this chat is in flight; null when unknown.
  final bool? sendInFlight;

  /// Counts since the outbox started.
  final OutboxDebugCounters counters;

  /// The snapshot as maps, lists, strings, numbers, booleans and nulls, in a
  /// fixed key order; JSON-encodable.
  Map<String, Object?> toMap() => {
    'chatId': chatId,
    'strategy': strategy,
    'tip': tip,
    'tail': [for (final row in tail) row.toMap()],
    'publisherRegistered': publisherRegistered,
    'sendInFlight': sendInFlight,
    'counters': counters.toMap(),
  };
}

/// One row of the provisional tail in an [OutboxDebugSnapshot].
@immutable
final class OutboxDebugRow {
  /// A row; [items] is copied.
  OutboxDebugRow({
    required this.position,
    required this.clientMessageId,
    required this.status,
    required this.payloadBytes,
    required this.fresh,
    List<OutboxDebugItem> items = const [],
    this.failure,
    this.jobId,
    this.jobState,
    this.stage,
    this.attempts,
  }) : items = List.unmodifiable(items);

  /// The row of [message]; [fresh] tells whether its fresh flag is unread,
  /// and [job] is its publish job as the outbox last saw it.
  @internal
  factory OutboxDebugRow.of(
    OutgoingMessage message, {
    required bool fresh,
    OutboxJobView? job,
  }) => OutboxDebugRow(
    position: message.position,
    clientMessageId: message.clientMessageId,
    status: message.status.name,
    failure: switch (message.status) {
      OutgoingStatus$Failed(:final failure) => failure.name,
      _ => null,
    },
    payloadBytes: message.payload.length,
    fresh: fresh,
    items: [for (final item in message.items) OutboxDebugItem.of(item)],
    jobId: job?.id,
    jobState: job?.state,
    stage: job?.stage?.name,
  );

  /// The row's id in the tail; null while no id strategy has placed it.
  final int position;

  /// The message's identity.
  final String clientMessageId;

  /// The status's name (`OutgoingStatus.name`).
  final String status;

  /// A failed message's reason form (`OutgoingFailure.name`); null otherwise.
  final String? failure;

  /// The payload's length in bytes; never the payload.
  final int payloadBytes;

  /// Whether the host has yet to read the row's fresh flag.
  final bool fresh;

  /// The items in order.
  final List<OutboxDebugItem> items;

  /// The publish job's id; null when unknown.
  final String? jobId;

  /// The publish job's state name; null when unknown.
  final String? jobState;

  /// The stage the publish job is in (`prepare`, `upload`, `publish`); null
  /// when unknown, or once the job completed.
  final String? stage;

  /// Publish attempts so far; null when unknown.
  final int? attempts;

  /// The row as a map; see [OutboxDebugSnapshot.toMap].
  Map<String, Object?> toMap() => {
    'position': position,
    'clientMessageId': clientMessageId,
    'status': status,
    'failure': failure,
    'payloadBytes': payloadBytes,
    'fresh': fresh,
    'jobId': jobId,
    'jobState': jobState,
    'stage': stage,
    'attempts': attempts,
    'items': [for (final item in items) item.toMap()],
  };
}

/// One media item of an [OutboxDebugRow].
@immutable
final class OutboxDebugItem {
  /// An item.
  const OutboxDebugItem({
    required this.mediaItemId,
    required this.localKey,
    this.mediaKey,
    this.transfer,
    this.sendOriginHeld,
  });

  /// The item of [item].
  @internal
  factory OutboxDebugItem.of(OutgoingItem item) => OutboxDebugItem(
    mediaItemId: '${item.id}',
    localKey: switch (item.localKey) {
      // An external id may be a URL, which is user content: its kind only.
      ContentKey$External() => 'external',
      final key => key.encoded,
    },
  );

  /// The item's `MediaItemId` in its string form.
  final String mediaItemId;

  /// The local content key in its encoded form, or `external` for a key
  /// whose id may be a URL.
  final String localKey;

  /// The media cache key's stable string; null when unknown.
  final String? mediaKey;

  /// The item's transfer state name; null when unknown.
  final String? transfer;

  /// Whether the outbox still holds the item's send origin; null when
  /// unknown.
  final bool? sendOriginHeld;

  /// The item as a map; see [OutboxDebugSnapshot.toMap].
  Map<String, Object?> toMap() => {
    'mediaItemId': mediaItemId,
    'localKey': localKey,
    'mediaKey': mediaKey,
    'transfer': transfer,
    'sendOriginHeld': sendOriginHeld,
  };
}

/// The outbox's counts in an [OutboxDebugSnapshot], since it started.
@immutable
final class OutboxDebugCounters {
  /// Counts, zero unless given; [rebases] is by reason name.
  const OutboxDebugCounters({
    this.accepted = 0,
    this.rebases = const {},
    this.conflicts = 0,
    this.retries = 0,
    this.cancels = 0,
    this.restores = 0,
  });

  /// Sends accepted.
  final int accepted;

  /// Tail rebases by reason (`incoming`, `publishStart`, `failedSink`, …).
  final Map<String, int> rebases;

  /// Publish conflicts answered.
  final int conflicts;

  /// Retries of failed messages.
  final int retries;

  /// Messages cancelled or deleted.
  final int cancels;

  /// Messages restored after a restart.
  final int restores;

  /// The counters as a map; see [OutboxDebugSnapshot.toMap].
  Map<String, Object?> toMap() => {
    'accepted': accepted,
    'rebases': {...rebases},
    'conflicts': conflicts,
    'retries': retries,
    'cancels': cancels,
    'restores': restores,
  };
}
