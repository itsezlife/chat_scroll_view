import 'dart:async';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_outbox/src/diagnostics/outbox_debug_snapshot.dart';
import 'package:chat_outbox/src/diagnostics/outbox_op.dart';
import 'package:chat_outbox/src/diagnostics/outbox_trace.dart';
import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:chat_outbox/src/message/outgoing_payload_codec.dart';
import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:chat_outbox/src/outbox/chat_send_publisher.dart';
import 'package:chat_outbox/src/outbox/job_projection.dart';
import 'package:chat_outbox/src/outbox/outbox_projection.dart';
import 'package:chat_outbox/src/outbox/outgoing_cancel.dart';
import 'package:chat_outbox/src/outbox/outgoing_retry.dart';
import 'package:chat_outbox/src/send/outgoing_message_sender.dart';
import 'package:chat_outbox/src/send/outgoing_send_item.dart';
import 'package:chat_outbox/src/send/send_check.dart';
import 'package:chat_outbox/src/transfers/outbox_transfers.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The outbox: the outgoing messages of every chat, sent as publish jobs
/// and read back as the host and the chat's rows see them.
///
/// [send] turns a planned send (or [sendText] a text) into one publish job
/// under the chat's tag, after the chat's slow mode and limits let it
/// through; the job's state, watched per chat, is the message's status.
/// [M] is the host's message model, which the outbox keeps as bytes
/// through the host's [OutgoingPayloadCodec]. The chat's
/// [OutgoingIdStrategy] places each accepted message's row in the
/// provisional tail and moves it there.
///
/// A failed message's row sinks below the sending rows; [retry] repeats
/// only what failed and [delete] makes it Absent.
///
/// It keeps no store of its own; its view of each chat is a projection of
/// the publish jobs, so a restart reads the same messages back. Every
/// lookup is per chat and by the message's client message id, its identity,
/// never by its row's position, which moves with the provisional tail.
///
/// Call [dispose] when the host shuts the chat down: it stops watching the
/// jobs, which run on in the engine.
final class ChatOutbox<M> {
  /// An outbox with no outgoing messages, making its jobs through
  /// [transfers].
  ///
  /// [codec] turns the host's message model into the job's payload.
  /// [itemOf] answers, for each attach item of a planned send, its keys
  /// and where its bytes come from. [idStrategyOf] makes a chat's id
  /// strategy, once per chat, on its first send; [rowOf] builds the host's
  /// row for an accepted message at the position the strategy gives it
  /// (`OutgoingMessage.position`). [capabilitiesOf] gives the chat's
  /// capabilities listenable, the one the host passes the chat's other
  /// consumers; a chat without one is unrestricted. [feedback] hears of a
  /// refused send. [clientMessageIds] issues each send's client message id
  /// (128 random bits in hex unless given); an id never contains `:`, which
  /// separates the parts of a job's tag. [now] is the clock slow mode is
  /// read at.
  ///
  /// [onSent] hears of each message the server published, inside the
  /// publish call: the host's duty there is to replace the outbox's row with
  /// the confirmed message (see [OutgoingSent]), before the chat's next
  /// outgoing row publishes.
  ///
  /// [onCancelled] hears of each message the outbox cancelled, whoever
  /// asked (the host's [cancel] or [cancelItem], or a cell's status
  /// control through the engine), and [onItemDropped] of each item that
  /// left a message that goes on: the host's duty there is to drop the item
  /// from its row.
  ///
  /// [onStatusChanged] hears of each change of a message's status after its
  /// send, with the message as it is now: the job moving on, failing, a
  /// retry repeating a stage, the server's accept. It is what the host's
  /// time pill and error badge redraw on, since a status change need not
  /// move the row. A cancel is not one: [onCancelled] reports it, and the
  /// row is gone.
  ///
  /// [localKeyOf] and [undecodableRowOf] serve [pendingFor] after a restart,
  /// when a message is known only from its job: [localKeyOf] maps an item's
  /// media key back to its local content key (the inverse of the mapping
  /// [itemOf] answers with), and [undecodableRowOf] builds the row of a
  /// message whose payload the [codec] cannot read, which has no model for
  /// [rowOf].
  ///
  /// [deleteOnSystemInterruption] is what a message does when the system
  /// ends the transfer envelope its job runs in (an OS time limit or
  /// expiry, a low-memory kill): by default (false, on every platform) the
  /// job pauses and the message keeps sending in its stage, going on once
  /// the app is back in the foreground; true deletes it instead, as a
  /// cancel does. The envelope itself, its notification's strings, the
  /// iOS `Info.plist` entries and the Play Console declaration are the
  /// host's duties toward `mpx_transfer` (see its README, "Android" and
  /// "iOS"); the outbox only reads what the jobs do.
  ChatOutbox({
    required OutboxTransfers transfers,
    required OutgoingPayloadCodec<M> codec,
    required OutgoingSendItemResolver itemOf,
    required OutgoingIdStrategy Function(String chatId) idStrategyOf,
    required OutgoingRowBuilder<M> rowOf,
    ValueListenable<ChatCapabilities>? Function(String chatId)? capabilitiesOf,
    CapabilityFeedback feedback = CapabilityFeedback.none,
    String Function()? clientMessageIds,
    DateTime Function() now = DateTime.now,
    void Function(OutgoingSent<M> sent)? onSent,
    void Function(OutgoingCancelled cancelled)? onCancelled,
    void Function(OutgoingItemDropped dropped)? onItemDropped,
    void Function(OutgoingMessage message)? onStatusChanged,
    ContentKey Function(MediaKey mediaKey)? localKeyOf,
    IChatMessage Function(OutgoingMessage message)? undecodableRowOf,
    bool deleteOnSystemInterruption = false,
  }) : this.over(
         OutboxProjection(),
         transfers: transfers,
         codec: codec,
         itemOf: itemOf,
         idStrategyOf: idStrategyOf,
         rowOf: rowOf,
         capabilitiesOf: capabilitiesOf,
         feedback: feedback,
         clientMessageIds: clientMessageIds,
         now: now,
         onSent: onSent,
         onCancelled: onCancelled,
         onItemDropped: onItemDropped,
         onStatusChanged: onStatusChanged,
         localKeyOf: localKeyOf,
         undecodableRowOf: undecodableRowOf,
         deleteOnSystemInterruption: deleteOnSystemInterruption,
       );

  /// An outbox reading [projection], for tests that set rows up directly.
  @visibleForTesting
  ChatOutbox.over(
    this._projection, {
    required OutboxTransfers transfers,
    required OutgoingPayloadCodec<M> codec,
    required OutgoingSendItemResolver itemOf,
    required OutgoingIdStrategy Function(String chatId) idStrategyOf,
    required OutgoingRowBuilder<M> rowOf,
    ValueListenable<ChatCapabilities>? Function(String chatId)? capabilitiesOf,
    CapabilityFeedback feedback = CapabilityFeedback.none,
    String Function()? clientMessageIds,
    DateTime Function() now = DateTime.now,
    void Function(OutgoingSent<M> sent)? onSent,
    void Function(OutgoingCancelled cancelled)? onCancelled,
    void Function(OutgoingItemDropped dropped)? onItemDropped,
    void Function(OutgoingMessage message)? onStatusChanged,
    ContentKey Function(MediaKey mediaKey)? localKeyOf,
    IChatMessage Function(OutgoingMessage message)? undecodableRowOf,
    this.deleteOnSystemInterruption = false,
  }) : _onCancelled = onCancelled,
       _onItemDropped = onItemDropped,
       _onStatusChanged = onStatusChanged,
       _localKeyOf = localKeyOf,
       _undecodableRowOf = undecodableRowOf,
       _transfers = transfers,
       _codec = codec,
       _itemOf = itemOf,
       _makeIdStrategy = idStrategyOf,
       _rowOf = rowOf,
       _capabilitiesOf = capabilitiesOf,
       _feedback = feedback,
       _issueClientMessageId = clientMessageIds ?? _$randomClientMessageId,
       _now = now,
       _onSent = onSent;

  /// The publisher id the outbox's jobs name: the host's sender, registered
  /// by the outbox.
  static const String publisherId = 'chat.send';

  /// How long the outbox keeps a send origin nobody takes, from the send's
  /// accept.
  ///
  /// A media cell takes its origin on its first frame, which comes within
  /// a frame or two of the send when the host inserts the row at once; an
  /// origin still untaken after this would fly from a thumbnail the user
  /// stopped looking at long ago, so the cell appears without it.
  static const Duration sendOriginLifetime = Duration(seconds: 5);

