import 'dart:typed_data';

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_outbox/src/diagnostics/outbox_op.dart';
import 'package:chat_outbox/src/diagnostics/outbox_trace.dart';
import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_outbox/src/message/outgoing_message.dart';
import 'package:chat_outbox/src/message/outgoing_payload_codec.dart';
import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:chat_outbox/src/outbox/outbox_projection.dart';
import 'package:chat_outbox/src/outbox/publish_rejection_codec.dart';
import 'package:chat_outbox/src/send/outgoing_message_sender.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// What the chat publisher counts across its calls, for the outbox's debug
/// snapshot: kept by the outbox, so a sender registered again counts on.
@internal
final class PublishCounters {
  final Map<(String, String), int> _$attempts = {};

  /// Conflicts answered, every chat.
  int conflicts = 0;

  /// Cancels that waited for the sender's answer, which was an accept.
  int cancelsTooLate = 0;

  /// The sender calls for message [clientMessageId] of [chatId] so far.
  int? attemptsOf(String chatId, String clientMessageId) =>
      _$attempts[(chatId, clientMessageId)];

  void _attempted(String chatId, String clientMessageId) => _$attempts.update(
    (chatId, clientMessageId),
    (count) => count + 1,
    ifAbsent: () => 1,
  );
}

/// The publisher `chat.send`: the engine calls it once a message's uploads
/// are done, and it runs the host's sender and turns its answer into the
/// engine's outcome.
///
/// Per call: the row moves to `tip+1` (the strategy's `publishStart`), the
/// sender gets the strategy's proposal, read now, and the message's client
/// message id, the idempotency key of every attempt. A conflict hands the
/// strategy the confirmed messages the sender brought, so the row moves up,
/// and sends again within this call, at most [maxConflicts] times; nothing
/// is uploaded or prepared again. A published answer confirms the row (or,
/// for a replay at another id, moves it there first) and hands the host the
/// message as stored before the engine hears `published`, so the next row's
/// proposal already sits after it.
@internal
final class ChatSendPublisher<M> implements Publisher {
  /// The publisher over [projection], running [sender].
  ChatSendPublisher({
    required OutboxProjection projection,
    required OutgoingIdStrategy Function(String chatId) strategyOf,
    required OutgoingPayloadCodec<M> codec,
    required OutgoingMessageSender<M> sender,
    required CapabilityFeedback feedback,
    required void Function(OutgoingSent<M> sent)? onSent,
    required PublishCounters counters,
    void Function(OutgoingMessage message)? onStatusChanged,
    required DateTime Function() now,
    required Future<OutgoingMessage?> Function(String clientMessageId)
    restoredMessage,
  }) : _projection = projection,
       _restoredMessage = restoredMessage,
       _strategyOf = strategyOf,
       _codec = codec,
       _sender = sender,
       _feedback = feedback,
       _onSent = onSent,
       _onStatusChanged = onStatusChanged,
       _counters = counters,
       _now = now;

  /// How many conflicts one publish call answers before it gives up: the
  /// third ends the call as a retryable rejection.
  static const int maxConflicts = 3;

  final OutboxProjection _projection;
  final OutgoingIdStrategy Function(String chatId) _strategyOf;
  final OutgoingPayloadCodec<M> _codec;
  final OutgoingMessageSender<M> _sender;
  final CapabilityFeedback _feedback;
  final void Function(OutgoingSent<M> sent)? _onSent;
  final void Function(OutgoingMessage message)? _onStatusChanged;
  final PublishCounters _counters;
  final DateTime Function() _now;

  /// The message [clientMessageId] once its chat is restored; null when it
  /// never will be in this run.
  final Future<OutgoingMessage?> Function(String clientMessageId)
  _restoredMessage;

  @override
  Future<PublishOutcome> publish(
    Uint8List payload,
    Map<String, PublishItemRefs> items,
    String idempotencyKey,
  ) => OutboxTrace.publish.runAsync(
    () => _publish(payload, items, idempotencyKey),
  );

