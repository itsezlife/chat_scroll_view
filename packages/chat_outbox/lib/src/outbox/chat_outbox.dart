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
  }) : _onCancelled = onCancelled,
       _onItemDropped = onItemDropped,
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

  int _$cancels = 0;
  int _$tooLate = 0;
  int _$droppedItems = 0;

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
        counters: _$publishCounters,
        now: _now,
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
    if (_repeated(chatId, clientMessageId, null)) {
      return OutgoingCancelOutcome.dropped;
    }
    final message = switch (_projection.lookup(chatId, clientMessageId)) {
      final message? => _current(message),
      null => null,
    };
    if (message == null) return OutgoingCancelOutcome.unknown;
    if (_tooLate(message)) return OutgoingCancelOutcome.tooLate;
    _$cancelsAccepted[(chatId, clientMessageId, null)] = _now();
    final key = (chatId, clientMessageId);
    if (_projection.sending.contains(key)) {
      // The server may be accepting it now: the publisher runs the cancel
      // once it answers, unless the answer is an accept.
      _projection.cancelRequests[key] = () {
        if (_projection.lookup(chatId, clientMessageId) case final message?) {
          _cancelNow(_current(message), trigger);
        }
      };
      return OutgoingCancelOutcome.pending;
    }
    _cancelNow(message, trigger);
    return OutgoingCancelOutcome.cancelled;
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

  /// Whether a cancel of the message ([itemId] null) or of its item
  /// [itemId] was accepted already; reports `actionDropped` when it was.
  bool _repeated(String chatId, String clientMessageId, String? itemId) {
    final accepted = _$cancelsAccepted[(chatId, clientMessageId, itemId)];
    if (accepted == null) return false;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.actionDropped,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        mediaItemId: itemId,
      ),
      fields: () => {
        'action': 'cancel',
        'msSinceAccepted': _now().difference(accepted).inMilliseconds,
      },
    );
    return true;
  }

  /// Cancels [message]'s job and makes the message Absent, its row leaving
  /// the tail.
  void _cancelNow(OutgoingMessage message, _Trigger trigger) {
    final OutgoingMessage(:chatId, :clientMessageId) = message;
    final job = _projection.jobOf(chatId, clientMessageId);
    // The engine may have dropped the job already (it lost its last item,
    // or ended); the message goes all the same.
    if (job != null) _transfers.cancel(job.id);
    final rowRemoved = _$strategies[chatId]?.remove(clientMessageId) ?? false;
    _projection.remove(chatId, clientMessageId);
    _$itemsDropped.remove((chatId, clientMessageId));
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
    _syncInFlight(chatId);
    _onCancelled?.call(
      OutgoingCancelled(
        message: message.withStatus(const OutgoingStatus.cancelled()),
        rowRemoved: rowRemoved,
      ),
    );
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
    });
    _syncInFlight(chatId);
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
    final (:status, :stage) = JobProjection.of(job, message.status);
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
        cancels: _$cancels,
        itemsDropped: _$droppedItems,
        cancelsTooLate: _$tooLate + _$publishCounters.cancelsTooLate,
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
    final watches = [..._$watches.values];
    _$watches.clear();
    for (final notifier in _$inFlightNotifiers.values) {
      notifier.dispose();
    }
    _$inFlightNotifiers.clear();
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

/// Builds the host's row for an accepted outgoing [message], at
/// `message.position`, from its message model [payload]: the row the
/// chat's id strategy inserts, for which the data source's `identityOf`
/// answers the message's client message id.
typedef OutgoingRowBuilder<M> =
    IChatMessage Function(OutgoingMessage message, M payload);
