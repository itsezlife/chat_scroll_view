import 'dart:async';
import 'dart:math';

import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_outbox/src/diagnostics/outbox_debug_snapshot.dart';
import 'package:chat_outbox/src/diagnostics/outbox_op.dart';
import 'package:chat_outbox/src/diagnostics/outbox_trace.dart';
import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:chat_outbox/src/message/outgoing_payload_codec.dart';
import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:chat_outbox/src/outbox/job_projection.dart';
import 'package:chat_outbox/src/outbox/outbox_projection.dart';
import 'package:chat_outbox/src/send/outgoing_send_item.dart';
import 'package:chat_outbox/src/send/send_check.dart';
import 'package:chat_outbox/src/transfers/outbox_transfers.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The outbox: the outgoing messages of every chat, sent as publish jobs
/// and read back as the host and the chat's rows see them.
///
/// [send] turns a planned send (or [sendText] a text) into one publish job
/// under the chat's tag, after the chat's slow mode and limits let it
/// through; the job's state, watched per chat, is the message's status.
/// [M] is the host's message model, which the outbox keeps as bytes
/// through the host's [OutgoingPayloadCodec].
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
  /// and where its bytes come from. [capabilitiesOf] gives the chat's
  /// capabilities listenable, the one the host passes the chat's other
  /// consumers; a chat without one is unrestricted. [feedback] hears of a
  /// refused send. [clientMessageIds] issues each send's client message id
  /// (128 random bits in hex unless given); an id never contains `:`, which
  /// separates the parts of a job's tag. [now] is the clock slow mode is
  /// read at.
  ChatOutbox({
    required OutboxTransfers transfers,
    required OutgoingPayloadCodec<M> codec,
    required OutgoingSendItemResolver itemOf,
    ValueListenable<ChatCapabilities>? Function(String chatId)? capabilitiesOf,
    CapabilityFeedback feedback = CapabilityFeedback.none,
    String Function()? clientMessageIds,
    DateTime Function() now = DateTime.now,
  }) : this.over(
         OutboxProjection(),
         transfers: transfers,
         codec: codec,
         itemOf: itemOf,
         capabilitiesOf: capabilitiesOf,
         feedback: feedback,
         clientMessageIds: clientMessageIds,
         now: now,
       );

  /// An outbox reading [projection], for tests that set rows up directly.
  @visibleForTesting
  ChatOutbox.over(
    this._projection, {
    required OutboxTransfers transfers,
    required OutgoingPayloadCodec<M> codec,
    required OutgoingSendItemResolver itemOf,
    ValueListenable<ChatCapabilities>? Function(String chatId)? capabilitiesOf,
    CapabilityFeedback feedback = CapabilityFeedback.none,
    String Function()? clientMessageIds,
    DateTime Function() now = DateTime.now,
  }) : _transfers = transfers,
       _codec = codec,
       _itemOf = itemOf,
       _capabilitiesOf = capabilitiesOf,
       _feedback = feedback,
       _issueClientMessageId = clientMessageIds ?? _$randomClientMessageId,
       _now = now;

  /// The publisher id the outbox's jobs name: the host's sender, registered
  /// by the outbox.
  static const String publisherId = 'chat.send';

  /// The tag of the publish job of message [clientMessageId] of [chatId].
  static String tagOf(String chatId, String clientMessageId) =>
      '${tagPrefixOf(chatId)}$clientMessageId';

  /// The tag prefix every publish job of [chatId] starts with.
  static String tagPrefixOf(String chatId) => 'chat:$chatId:';

  final OutboxProjection _projection;
  final OutboxTransfers _transfers;
  final OutgoingPayloadCodec<M> _codec;
  final OutgoingSendItemResolver _itemOf;
  final ValueListenable<ChatCapabilities>? Function(String chatId)?
  _capabilitiesOf;
  final CapabilityFeedback _feedback;
  final String Function() _issueClientMessageId;
  final DateTime Function() _now;

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
  /// [itemIds], one per item in order. The message is fresh: the host's
  /// [isFreshOutgoing] answers true for it once.
  ///
  /// Reports `refusedBeforeJob`, or `accepted` then `jobCreated`. Throws an
  /// [ArgumentError] when [itemIds] does not give one id per item, and
  /// whatever the engine throws for a request it cannot run, after which
  /// the outbox holds nothing of the send.
  OutgoingMessage? send(
    String chatId,
    PlannedSend send, {
    required M payload,
    List<MediaItemId>? itemIds,
  }) {
    _checkNotDisposed();
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
    final message = OutgoingMessage(
      chatId: chatId,
      clientMessageId: clientMessageId,
      status: _firstStatusOf(request),
      payload: request.payload,
      items: [
        for (final (index, item) in sendItems.indexed)
          OutgoingItem(id: ids[index], localKey: item.localKey),
      ],
    );
    _projection.put(message, fresh: true, job: OutboxJobView(jobId));
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
    final message = _projection.lookup(chatId, clientMessageId);
    // A job this outbox did not make in this run (a restart's) is not
    // projected here.
    if (message == null ||
        _projection.jobOf(chatId, clientMessageId)?.id != job.id) {
      return;
    }
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
        scrollId: switch (message.position) {
          final position? => '$position',
          null => null,
        },
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
    final message = _projection.lookup(chatId, clientMessageId);
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.outbox,
      OutboxOp.echoMatched,
      correlation: ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        scrollId: switch (message?.position) {
          final position? => '$position',
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
  /// Reading it changes nothing: a row's fresh flag stays unread.
  OutboxDebugSnapshot debugSnapshot(String chatId) => OutboxDebugSnapshot(
    chatId: chatId,
    tail: [
      for (final message in _projection.tailOf(chatId))
        OutboxDebugRow.of(
          message,
          fresh: _projection.isFresh(chatId, message.clientMessageId),
          job: _projection.jobOf(chatId, message.clientMessageId),
        ),
    ],
    sendInFlight: _projection.hasInFlight(chatId),
    counters: OutboxDebugCounters(accepted: _$accepted),
  );

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