  /// The tag of the publish job of message [clientMessageId] of [chatId].
  static String tagOf(String chatId, String clientMessageId) =>
      '${tagPrefixOf(chatId)}$clientMessageId';

  /// The tag prefix every publish job of [chatId] starts with.
  static String tagPrefixOf(String chatId) => 'chat:$chatId:';

  /// Whether a message whose job the system's end of the transfer envelope
  /// paused is deleted rather than kept sending; see [ChatOutbox.new].
  final bool deleteOnSystemInterruption;

  final OutboxProjection _projection;
  final OutboxTransfers _transfers;
  final OutgoingPayloadCodec<M> _codec;
  final OutgoingSendItemResolver _itemOf;
  final OutgoingIdStrategy Function(String chatId) _makeIdStrategy;
  final OutgoingRowBuilder<M> _rowOf;

  /// Each chat's id strategy, made on its first use.
  final Map<String, OutgoingIdStrategy> _$strategies = {};
  final ValueListenable<ChatCapabilities>? Function(String chatId)?
  _capabilitiesOf;
  final CapabilityFeedback _feedback;
  final String Function() _issueClientMessageId;
  final DateTime Function() _now;
  final void Function(OutgoingSent<M> sent)? _onSent;
  final void Function(OutgoingCancelled cancelled)? _onCancelled;
  final void Function(OutgoingItemDropped dropped)? _onItemDropped;
  final void Function(OutgoingMessage message)? _onStatusChanged;

  /// The cancels accepted so far, by (chat id, client message id, item id or
  /// null for the whole message), with when: the input guard drops a repeat,
  /// and an id issued again after its message was cancelled is refused.
  final Map<(String, String, String?), DateTime> _$cancelsAccepted = {};

  /// Messages that lost an item already: the last one going then is
  /// `lastItemNoText`, not `onlyItem`.
  final Set<(String, String)> _$itemsDropped = {};

  /// Jobs the outbox committed after they lost their last item, so a late
  /// snapshot of them waiting for their owner is not decided twice.
  final Set<PublishJobId> _$committed = {};

  /// The retries accepted since each message last failed, by (chat id,
  /// client message id), with when: the input guard drops a repeat until
  /// the message fails again.
  final Map<(String, String), DateTime> _$retriesAccepted = {};

  int _$retries = 0;
  int _$cancels = 0;
  int _$tooLate = 0;
  int _$droppedItems = 0;
  final ContentKey Function(MediaKey mediaKey)? _localKeyOf;
  final IChatMessage Function(OutgoingMessage message)? _undecodableRowOf;

  /// What the chat publisher counted, across registrations.
  final PublishCounters _$publishCounters = PublishCounters();

  bool _$senderRegistered = false;

  /// The chats whose jobs the outbox watches, with their subscription.
  final Map<String, StreamSubscription<List<PublishJobSnapshot>>> _$watches =
      {};

  /// Whether each chat has a send in flight, as last reported.
  final Map<String, bool> _$inFlight = {};

  /// The listenables handed out by [sendInFlight].
  final Map<String, ValueNotifier<bool>> _$inFlightNotifiers = {};

  int _$accepted = 0;

  /// Each chat's restore, run once: [pendingFor] awaits it.
  final Map<String, Future<void>> _$restores = {};

  /// The publisher's calls waiting for their message's restore, by client
  /// message id.
  final Map<String, Completer<OutgoingMessage?>> _$restoreWaiters = {};

  int _$restored = 0;

  /// Jobs the system's end of the transfer envelope paused, until they go
  /// on: each is reported `systemInterrupted` once, then `resumed` once.
  final Set<PublishJobId> _$interrupted = {};

  /// Messages the engine took away from the outbox (their job left without
  /// its owner cancelling it) or that leave as their job paused, by chat
  /// and client message id, with what made them go: deleted together once
  /// the engine's burst of snapshots is read ([_leaveSoon]).
  final Map<String, Map<String, _Trigger>> _$leaving = {};
  Timer? _$leavingFlush;

  bool _$disposed = false;

  // --- Sending ---------------------------------------------------------------

