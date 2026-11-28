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
  /// [localKeyOf] and [undecodableRowOf] serve [pendingFor] after a restart,
  /// when a message is known only from its job: [localKeyOf] maps an item's
  /// media key back to its local content key (the inverse of the mapping
  /// [itemOf] answers with), and [undecodableRowOf] builds the row of a
  /// message whose payload the [codec] cannot read, which has no model for
  /// [rowOf].
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
    ContentKey Function(MediaKey mediaKey)? localKeyOf,
    IChatMessage Function(OutgoingMessage message)? undecodableRowOf,
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
         localKeyOf: localKeyOf,
         undecodableRowOf: undecodableRowOf,
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
    ContentKey Function(MediaKey mediaKey)? localKeyOf,
    IChatMessage Function(OutgoingMessage message)? undecodableRowOf,
  }) : _transfers = transfers,
       _localKeyOf = localKeyOf,
       _undecodableRowOf = undecodableRowOf,
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
    _projection.put(message, fresh: true, job: OutboxJobView(jobId));
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