  Future<PublishOutcome> _publish(
    Uint8List payload,
    Map<String, PublishItemRefs> items,
    String clientMessageId,
  ) async {
    final started = _now();
    // A job of an earlier run publishes as soon as the sender registers,
    // which may be before the host restores its chat: it waits for the
    // restore, since only then does its message have a row to confirm.
    final message =
        _projection.find(clientMessageId) ??
        await _restoredMessage(clientMessageId);
    if (message == null) {
      // A message this run will not restore (the outbox was disposed, or its
      // payload could not be read and the host gave no row for that).
      // Thrown, the engine fails it as its publisher's error, retryable.
      _report(
        ChatEventLevel.error,
        OutboxOp.senderFailed,
        ChatCorrelation(clientMessageId: clientMessageId),
        {'errorType': 'unknownMessage'},
      );
      throw StateError('No outgoing message $clientMessageId in this run.');
    }
    final chatId = message.chatId;
    final strategy = _strategyOf(chatId);
    final jobId = _projection.jobOf(chatId, clientMessageId)?.id;
    final M model;
    try {
      model = _codec.decode(payload);
    } on Object catch (error, stackTrace) {
      _report(
        ChatEventLevel.error,
        OutboxOp.payloadDecodeFailed,
        ChatCorrelation(
          chatId: chatId,
          clientMessageId: clientMessageId,
          jobId: jobId,
        ),
        {'errorType': '${error.runtimeType}', 'payloadBytes': payload.length},
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    final refs = {
      for (final MapEntry(:key, :value) in items.entries)
        MediaItemId.parse(key): value,
    };
    ChatCorrelation correlation({int? position}) => ChatCorrelation(
      chatId: chatId,
      clientMessageId: clientMessageId,
      jobId: jobId,
      scrollId: switch (position ?? strategy.positionOf(clientMessageId)) {
        final position? => '$position',
        null => null,
      },
    );

    var conflicts = 0;
    for (var attempt = 1; ; attempt++) {
      strategy.publishStart(clientMessageId);
      final proposedId = strategy.proposedId;
      _counters._attempted(chatId, clientMessageId);
      _report(ChatEventLevel.info, OutboxOp.publishAttempt, correlation(), {
        'attempt': attempt,
        'proposedId': ?proposedId,
        'remoteRefs': refs.length,
      });
      final key = (chatId, clientMessageId);
      final OutgoingSendAnswer<M> answer;
      // While the call is out, a cancel waits for its answer: the server
      // may be accepting the message, and an accepted message stays sent.
      _projection.sending.add(key);
      try {
        answer = await _sender.send(
          OutgoingSendRequest(
            chatId: chatId,
            clientMessageId: clientMessageId,
            payload: model,
            items: refs,
            attempt: attempt,
            proposedId: proposedId,
          ),
        );
      } on Object catch (error, stackTrace) {
        // The error may carry the host's message: only its type.
        _report(ChatEventLevel.error, OutboxOp.senderFailed, correlation(), {
          'errorType': '${error.runtimeType}',
        });
        _projection.sending.remove(key);
        _projection.cancelRequests.remove(key)?.call();
        Error.throwWithStackTrace(error, stackTrace);
      }
      _projection.sending.remove(key);
      if (_projection.cancelRequests.remove(key) case final cancel?) {
        if (answer case OutgoingSendResult<M>()) {
          _report(ChatEventLevel.info, OutboxOp.cancelTooLate, correlation(), {
            'stage': PublishStage.publish.name,
          });
          _counters.cancelsTooLate++;
          // The job may be gone already (the system's cancel of every job in
          // the transfer envelope took it), and then no completion comes to
          // show the message sent: it is sent from the server's accept.
          if (_projection.lookup(chatId, clientMessageId) case final current?
              when current.status is! OutgoingStatus$Sent) {
            final sent = current.withStatus(const OutgoingStatus.sent());
            _projection.put(sent);
            _report(
              ChatEventLevel.debug,
              OutboxOp.statusChanged,
              correlation(),
              {
                'from': current.status.name,
                'to': const OutgoingStatus.sent().name,
              },
            );
            _onStatusChanged?.call(sent);
          }
        } else {
          // Not accepted: the cancel applies. The job is gone by then, so
          // the engine reads nothing of this answer.
          cancel();
          return const PublishOutcome.rejected(
            reason: PublishFailureReason.cancelled,
          );
        }
      }
      switch (answer) {
        case OutgoingSendResult<M>():
          return _published(
            message,
            answer,
            strategy: strategy,
            model: model,
            proposedId: proposedId,
            attempts: attempt,
            started: started,
            jobId: jobId,
          );
        case OutgoingSendAnswer$ReuploadItems<M>(:final itemIds):
          for (final itemId in itemIds) {
            _report(
              ChatEventLevel.warning,
              OutboxOp.reuploadRequested,
              ChatCorrelation(
                chatId: chatId,
                clientMessageId: clientMessageId,
                jobId: jobId,
                mediaItemId: '$itemId',
              ),
              {'items': itemIds.length},
            );
          }
          return PublishOutcome.reuploadItems([
            for (final itemId in itemIds) '$itemId',
          ]);
        case OutgoingSendAnswer$Rejected<M>(:final reason, :final retryable):
          _report(ChatEventLevel.warning, OutboxOp.rejected, correlation(), {
            'reason': 'rejected',
            'retryable': retryable,
          });
          return PublishOutcome.rejected(
            reason: const PublishRejectionCodec().encode(
              OutgoingFailure.rejected(reason),
            ),
            retryable: retryable,
          );
        case OutgoingSendAnswer$Denied<M>(:final action, :final reason):
          _report(ChatEventLevel.info, OutboxOp.denied, correlation(), {
            'action': action,
            'reason': reason.diagnosticForm,
          });
          _feedback.onDenied(
            action,
            reason,
            consumer: CapabilityConsumer.outbox,
            correlation: correlation(),
          );
          return PublishOutcome.rejected(
            reason: const PublishRejectionCodec().encode(
              OutgoingFailure.denied(action),
            ),
          );
        case OutgoingSendAnswer$Conflict<M>(:final nextId, :final missing):
          conflicts++;
          _counters.conflicts++;
          _report(
            ChatEventLevel.warning,
            OutboxOp.publishConflict,
            correlation(),
            {
              'attempt': conflicts,
              if (proposedId case final proposed?)
                'distance': nextId - proposed,
            },
          );
          if (conflicts >= maxConflicts) {
            _report(
              ChatEventLevel.error,
              OutboxOp.publishConflictExhausted,
              correlation(),
              {'attempts': attempt},
            );
            return const PublishOutcome.rejected(
              reason: PublishRejectionCodec.conflictCode,
              retryable: true,
            );
          }
          _placeBefore(strategy, missing);
      }
    }
  }

  PublishOutcome _published(
    OutgoingMessage message,
    OutgoingSendResult<M> result, {
    required OutgoingIdStrategy strategy,
    required M model,
    required int? proposedId,
    required int attempts,
    required DateTime started,
    required PublishJobId? jobId,
  }) {
    final OutgoingMessage(:chatId, :clientMessageId) = message;
    // From here a cancel is too late, before the job's completion is seen.
    _projection.accepted.add((chatId, clientMessageId));
    final serverId = result.serverMessageId ?? proposedId;
    int? rowAt;
    if (proposedId != null && serverId != null && serverId != proposedId) {
      // An idempotent replay: the server has the message at another id.
      _report(
        ChatEventLevel.warning,
        OutboxOp.replayRebased,
        ChatCorrelation(
          chatId: chatId,
          clientMessageId: clientMessageId,
          jobId: jobId,
          scrollId: '$serverId',
        ),
        {'distance': serverId - proposedId},
      );
      if (serverId > proposedId) _placeBefore(strategy, result.missing);
      if (strategy.positionOf(clientMessageId) == serverId) {
        rowAt = strategy.confirm(clientMessageId);
      } else {
        // The server's id is one the row cannot sit at: below the tip, or
        // past positions the chat does not hold. The row leaves, and the
        // host places the confirmed message where it learns of it.
        strategy.remove(clientMessageId);
      }
    } else {
      rowAt = strategy.confirm(clientMessageId);
    }
    final position = rowAt ?? serverId ?? message.position;
    if (_projection.lookup(chatId, clientMessageId) case final current?) {
      _projection.put(current.withPosition(position));
    }
    final stored = switch (result.payloadAsStored) {
      final stored? => _codec.encode(stored),
      null => null,
    };
    try {
      _onSent?.call(
        OutgoingSent(
          chatId: chatId,
          clientMessageId: clientMessageId,
          position: position,
          rowAt: rowAt,
          serverMessageId: result.serverMessageId,
          payload: model,
          payloadAsStored: result.payloadAsStored,
          serverKeys: result.serverKeys,
        ),
      );
    } on Object catch (error) {
      // The server has the message: a host fault in settling the row must
      // not fail it.
      _report(
        ChatEventLevel.error,
        OutboxOp.senderFailed,
        ChatCorrelation(
          chatId: chatId,
          clientMessageId: clientMessageId,
          jobId: jobId,
        ),
        {'errorType': '${error.runtimeType}', 'in': 'onSent'},
      );
    }
    _report(
      ChatEventLevel.info,
      OutboxOp.published,
      ChatCorrelation(
        chatId: chatId,
        clientMessageId: clientMessageId,
        jobId: jobId,
        scrollId: '$position',
      ),
      {
        'attempts': attempts,
        'durationMs': _now().difference(started).inMilliseconds,
        'serverKeys': result.serverKeys.length,
        'payloadAsStoredDiffers':
            stored != null && !_sameBytes(stored, message.payload),
      },
    );
    return PublishOutcome.published(
      result: stored,
      serverKeys: {
        for (final MapEntry(:key, :value) in result.serverKeys.entries)
          '$key': value,
      },
    );
  }

  /// Hands [strategy] the confirmed messages a sender brought that land
  /// inside the tail; those the chat holds already (below the tail) are
  /// skipped.
  static void _placeBefore(
    OutgoingIdStrategy strategy,
    List<IChatMessage> missing,
  ) {
    final start = strategy.tip + 1;
    final inside = [
      for (final message in missing)
        if (message.id >= start) message,
    ];
    if (inside.isNotEmpty) strategy.incoming(inside);
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static void _report(
    ChatEventLevel level,
    OutboxOp op,
    ChatCorrelation correlation,
    Map<String, Object> fields,
  ) => ChatDiagnostics.current.emit(
    level,
    ChatEventCategory.outbox,
    op,
    correlation: correlation,
    fields: () => fields,
  );
}