  /// Sends [send] to [chatId] as one publish job carrying [payload], and
  /// answers the outgoing message, or null when the chat's capabilities
  /// refuse it.
  ///
  /// The message's client message id is issued first, since the job's tag
  /// (`chat:<chatId>:<clientMessageId>`) and idempotency key carry it. Then
  /// slow mode and the chat's limits are checked: a refused send calls the
  /// host's `onDenied` (consumer `outbox`) and makes no job. An accepted
  /// one becomes a job of the chat's publisher, ordered with the chat's
  /// other jobs, its uploads kept going by the system, failing as a whole
  /// when any item fails; a text is a job with no items.
  ///
  /// Each item's `MediaItemId` is the client message id and the item's
  /// index (`<clientMessageId>:<index>`), unless the host gives its own
  /// [itemIds], one per item in order. After the job is made the chat's id
  /// strategy places the message's row (built by the host's row builder)
  /// in the provisional tail; the answered message holds its position. The
  /// message is fresh: the host's [isFreshOutgoing] answers true for it
  /// once.
  ///
  /// [origins] are the picker's send origins by item order: each item's
  /// global thumbnail rect at send time, null for an item the picker did
  /// not show. The outbox keys them by the items' `MediaItemId`s and hands
  /// each out once through [takeSendOrigin].
  ///
  /// Reports `refusedBeforeJob`, or `accepted`, `jobCreated`,
  /// `positionAllocated` and, with [origins], `sendOriginStored`. Throws an [ArgumentError] when
  /// [itemIds] or [origins] does not give one entry per item, and
  /// whatever the engine throws for a request it cannot run, after which
  /// the outbox holds nothing of the send.
  OutgoingMessage? send(
    String chatId,
    PlannedSend send, {
    required M payload,
    List<MediaItemId>? itemIds,
    List<Rect?>? origins,
  }) {
    _checkNotDisposed();
    _projection.origins.expire(_now());
    final items = switch (send) {
      PlannedSend$Single(:final item) => [item],
      PlannedSend$Group(:final items) => items,
      PlannedSend$Text() => const <AttachItem>[],
    };
    if (itemIds != null && itemIds.length != items.length) {
      throw ArgumentError.value(
        itemIds.length,
        'itemIds',
        'One id per item: the send has ${items.length}.',
      );
    }
    if (origins != null && origins.length != items.length) {
      throw ArgumentError.value(
        origins.length,
        'origins',
        'One origin (or null) per item: the send has ${items.length}.',
      );
    }
    final clientMessageId = _issueClientMessageId();
    if (_$cancelsAccepted.containsKey((chatId, clientMessageId, null))) {
      // A cancelled message's id stays its own: reusing it would match the
      // server's late echo of the old message to the new one.
      throw StateError(
        'The client message id $clientMessageId was issued before and its '
        'message cancelled; an id is never reused.',
      );
    }
    final correlation = ChatCorrelation(
      chatId: chatId,
      clientMessageId: clientMessageId,
    );
    if (_refusalOf(chatId, send) case final refusal?) {
      _refuse(refusal, correlation);
      return null;
    }
    final ids =
        itemIds ??
        [
          for (var index = 0; index < items.length; index++)
            MediaItemId('$clientMessageId:$index'),
        ];
    final form = switch (send) {
      PlannedSend$Single(:final form) || PlannedSend$Group(:final form) => form,
      PlannedSend$Text() => SendForm.media,
    };
    final sendItems = [for (final item in items) _itemOf(item, form)];
    final strategy = idStrategy(chatId);
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.outbox,
      OutboxOp.accepted,
      correlation: correlation,
      fields: () => {
        'kind': switch (send) {
          PlannedSend$Text() => 'text',
          PlannedSend$Single() => 'single',
          PlannedSend$Group() => 'group',
        },
        'items': items.length,
        'idsIssuedBy': itemIds == null ? 'outbox' : 'host',
        'strategy': strategy.name,
      },
    );
    final request = PublishRequest(
      tag: tagOf(chatId, clientMessageId),
      items: [
        for (final (index, item) in sendItems.indexed)
          PublishItem(
            itemId: '${ids[index]}',
            key: item.mediaKey,
            source: item.source,
            fingerprint: item.fingerprint,
            fileName: item.fileName,
          ),
      ],
      payload: _codec.encode(payload),
      publisher: publisherId,
      idempotencyKey: clientMessageId,
      orderingGroup: chatId,
    );
    final jobId = _transfers.publish(request);
    _reportJobCreated(request, correlation, jobId);
    OutgoingMessage at(int position) => OutgoingMessage(
      chatId: chatId,
      clientMessageId: clientMessageId,
      position: position,
      status: _firstStatusOf(request),
      payload: request.payload,
      items: [
        for (final (index, item) in sendItems.indexed)
          OutgoingItem(id: ids[index], localKey: item.localKey),
      ],
    );
    final message = at(
      strategy.allocate(
        clientMessageId,
        (position) => _rowOf(at(position), payload),
      ),
    );
    _projection
      ..put(message, fresh: true, job: OutboxJobView(jobId))
      ..putSendFacts(
        message,
        hasText: _hasTextOf(send),
        mediaKeys: [for (final item in sendItems) item.mediaKey],
      );
    if (origins != null) _storeOrigins(message, origins);
    _$accepted++;
    _watch(chatId);
    _syncInFlight(chatId);
    return message;
  }

  /// Sends [text] to [chatId] as a text message carrying [payload]: a job
  /// with no items, checked against the message length. See [send].
  OutgoingMessage? sendText(
    String chatId,
    RichText text, {
    required M payload,
  }) => send(chatId, PlannedSend.text(text), payload: payload);

  /// Whether a send of [chatId] is in flight: true while one of its
  /// outgoing messages is preparing, uploading or publishing.
  ///
  /// The host's duty: fold it into the chat's capabilities value as
  /// `slowMode.pending` (a `SlowMode.active` with `pending: true`), so the
  /// composer and the picker hold the next send while one is still sending.
  /// The outbox's own check reads it without waiting for that.
  ///
  /// The same listenable on every call for one chat, until [dispose].
  ValueListenable<bool> sendInFlight(String chatId) => _$inFlightNotifiers
      .putIfAbsent(chatId, () => ValueNotifier(_$inFlight[chatId] ?? false));

  /// The send origin of item [id]: the global rect its thumbnail had in the
  /// picker when the user sent it, or null when the outbox holds none.
  ///
  /// One-shot: an origin is answered once, then null. One the cell never
  /// takes goes with its message once it is sent or cancelled, or after
  /// [sendOriginLifetime]. The host hands this to its media state as the
  /// one-shot origin lookup, a `Rect? Function(MediaItemId)`. Reports
  /// `sendOriginTaken` for an item of an outgoing message here.
  Rect? takeSendOrigin(MediaItemId id) {
    final now = _now();
    _projection.origins.expire(now);
    final taken = _projection.origins.take(id);
    final message = _projection.messageOfItem(id);
    if (message != null) {
      ChatDiagnostics.current.emit(
        ChatEventLevel.debug,
        ChatEventCategory.outbox,
        OutboxOp.sendOriginTaken,
        correlation: ChatCorrelation(
          chatId: message.chatId,
          clientMessageId: message.clientMessageId,
          mediaItemId: '$id',
        ),
        fields: () => {
          'present': taken != null,
          if (taken case (:final acceptedAt, rect: _))
            'msSinceAccept': now.difference(acceptedAt).inMilliseconds,
        },
      );
    }
    return taken?.rect;
  }

  void _storeOrigins(OutgoingMessage message, List<Rect?> origins) {
    final accepted = _now();
    final held = {
      for (final (index, item) in message.items.indexed)
        item.id: ?origins[index],
    };
    _projection.origins.store(
      message.chatId,
      message.clientMessageId,
      held,
      at: accepted,
      expiresAt: accepted.add(sendOriginLifetime),
    );
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.sendOriginStored,
      correlation: ChatCorrelation(
        chatId: message.chatId,
        clientMessageId: message.clientMessageId,
      ),
      fields: () => {
        'withOrigin': held.length,
        'withoutOrigin': origins.length - held.length,
      },
    );
  }

  /// The id strategy of [chatId], made on first use: the one that places
  /// and moves the chat's outgoing rows.
  ///
  /// The host's duty: hand it the incoming messages that land inside the
  /// provisional tail (`OutgoingIdStrategy.incoming`) instead of inserting
  /// them, so they take their positions before the outgoing rows.
  OutgoingIdStrategy idStrategy(String chatId) =>
      _$strategies.putIfAbsent(chatId, () => _makeIdStrategy(chatId));

  /// [message] at the position its chat's strategy holds for it now; the
  /// stored one when the strategy no longer moves it.
  OutgoingMessage _current(OutgoingMessage message) =>
      switch (_$strategies[message.chatId]?.positionOf(
        message.clientMessageId,
      )) {
        final position? when position != message.position =>
          message.withPosition(position),
        _ => message,
      };

  SendRefusal? _refusalOf(String chatId, PlannedSend send) {
    final capabilities = _capabilitiesOf?.call(chatId)?.value;
    if (capabilities == null) return null;
    return SendCheck.of(
      send,
      capabilities,
      now: _now(),
      inFlight: _projection.hasInFlight(chatId),
    );
  }

  void _refuse(SendRefusal refusal, ChatCorrelation correlation) {
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.outbox,
      OutboxOp.refusedBeforeJob,
      correlation: correlation,
      fields: () => {
        'action': refusal.rule,
        'reason': refusal.reason.diagnosticForm,
      },
    );
    _feedback.onDenied(
      refusal.action,
      refusal.reason,
      consumer: CapabilityConsumer.outbox,
      remaining: refusal.remaining,
      correlation: correlation,
    );
  }

  static void _reportJobCreated(
    PublishRequest request,
    ChatCorrelation correlation,
    PublishJobId jobId,
  ) {
    final sources = request.items.map((item) => item.source).toList();
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.jobCreated,
      correlation: ChatCorrelation(
        chatId: correlation.chatId,
        clientMessageId: correlation.clientMessageId,
        jobId: jobId,
      ),
      fields: () => {
        'durability': request.durability,
        'failurePolicy': request.failurePolicy,
        'orderingGroup': request.orderingGroup != null,
        'prepare': sources.whereType<PublishSource$Prepare>().length,
        'prepared': sources.whereType<PublishSource$Prepared>().length,
        'remote': sources.whereType<PublishSource$Remote>().length,
        'payloadBytes': request.payload.length,
      },
    );
  }

  /// Whether [send] carries text besides its items: a caption, the batch's
  /// or an item's own, that is not empty.
  static bool _hasTextOf(PlannedSend send) => switch (send) {
    PlannedSend$Text() => true,
    PlannedSend$Single(:final caption) => !(caption?.isEmpty ?? true),
    PlannedSend$Group(:final caption, :final itemCaptions) => [
      caption,
      ...itemCaptions,
    ].any((text) => !(text?.isEmpty ?? true)),
  };

  /// The status of a job not seen yet: its first stage, preparing when an
  /// item needs preparing, uploading when one is ready to upload, and
  /// publishing when nothing is to upload (a text, or content the server
  /// has).
  static OutgoingStatus _firstStatusOf(PublishRequest request) {
    var upload = false;
    for (final item in request.items) {
      switch (item.source) {
        case PublishSource$Prepare():
          return const OutgoingStatus.preparing();
        case PublishSource$Prepared():
          upload = true;
        case PublishSource$Remote():
          break;
      }
    }
    return upload
        ? const OutgoingStatus.uploading()
        : const OutgoingStatus.publishing();
  }

  // --- Publishing ------------------------------------------------------------

  /// Registers the host's [sender] as the publisher of every chat's
  /// outgoing messages, replacing any registered before.
  ///
  /// The host's duty: register it once at start. Until then every publish
  /// job waits at its publish stage (its message reads as publishing), after
  /// a restart too; registering sends the waiting ones. Reports
  /// `publisherRegistered`.
  void registerSender(OutgoingMessageSender<M> sender) {
    _checkNotDisposed();
    _transfers.registerPublisher(
      publisherId,
      ChatSendPublisher(
        projection: _projection,
        strategyOf: idStrategy,
        codec: _codec,
        sender: sender,
        feedback: _feedback,
        onSent: _onSent,
        onStatusChanged: _onStatusChanged,
        counters: _$publishCounters,
        now: _now,
        restoredMessage: _restoredMessage,
      ),
    );
    _$senderRegistered = true;
    final chats = [..._projection.chats];
    if (chats.isEmpty) _reportRegistered(ChatCorrelation.none, 0);
    for (final chatId in chats) {
      final waiting = _projection
          .tailOf(chatId)
          .where(
            (message) =>
                _projection.jobOf(chatId, message.clientMessageId)?.state ==
                'awaitingPublisher',
          )
          .length;
      _reportRegistered(ChatCorrelation(chatId: chatId), waiting);
    }
  }

  static void _reportRegistered(ChatCorrelation correlation, int waiting) =>
      ChatDiagnostics.current.emit(
        ChatEventLevel.info,
        ChatEventCategory.outbox,
        OutboxOp.publisherRegistered,
        correlation: correlation,
        fields: () => {'waiting': waiting},
      );

  // --- Cancel ----------------------------------------------------------------

  /// Cancels the outgoing message [clientMessageId] of [chatId] (the
  /// message menu's cancel): its job is cancelled, its status is
  /// `cancelled`, and it becomes Absent, its row leaving the provisional
  /// tail in one `rebaseTail` (the rows after it move down; under
  /// `SequentialServerIds` the next row may take its position). Its client
  /// message id is never issued again.
  ///
  /// While the server's answer to the message's publish is in flight the
  /// cancel waits for it ([OutgoingCancelOutcome.pending]): a message the
  /// server accepted stays sent, as does one the cancel finds sent
  /// ([OutgoingCancelOutcome.tooLate]); the host may delete it as any sent
  /// message. The host's `onCancelled` hears of the message once it is
  /// cancelled.
  ///
  /// Guarded against a burst: once a cancel of the message is accepted,
  /// another one changes nothing ([OutgoingCancelOutcome.dropped]).
  /// Reports `cancelled` (trigger `menu`), `cancelTooLate` or
  /// `actionDropped`.
  OutgoingCancelOutcome cancel(String chatId, String clientMessageId) {
    _checkNotDisposed();
    return _cancelMessage(chatId, clientMessageId, trigger: _Trigger.menu);
  }

  /// Cancels item [itemId] of the outgoing message [clientMessageId] of
  /// [chatId] (the cross on its media cell).
  ///
  /// | The message | Effect |
  /// | --- | --- |
  /// | an album | the item drops and the rest publish ([OutgoingCancelOutcome.itemDropped]) |
  /// | its only item, no text | the message is cancelled, as [cancel] does |
  /// | its last item, with text | the item drops and the text publishes alone, joining the end of the chat's sending messages |
  /// | its last item of an album, no text | the message is cancelled |
  ///
  /// The host's `onItemDropped` hears of each item that drops, so it drops
  /// it from its row; `onCancelled` of a message cancelled. While the
  /// server's answer is in flight an item drops from the message all the
  /// same (whether the server used it is its own concern), and a cancel of
  /// the message waits as [cancel]'s does. An item of a job that ended (a
  /// failed message) cannot leave it ([OutgoingCancelOutcome.unknown]):
  /// the host deletes the message instead.
  ///
  /// Guarded as [cancel] is, per item. Reports `itemDropped` (trigger
  /// `cross`), `awaitingOwner`, `cancelled` (trigger `onlyItem` or
  /// `lastItemNoText`), `cancelTooLate` or `actionDropped`.
  OutgoingCancelOutcome cancelItem(
    String chatId,
    String clientMessageId,
    MediaItemId itemId,
  ) {
    _checkNotDisposed();
    if (_repeated(chatId, clientMessageId, null) ||
        _repeated(chatId, clientMessageId, '$itemId')) {
      return OutgoingCancelOutcome.dropped;
    }
    final message = switch (_projection.lookup(chatId, clientMessageId)) {
      final message? => _current(message),
      null => null,
    };
    final index = message?.items.indexWhere((item) => item.id == itemId) ?? -1;
    if (message == null || index < 0) return OutgoingCancelOutcome.unknown;
    if (_tooLate(message)) return OutgoingCancelOutcome.tooLate;
    final key = (chatId, clientMessageId);
    final hasText = _projection.hasText(chatId, clientMessageId);
    if (message.items.length == 1 && !hasText) {
      return _cancelMessage(
        chatId,
        clientMessageId,
        trigger: _$itemsDropped.contains(key)
            ? _Trigger.lastItemNoText
            : _Trigger.onlyItem,
      );
    }
    final job = _projection.jobOf(chatId, clientMessageId);
    if (job == null || !_transfers.removeItem(job.id, '$itemId')) {
      return OutgoingCancelOutcome.unknown;
    }
    _$cancelsAccepted[(chatId, clientMessageId, '$itemId')] = _now();
    final left = _dropItem(message, index, trigger: _Trigger.cross);
    if (left.items.isEmpty) _awaitingOwner(left, job.id);
    return OutgoingCancelOutcome.itemDropped;
  }

  OutgoingCancelOutcome _cancelMessage(
    String chatId,
    String clientMessageId, {
    required _Trigger trigger,
  }) {
    final (outcome, now) = _admitCancel(chatId, clientMessageId, trigger);
    if (now != null) _cancelNow([now], trigger);
    return outcome;
  }

  /// Admits a cancel of the message [clientMessageId] of [chatId]: answers
  /// the outcome, and the message to cancel now when it is
  /// [OutgoingCancelOutcome.cancelled]. A message whose server answer is in
  /// flight is cancelled once it comes, unless it is an accept.
  (OutgoingCancelOutcome, OutgoingMessage?) _admitCancel(
    String chatId,
    String clientMessageId,
    _Trigger trigger,
  ) {
    if (_repeated(
      chatId,
      clientMessageId,
      null,
      action: trigger == _Trigger.delete ? 'delete' : 'cancel',
    )) {
      return (OutgoingCancelOutcome.dropped, null);
    }
    final message = switch (_projection.lookup(chatId, clientMessageId)) {
      final message? => _current(message),
      null => null,
    };
    if (message == null) return (OutgoingCancelOutcome.unknown, null);
    if (_tooLate(message)) return (OutgoingCancelOutcome.tooLate, null);
    _$cancelsAccepted[(chatId, clientMessageId, null)] = _now();
    final key = (chatId, clientMessageId);
    if (_projection.sending.contains(key)) {
      // The server may be accepting it now: the publisher runs the cancel
      // once it answers, unless the answer is an accept.
      _projection.cancelRequests[key] = () {
        if (_projection.lookup(chatId, clientMessageId) case final message?) {
          _cancelNow([_current(message)], trigger);
        }
      };
      return (OutgoingCancelOutcome.pending, null);
    }
    return (OutgoingCancelOutcome.cancelled, message);
  }

  /// Whether [message] is past cancelling, the server having accepted it;
  /// reports `cancelTooLate` when it is.
  bool _tooLate(OutgoingMessage message) {
    final accepted = _projection.accepted.contains((
      message.chatId,
      message.clientMessageId,
    ));
    final sent = message.status is OutgoingStatus$Sent;
    if (!accepted && !sent) return false;
    _$tooLate++;
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.outbox,
      OutboxOp.cancelTooLate,
      correlation: ChatCorrelation(
        chatId: message.chatId,
        clientMessageId: message.clientMessageId,
        jobId: _projection.jobOf(message.chatId, message.clientMessageId)?.id,
      ),
      fields: () => {'stage': sent ? 'sent' : 'publish'},
    );
    return true;
  }

  /// Whether a cancel (or a delete, the [action] reported) of the message
  /// ([itemId] null) or of its item [itemId] was accepted already; reports
  /// `actionDropped` when it was.
  bool _repeated(
    String chatId,
    String clientMessageId,
    String? itemId, {
    String action = 'cancel',
  }) {
    final accepted = _$cancelsAccepted[(chatId, clientMessageId, itemId)];
    if (accepted == null) return false;
    _reportDropped(chatId, clientMessageId, itemId, action, accepted);
    return true;
  }

  void _reportDropped(
    String chatId,
    String clientMessageId,
    String? itemId,
    String action,
    DateTime accepted,
  ) => ChatDiagnostics.current.emit(
    ChatEventLevel.debug,
    ChatEventCategory.outbox,
    OutboxOp.actionDropped,
    correlation: ChatCorrelation(
      chatId: chatId,
      clientMessageId: clientMessageId,
      mediaItemId: itemId,
    ),
    fields: () => {
      'action': action,
      'msSinceAccepted': _now().difference(accepted).inMilliseconds,
    },
  );

  /// Cancels the jobs of [messages], all of one chat, and makes the
  /// messages Absent, their rows leaving the tail in one `rebaseTail`.
  void _cancelNow(List<OutgoingMessage> messages, _Trigger trigger) {
    if (messages.isEmpty) return;
    final chatId = messages.first.chatId;
    final jobs = [
      for (final message in messages)
        _projection.jobOf(chatId, message.clientMessageId),
    ];
    for (final job in jobs) {
      // The engine may have dropped the job already (it lost its last item,
      // ended, or the envelope's cancel of all took it); the message goes
      // all the same.
      if (job != null) _transfers.cancel(job.id);
    }
    final rowsRemoved =
        _$strategies[chatId]?.removeAll([
          for (final message in messages) message.clientMessageId,
        ]) ??
        const <String>{};
    for (final (index, message) in messages.indexed) {
      final clientMessageId = message.clientMessageId;
      final job = jobs[index];
      _projection.remove(chatId, clientMessageId);
      if (job != null) _$interrupted.remove(job.id);
      _$itemsDropped.remove((chatId, clientMessageId));
      _$retriesAccepted.remove((chatId, clientMessageId));
      _$cancelsAccepted[(chatId, clientMessageId, null)] ??= _now();
      _$cancels++;
      ChatDiagnostics.current.emit(
        ChatEventLevel.info,
        ChatEventCategory.outbox,
        OutboxOp.cancelled,
        correlation: ChatCorrelation(
          chatId: chatId,
          clientMessageId: clientMessageId,
          jobId: job?.id,
        ),
        fields: () => {
          'trigger': trigger.name,
          'stage': switch (message.status) {
            OutgoingStatus$Preparing() => PublishStage.prepare.name,
            OutgoingStatus$Uploading() => PublishStage.upload.name,
            OutgoingStatus$Publishing() => PublishStage.publish.name,
            final status => status.name,
          },
        },
      );
      if (trigger == _Trigger.delete) {
        ChatDiagnostics.current.emit(
          ChatEventLevel.info,
          ChatEventCategory.outbox,
          OutboxOp.deleted,
          correlation: ChatCorrelation(
            chatId: chatId,
            clientMessageId: clientMessageId,
            jobId: job?.id,
          ),
          fields: () => {'status': message.status.name},
        );
      }
    }
    _syncInFlight(chatId);
    for (final message in messages) {
      _onCancelled?.call(
        OutgoingCancelled(
          message: message.withStatus(const OutgoingStatus.cancelled()),
          rowRemoved: rowsRemoved.contains(message.clientMessageId),
        ),
      );
    }
  }

  /// Takes item [index] out of [message] and answers the message without
  /// it; reports `itemDropped` and tells the host.
  OutgoingMessage _dropItem(
    OutgoingMessage message,
    int index, {
    required _Trigger trigger,
  }) {
    final item = message.items[index];
    final left = OutgoingMessage(
      chatId: message.chatId,
      clientMessageId: message.clientMessageId,
      position: message.position,
      status: message.status,
      payload: message.payload,
      items: [...message.items]..removeAt(index),
    );
    _projection.put(left);
    _$itemsDropped.add((message.chatId, message.clientMessageId));
    _$droppedItems++;
    final hasText = _projection.hasText(
      message.chatId,
      message.clientMessageId,
    );
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.outbox,
      OutboxOp.itemDropped,
      correlation: ChatCorrelation(
        chatId: message.chatId,
        clientMessageId: message.clientMessageId,
        jobId: _projection.jobOf(message.chatId, message.clientMessageId)?.id,
        mediaItemId: '${item.id}',
        mediaKey: switch (_projection.mediaKeyOf(item.id)) {
          // An external key's id may be a URL, which is user content.
          MediaKey$External() => 'external',
          final key? => key.encoded,
          null => null,
        },
      ),
      fields: () => {
        'index': index,
        'itemsLeft': left.items.length,
        'hasText': hasText,
        'trigger': trigger.name,
      },
    );
    _onItemDropped?.call(
      OutgoingItemDropped(message: left, item: item, index: index),
    );
    return left;
  }

  /// [message]'s job [jobId] lost its last item and waits for the outbox:
  /// a message with text publishes it alone, joining the end of the chat's
  /// sending messages as the job joins the end of its ordering group; one
  /// without is cancelled. Reports `awaitingOwner`.
  void _awaitingOwner(
    OutgoingMessage message,
    PublishJobId jobId, {
    _Trigger trigger = _Trigger.lastItemNoText,
  }) {
    final OutgoingMessage(:chatId, :clientMessageId) = message;
    final hasText = _projection.hasText(chatId, clientMessageId);
    // While the publisher's call is in flight the job is the server's
    // answer's to end: committing it then would publish it twice.
    final inFlight = _projection.sending.contains((chatId, clientMessageId));
    final action = switch ((hasText, inFlight)) {
      (_, true) => _OwnerAction.none,
      (true, false) => _OwnerAction.commit,
      (false, false) => _OwnerAction.cancel,
    };
    ChatDiagnostics.current.emit(
      ChatEventLevel.warning,
      ChatEventCategory.outbox,
      OutboxOp.awaitingOwner,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        jobId: jobId,
      ),
      fields: () => {
        'itemsLeft': message.items.length,
        'hasText': hasText,
        'action': action.name,
      },
    );
    _$committed.add(jobId);
    switch (action) {
      case _OwnerAction.commit:
        _transfers.commit(jobId);
        _$strategies[chatId]?.retry(clientMessageId);
      case _OwnerAction.cancel:
        _cancelMessage(chatId, clientMessageId, trigger: trigger);
      case _OwnerAction.none:
        break;
    }
  }

  // --- Retry and delete ------------------------------------------------------

  /// Retries the failed message [clientMessageId] of [chatId] (the message
  /// menu's Retry): its job repeats only what failed, and its row joins the
  /// end of the sending rows, above the rows still failed, as the job joins
  /// the end of the chat's ordering group.
  ///
  /// | Failed at | Repeats |
  /// | --- | --- |
  /// | prepare | the preparation of each failed item |
  /// | upload | each failed upload, from the parts it journaled |
  /// | publish | the publish alone, with the same client message id; nothing uploads |
  ///
  /// A denied message retries as any other: the server answers again (a
  /// host whose platform offers only Delete for a denial does not show
  /// Retry). A message restored with a payload the codec cannot read is not
  /// retried ([OutgoingRetryOutcome.undecodable]): only [delete] helps it.
  ///
  /// [sources] is the host's way back from a lost source
  /// (`OutgoingFailure.sourceLost`, a web reload that kept no copy of a
  /// file): the host asks the user for the file again and passes its bytes
  /// by item id, and each such item uploads again from zero. Throws an
  /// [ArgumentError] for an id that is not one of the message's items.
  ///
  /// Guarded against a burst: once a retry is accepted, another changes
  /// nothing ([OutgoingRetryOutcome.dropped]) until the message fails again.
  /// Reports `retried`, `tailRebased` (reason `retry`) or `actionDropped`.
  OutgoingRetryOutcome retry(
    String chatId,
    String clientMessageId, {
    Map<MediaItemId, SourceBytes> sources = const {},
  }) {
    _checkNotDisposed();
    final key = (chatId, clientMessageId);
    if (_$retriesAccepted[key] case final accepted?) {
      _reportDropped(chatId, clientMessageId, null, 'retry', accepted);
      return OutgoingRetryOutcome.dropped;
    }
    final message = switch (_projection.lookup(chatId, clientMessageId)) {
      final message? => _current(message),
      null => null,
    };
    if (message == null) return OutgoingRetryOutcome.unknown;
    if (_projection.isUndecodable(chatId, clientMessageId)) {
      return OutgoingRetryOutcome.undecodable;
    }
    if (message.status is! OutgoingStatus$Failed) {
      return OutgoingRetryOutcome.notFailed;
    }
    for (final id in sources.keys) {
      if (!message.items.any((item) => item.id == id)) {
        throw ArgumentError.value(id, 'sources', 'Not an item of the message.');
      }
    }
    final job = _projection.jobOf(chatId, clientMessageId);
    if (job == null) return OutgoingRetryOutcome.unknown;
    // The items given a source first, each from its new bytes; then whatever
    // else failed, which a job failed by those items alone no longer has.
    var reopened = false;
    for (final MapEntry(key: id, value: source) in sources.entries) {
      reopened =
          _transfers.retryItem(job.id, '$id', source: source) || reopened;
    }
    reopened = _transfers.retry(job.id) || reopened;
    if (!reopened) return OutgoingRetryOutcome.unknown;
    _$retriesAccepted[key] = _now();
    _$retries++;
    final stage = job.stage ?? PublishStage.publish;
    // The job's stage at once, not at its next snapshot: a repeat failure
    // then reads as a new one, and the row sinks again.
    final retried = message.withStatus(switch (stage) {
      PublishStage.prepare => const OutgoingStatus.preparing(),
      PublishStage.upload => const OutgoingStatus.uploading(),
      PublishStage.publish => const OutgoingStatus.publishing(),
    });
    _projection.put(retried);
    _$strategies[chatId]?.retry(clientMessageId);
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.outbox,
      OutboxOp.retried,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        jobId: job.id,
      ),
      fields: () => {
        'stage': stage.name,
        'uploadsKept': sources.isEmpty,
        'newSources': sources.length,
      },
    );
    _syncInFlight(chatId);
    _onStatusChanged?.call(_current(retried));
    return OutgoingRetryOutcome.retried;
  }

  /// Deletes the outgoing message [clientMessageId] of [chatId] (the
  /// message menu's Delete, a failed message's way out): its job is
  /// cancelled and the message becomes Absent, its row leaving the
  /// provisional tail, as [cancel] does; the host's `onCancelled` hears of
  /// it. A message the server accepted stays sent
  /// ([OutgoingCancelOutcome.tooLate]), for the host to delete as any sent
  /// message.
  ///
  /// Guarded against a burst as [cancel] is. Reports `cancelled` (trigger
  /// `delete`) and `deleted`, or `cancelTooLate` or `actionDropped`.
  OutgoingCancelOutcome delete(String chatId, String clientMessageId) {
    _checkNotDisposed();
    return _cancelMessage(chatId, clientMessageId, trigger: _Trigger.delete);
  }

  // --- Restart ---------------------------------------------------------------

  /// The outgoing messages of [chatId] still on their way or failed, in
  /// tail order: after a restart, read back from the engine's publish jobs.
  ///
  /// The outbox keeps nothing of its own, so the first call per chat
  /// restores the chat from the jobs under its tag prefix: each message
  /// takes a fresh tail position from the chat's id strategy, the sending
  /// ones first in creation order, then the failed ones below them in
  /// creation order, and the strategy inserts the host's row for each. A
  /// sending message goes on (a job waiting for its publisher waits until
  /// [registerSender]); a failed one waits for the user. A completed job is
  /// not pending: the server has its message. Later calls answer the
  /// messages as they are now.
  ///
  /// Each payload decodes through the host's codec into the model its row
  /// is built from. A payload the codec cannot read gives a message failed
  /// for an unknown reason, with the row `undecodableRowOf` builds; without
  /// that builder it is left out. A job under the prefix whose tag names no
  /// client message id is left alone.
  ///
  /// The host's duty: call it for a chat before the chat's first send in
  /// this run, so the restored rows sit above the new ones; and for every
  /// chat it may hold messages of, since a job whose chat is not restored
  /// waits at its publish stage until it is. Reports `restored`,
  /// `positionAllocated` per message, `payloadDecodeFailed` and
  /// `foreignJob`. Throws a [StateError] when a restored message has items
  /// and the outbox was made without `localKeyOf`.
  Future<List<OutgoingMessage>> pendingFor(String chatId) async {
    _checkNotDisposed();
    final restore = _$restores[chatId] ??= _restore(chatId);
    try {
      await restore;
    } on Object {
      // A restore that failed runs again on the next call.
      if (identical(_$restores[chatId], restore)) {
        unawaited(_$restores.remove(chatId));
      }
      rethrow;
    }
    return [
      for (final message in _projection.tailOf(chatId))
        if (_isPending(message.status)) _current(message),
    ]..sort((a, b) => a.position.compareTo(b.position));
  }

  static bool _isPending(OutgoingStatus status) => switch (status) {
    OutgoingStatus$Preparing() ||
    OutgoingStatus$Uploading() ||
    OutgoingStatus$Publishing() ||
    OutgoingStatus$Failed() => true,
    OutgoingStatus$Sent() || OutgoingStatus$Cancelled() => false,
  };

  Future<void> _restore(String chatId) async {
    final jobs = await _transfers
        .watchJobs(
          PublishJobFilter(
            tagPrefix: tagPrefixOf(chatId),
            publisher: publisherId,
          ),
        )
        .first;
    if (_$disposed) return;
    final prefix = tagPrefixOf(chatId);
    final sending = <_Restored<M>>[];
    final failed = <_Restored<M>>[];
    var awaitingPublisher = 0;
    for (final job in [...jobs]..sort(_byCreation)) {
      final tag = job.tag;
      if (tag == null || !tag.startsWith(prefix)) continue;
      final clientMessageId = tag.substring(prefix.length);
      if (clientMessageId.isEmpty || clientMessageId.contains(':')) {
        _reportForeign(
          chatId,
          job.id,
          why: clientMessageId.isEmpty ? 'emptyId' : 'separator',
        );
        continue;
      }
      if (job.items.any((item) => MediaItemId.tryParse(item.itemId) == null)) {
        _reportForeign(chatId, job.id, why: 'itemId');
        continue;
      }
      if (job.state case PublishJobState$Completed()) continue;
      // A message this run sent is already here.
      if (_projection.lookup(chatId, clientMessageId) != null) continue;
      final restored = _restoredOf(chatId, clientMessageId, job);
      if (restored == null) continue;
      switch (restored.message.status) {
        case OutgoingStatus$Failed():
          failed.add(restored);
        case _:
          sending.add(restored);
          if (job.state case PublishJobState$AwaitingPublisher()) {
            awaitingPublisher++;
          }
      }
    }
    final strategy = idStrategy(chatId);
    for (final (index, restored) in [...sending, ...failed].indexed) {
      final _Restored(:message, :model, :job) = restored;
      final IChatMessage Function(OutgoingMessage message) rowOf;
      switch (model) {
        case (final model,):
          rowOf = (message) => _rowOf(message, model);
        case null:
          final undecodableRowOf = _undecodableRowOf;
          if (undecodableRowOf == null) continue;
          rowOf = undecodableRowOf;
      }
      final position = strategy.allocate(
        message.clientMessageId,
        (position) => rowOf(message.withPosition(position)),
        failed: index >= sending.length,
        restored: true,
      );
      _projection.put(message.withPosition(position), job: job);
      if (model == null) {
        _projection.markUndecodable(chatId, message.clientMessageId);
      }
      _$restored++;
    }
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.outbox,
      OutboxOp.restored,
      correlation: ChatCorrelation(chatId: chatId),
      fields: () => {
        'sending': sending.length,
        'failed': failed.length,
        'awaitingPublisher': awaitingPublisher,
      },
    );
    _watch(chatId);
    _syncInFlight(chatId);
    for (final restored in [...sending, ...failed]) {
      final clientMessageId = restored.message.clientMessageId;
      _$restoreWaiters
          .remove(clientMessageId)
          ?.complete(_projection.lookup(chatId, clientMessageId));
    }
  }

  static int _byCreation(PublishJobSnapshot a, PublishJobSnapshot b) =>
      a.createdAt.compareTo(b.createdAt);

  /// The message of [job] as its journal holds it, its payload decoded; null
  /// when the engine no longer has the job.
  _Restored<M>? _restoredOf(
    String chatId,
    String clientMessageId,
    PublishJobSnapshot job,
  ) {
    final payload = _transfers.payloadOf(job.id);
    if (payload == null) return null;
    final (status: projected, :stage) = JobProjection.of(
      job,
      const OutgoingStatus.publishing(),
    );
    (M,)? model;
    try {
      model = (_codec.decode(payload),);
    } on Object catch (error) {
      // The error may quote the payload: only its type.
      ChatDiagnostics.current.emit(
        ChatEventLevel.error,
        ChatEventCategory.outbox,
        OutboxOp.payloadDecodeFailed,
        correlation: ChatCorrelation(
          chatId: chatId,
          clientMessageId: clientMessageId,
          jobId: job.id,
        ),
        fields: () => {
          'errorType': '${error.runtimeType}',
          'payloadBytes': payload.length,
        },
      );
    }
    final items = [
      for (final item in job.items)
        if (item.state is! PublishItemState$Removed)
          OutgoingItem(
            id: MediaItemId.parse(item.itemId),
            localKey: switch (_localKeyOf) {
              final localKeyOf? => localKeyOf(item.key),
              null => throw StateError(
                'A restored message has items: the outbox needs localKeyOf.',
              ),
            },
          ),
    ];
    return _Restored(
      message: OutgoingMessage(
        chatId: chatId,
        clientMessageId: clientMessageId,
        // A stand-in until the strategy places the row.
        position: 0,
        status: model == null
            ? const OutgoingStatus.failed(OutgoingFailure.unknown())
            : projected,
        payload: payload,
        items: items,
      ),
      model: model,
      job: OutboxJobView(job.id, state: job.state.name, stage: stage),
    );
  }

  static void _reportForeign(
    String chatId,
    PublishJobId jobId, {
    required String why,
  }) => ChatDiagnostics.current.emit(
    ChatEventLevel.warning,
    ChatEventCategory.outbox,
    OutboxOp.foreignJob,
    correlation: ChatCorrelation(chatId: chatId, jobId: jobId),
    fields: () => {'why': why},
  );

  /// The message [clientMessageId] once a restore places it, for the
  /// publisher's call of a job from an earlier run; null when this run will
  /// not hold it (the outbox was disposed, or its restore left it out).
  Future<OutgoingMessage?> _restoredMessage(String clientMessageId) {
    if (_projection.find(clientMessageId) case final message?) {
      return Future.value(message);
    }
    if (_$disposed) return Future.value();
    return _$restoreWaiters.putIfAbsent(clientMessageId, Completer.new).future;
  }

  // --- Status projection -----------------------------------------------------

  void _watch(String chatId) {
    if (_$watches.containsKey(chatId)) return;
    _$watches[chatId] = _transfers
        .watchJobs(
          PublishJobFilter(
            tagPrefix: tagPrefixOf(chatId),
            publisher: publisherId,
          ),
        )
        .listen((jobs) => _project(chatId, jobs));
  }

  void _project(String chatId, List<PublishJobSnapshot> jobs) {
    if (_$disposed) return;
    _projection.origins.expire(_now());
    OutboxTrace.project.run(() {
      final prefix = tagPrefixOf(chatId);
      for (final job in jobs) {
        final clientMessageId = switch (job.tag) {
          final tag? when tag.startsWith(prefix) => tag.substring(
            prefix.length,
          ),
          _ => null,
        };
        // A client message id never holds `:`: a tag with one past the
        // prefix is a job of a chat whose id extends this one's.
        if (clientMessageId == null || clientMessageId.contains(':')) continue;
        _projectJob(chatId, clientMessageId, job);
      }
      _projectRemovals(chatId, jobs);
    });
    _syncInFlight(chatId);
  }

  /// Deletes each message of [chatId] whose job left [jobs] without the
  /// outbox cancelling it: the user cancelled every job of the system's
  /// transfer envelope from its notification or progress UI, and the
  /// engine removed them. (A cancel of the outbox's own makes its message
  /// Absent first, so its job's leaving finds nothing here.)
  ///
  /// Only a job seen in an earlier snapshot counts as gone: a snapshot the
  /// engine sent before a new job was made may arrive after the send, and
  /// it would read as the new job's removal. A sent message stays sent
  /// when its job leaves (the engine forgets a completed job after a while).
  void _projectRemovals(String chatId, List<PublishJobSnapshot> jobs) {
    final present = {for (final job in jobs) job.id};
    for (final message in _projection.tailOf(chatId)) {
      if (message.status is OutgoingStatus$Sent) continue;
      final job = _projection.jobOf(chatId, message.clientMessageId);
      if (job == null || job.state == null || present.contains(job.id)) {
        continue;
      }
      _leaveSoon(
        chatId,
        message.clientMessageId,
        _Trigger.notificationCancelAll,
      );
    }
  }

  /// Follows the system's end of the transfer envelope for [message]'s
  /// [job]: reports `systemInterrupted` once when the job pauses for it,
  /// and deletes the message when [deleteOnSystemInterruption] says so;
  /// reports `resumed` once the job goes on.
  ///
  /// A kept message needs nothing more: the paused job reads as its stage
  /// (`JobProjection`), so it keeps sending.
  void _followInterruption(OutgoingMessage message, PublishJobSnapshot job) {
    final correlation = ChatCorrelation(
      chatId: message.chatId,
      clientMessageId: message.clientMessageId,
      jobId: job.id,
    );
    switch (job.state) {
      case PublishJobState$Paused(reason: PauseReason.systemInterrupted):
        if (!_$interrupted.add(job.id)) return;
        ChatDiagnostics.current.emit(
          ChatEventLevel.info,
          ChatEventCategory.outbox,
          OutboxOp.systemInterrupted,
          correlation: correlation,
          fields: () => {
            'action': deleteOnSystemInterruption ? 'deleted' : 'kept',
          },
        );
        if (deleteOnSystemInterruption) {
          _leaveSoon(
            message.chatId,
            message.clientMessageId,
            _Trigger.systemInterruption,
          );
        }
      case PublishJobState$Preparing() ||
              PublishJobState$Uploading() ||
              PublishJobState$Publishing() ||
              PublishJobState$AwaitingPublisher()
          when _$interrupted.remove(job.id):
        final (status: _, :stage) = JobProjection.of(job, message.status);
        ChatDiagnostics.current.emit(
          ChatEventLevel.info,
          ChatEventCategory.outbox,
          OutboxOp.resumed,
          correlation: correlation,
          fields: () => {'stage': ?stage?.name},
        );
      case _:
        // Paused for another reason, or ended: not a resume.
        if (job.state is! PublishJobState$Paused) _$interrupted.remove(job.id);
    }
  }

  /// Deletes the message [clientMessageId] of [chatId] for [trigger] once
  /// the snapshots the engine sent in one burst are read: a cancel of all,
  /// or the system's end of the envelope, reaches every job in it one
  /// snapshot at a time, and the chat's messages then leave together, their
  /// rows in one `rebaseTail`.
  ///
  /// The engine sends that burst within one turn of the event loop, its
  /// snapshots delivered as microtasks; a zero timer runs after all of
  /// them, where a microtask would run between two.
  void _leaveSoon(String chatId, String clientMessageId, _Trigger trigger) {
    (_$leaving[chatId] ??= {})[clientMessageId] ??= trigger;
    _$leavingFlush ??= Timer(Duration.zero, _leave);
  }

  void _leave() {
    _$leavingFlush = null;
    if (_$disposed) return;
    final leaving = {..._$leaving};
    _$leaving.clear();
    for (final MapEntry(key: chatId, value: messages) in leaving.entries) {
      for (final trigger in {...messages.values}) {
        final now = <OutgoingMessage>[];
        var pending = 0;
        for (final MapEntry(key: clientMessageId, value: of)
            in messages.entries) {
          if (of != trigger) continue;
          switch (_admitCancel(chatId, clientMessageId, trigger)) {
            case (OutgoingCancelOutcome.cancelled, final message?):
              now.add(message);
            case (OutgoingCancelOutcome.pending, _):
              pending++;
            case _:
              break;
          }
        }
        _cancelNow(now, trigger);
        if (trigger == _Trigger.notificationCancelAll) {
          ChatDiagnostics.current.emit(
            ChatEventLevel.info,
            ChatEventCategory.outbox,
            OutboxOp.envelopeCancelAll,
            correlation: ChatCorrelation(chatId: chatId),
            fields: () => {'deleted': now.length, 'pending': pending},
          );
        }
      }
    }
  }

  void _projectJob(
    String chatId,
    String clientMessageId,
    PublishJobSnapshot job,
  ) {
    final message = switch (_projection.lookup(chatId, clientMessageId)) {
      final message? => _current(message),
      null => null,
    };
    // A job this outbox did not make in this run (a restart's) is not
    // projected here.
    if (message == null ||
        _projection.jobOf(chatId, clientMessageId)?.id != job.id) {
      return;
    }
    _followInterruption(message, job);
    final kept = _dropRemovedItems(message, job);
    if (job.state is PublishJobState$AwaitingOwner &&
        kept.items.isEmpty &&
        !_$committed.contains(job.id)) {
      _awaitingOwner(kept, job.id, trigger: _Trigger.statusControl);
      if (_projection.lookup(chatId, clientMessageId) == null) return;
    }
    _projectStatus(chatId, clientMessageId, kept, job);
  }

  /// Drops from [message] each item [job] no longer lists: an item a
  /// cell's status control cancelled the upload of, which the engine took
  /// out of the job. Answers the message as it is left.
  OutgoingMessage _dropRemovedItems(
    OutgoingMessage message,
    PublishJobSnapshot job,
  ) {
    final inJob = {for (final item in job.items) item.itemId};
    final emptied = !message.items.any((item) => inJob.contains('${item.id}'));
    if (message.items.isNotEmpty &&
        emptied &&
        job.state is PublishJobState$AwaitingOwner &&
        !_projection.hasText(message.chatId, message.clientMessageId)) {
      // Nothing is left to send: the message is cancelled as a whole, and
      // its items go with it, not one by one.
      return OutgoingMessage(
        chatId: message.chatId,
        clientMessageId: message.clientMessageId,
        position: message.position,
        status: message.status,
        payload: message.payload,
      );
    }
    var left = message;
    for (var index = left.items.length - 1; index >= 0; index--) {
      if (inJob.contains('${left.items[index].id}')) continue;
      left = _dropItem(left, index, trigger: _Trigger.statusControl);
    }
    return left;
  }

  void _projectStatus(
    String chatId,
    String clientMessageId,
    OutgoingMessage message,
    PublishJobSnapshot job,
  ) {
    final (status: projected, :stage) = JobProjection.of(job, message.status);
    // A message whose payload did not decode stays failed: its row cannot
    // show it sending, and its publish fails at the decode anyway.
    final status = _projection.isUndecodable(chatId, clientMessageId)
        ? message.status
        : projected;
    final changed = status != message.status;
    _projection.put(
      changed ? message.withStatus(status) : message,
      job: OutboxJobView(job.id, state: job.state.name, stage: stage),
    );
    if (!changed) return;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.statusChanged,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        jobId: job.id,
        scrollId: '${message.position}',
      ),
      fields: () => {
        'from': message.status.name,
        'to': status.name,
        'jobState': job.state.name,
        'stage': ?stage?.name,
      },
    );
    if ((message.status, status, stage) case (
      OutgoingStatus$Preparing() ||
          OutgoingStatus$Uploading() ||
          OutgoingStatus$Publishing(),
      OutgoingStatus$Failed(:final failure),
      final stage?,
    )) {
      _failed(message, failure, stage, job);
    }
    if (_projection.lookup(chatId, clientMessageId) case final current?) {
      _onStatusChanged?.call(_current(current));
    }
  }

  /// [message]'s job failed at [stage] for [failure]: its row sinks below
  /// every sending row, and a retry of it may be accepted again. Reports
  /// `failed`.
  void _failed(
    OutgoingMessage message,
    OutgoingFailure failure,
    PublishStage stage,
    PublishJobSnapshot job,
  ) {
    final OutgoingMessage(:chatId, :clientMessageId) = message;
    _$retriesAccepted.remove((chatId, clientMessageId));
    _$strategies[chatId]?.fail(clientMessageId);
    ChatDiagnostics.current.emit(
      ChatEventLevel.warning,
      ChatEventCategory.outbox,
      OutboxOp.failed,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        jobId: job.id,
      ),
      fields: () => {
        'reason': failure.name,
        'stage': stage.name,
        'itemsFailed': job.items
            .where((item) => item.state is PublishItemState$Failed)
            .length,
      },
    );
  }

  void _syncInFlight(String chatId) {
    final inFlight = _projection.hasInFlight(chatId);
    if ((_$inFlight[chatId] ?? false) == inFlight) return;
    _$inFlight[chatId] = inFlight;
    _$inFlightNotifiers[chatId]?.value = inFlight;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.sendInFlight,
      correlation: ChatCorrelation(chatId: chatId),
      fields: () => {'on': inFlight},
    );
  }

  // --- Lookups ---------------------------------------------------------------

  /// The outgoing message [clientMessageId] of [chatId], or null when there
  /// is none (never sent from here, or Absent: cancelled or deleted).
  ///
  /// The host calls it when the server's echo of a message arrives: a match
  /// is the host's own message, which it settles in place instead of
  /// inserting a twin row. Reports `echoMatched`.
  OutgoingMessage? byClientMessageId(String chatId, String clientMessageId) {
    final message = switch (_projection.lookup(chatId, clientMessageId)) {
      final message? => _current(message),
      null => null,
    };
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.echoMatched,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        scrollId: switch (message) {
          final message? => '${message.position}',
          null => null,
        },
      ),
      fields: () => {
        'matched': message != null,
        if (message case final message?) 'status': message.status.name,
      },
    );
    return message;
  }

  /// Whether the outgoing row [clientMessageId] of [chatId] is new, so the
  /// host animates its appearance: true once per message the user just
  /// sent, false on every later call and for any other message.
  ///
  /// The whole-row animation is the host's, since it owns the row. Reports
  /// `freshOutgoingTaken`.
  bool isFreshOutgoing(String chatId, String clientMessageId) {
    final fresh = _projection.takeFresh(chatId, clientMessageId);
    ChatDiagnostics.current.emit(
      ChatEventLevel.trace,
      ChatEventCategory.outbox,
      OutboxOp.freshOutgoingTaken,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
      ),
      fields: () => {'answered': fresh},
    );
    return fresh;
  }

  /// What the outbox holds for [chatId] right now, without user content;
  /// see [OutboxDebugSnapshot].
  ///
  /// Reading it changes nothing: a row's fresh flag stays unread, a
  /// chat with no strategy yet gets none, and an origin it shows as
  /// held is still there to take (it drops the expired ones first, as
  /// every call does).
  OutboxDebugSnapshot debugSnapshot(String chatId) {
    _projection.origins.expire(_now());
    final strategy = _$strategies[chatId];
    final messages = [
      for (final message in _projection.tailOf(chatId)) _current(message),
    ]..sort((a, b) => a.position.compareTo(b.position));
    return OutboxDebugSnapshot(
      chatId: chatId,
      strategy: strategy?.name,
      tip: strategy?.tip,
      tail: [
        for (final message in messages)
          OutboxDebugRow.of(
            message,
            fresh: _projection.isFresh(chatId, message.clientMessageId),
            job: _projection.jobOf(chatId, message.clientMessageId),
            sendOriginHeld: _projection.origins.holds,
            attempts: _$publishCounters.attemptsOf(
              chatId,
              message.clientMessageId,
            ),
          ),
      ],
      publisherRegistered: _$senderRegistered,
      sendInFlight: _projection.hasInFlight(chatId),
      counters: OutboxDebugCounters(
        accepted: _$accepted,
        rebases: strategy?.rebases ?? const {},
        conflicts: _$publishCounters.conflicts,
        retries: _$retries,
        cancels: _$cancels,
        itemsDropped: _$droppedItems,
        cancelsTooLate: _$tooLate + _$publishCounters.cancelsTooLate,
        restores: _$restored,
      ),
    );
  }

  // --- Lifecycle -------------------------------------------------------------

  /// Stops watching every chat's jobs and disposes the [sendInFlight]
  /// listenables. The jobs run on in the engine. Idempotent; [send] throws
  /// a [StateError] afterwards.
  Future<void> dispose() async {
    if (_$disposed) return;
    _$disposed = true;
    _$leavingFlush?.cancel();
    _$leavingFlush = null;
    _$leaving.clear();
    final watches = [..._$watches.values];
    _$watches.clear();
    for (final notifier in _$inFlightNotifiers.values) {
      notifier.dispose();
    }
    _$inFlightNotifiers.clear();
    for (final waiter in _$restoreWaiters.values) {
      waiter.complete(null);
    }
    _$restoreWaiters.clear();
    await Future.wait([for (final watch in watches) watch.cancel()]);
  }

  void _checkNotDisposed() {
    if (_$disposed) throw StateError('The outbox was disposed.');
  }

  static final Random _$random = Random.secure();

  static String _$randomClientMessageId() => [
    for (var i = 0; i < 16; i++)
      _$random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Who asked for a cancel: the `trigger` of a `cancelled` or `itemDropped`
/// event.
enum _Trigger {
  /// The message menu's cancel.
  menu,

  /// The cross on the message's only item, with no text.
  onlyItem,

  /// The cross on the last item left of an album, with no text.
  lastItemNoText,

  /// The cross on one item of a message that goes on.
  cross,

  /// A cell's status control cancelled an item's upload, which the engine
  /// took out of the job.
  statusControl,

  /// The message menu's delete (a failed message's way out).
  delete,

  /// The system ended the transfer envelope, and the host asked for the
  /// message to be deleted then.
  systemInterruption,

  /// The user cancelled every job of the transfer envelope from the
  /// system's UI (its notification, or the progress it shows).
  notificationCancelAll,
}

/// What the outbox does with a job that lost its last item.
enum _OwnerAction {
  /// The text publishes alone.
  commit,

  /// Nothing is left to send: the message is cancelled.
  cancel,

  /// The publisher's call is in flight and ends the job.
  none,
}

/// One message read back from its job by a restore, before its row is
/// placed: its decoded model (null when the payload did not decode) and its
/// job as seen.
final class _Restored<M> {
  _Restored({required this.message, required this.model, required this.job});

  final OutgoingMessage message;
  final (M,)? model;
  final OutboxJobView job;
}

/// Builds the host's row for an accepted outgoing [message], at
/// `message.position`, from its message model [payload]: the row the
/// chat's id strategy inserts, for which the data source's `identityOf`
/// answers the message's client message id.
typedef OutgoingRowBuilder<M> =
    IChatMessage Function(OutgoingMessage message, M payload);
