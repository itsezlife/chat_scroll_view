import 'dart:async';
import 'dart:collection';

import 'package:chat_outbox/src/send/outgoing_message_sender.dart';

/// An [OutgoingMessageSender] with no server behind it, for tests of the
/// outbox and of hosts that drive one: it records every request and answers
/// each from a script.
///
/// Each call takes the next scripted answer ([answerWith], [answerBy],
/// [throwOnNext]). With none scripted it answers as an accept-if-next
/// server that takes every proposal: published at the proposed id (or at
/// no id of its own under a strategy that proposes none).
final class RecordingOutgoingSender<M> implements OutgoingMessageSender<M> {
  /// A sender with nothing scripted.
  RecordingOutgoingSender();

  final List<OutgoingSendRequest<M>> _requests = [];
  final Queue<FutureOr<OutgoingSendAnswer<M>> Function(OutgoingSendRequest<M>)>
  _$script = Queue();

  /// Every request so far, in order.
  List<OutgoingSendRequest<M>> get requests => List.unmodifiable(_requests);

  /// The next call answers [answer].
  void answerWith(OutgoingSendAnswer<M> answer) => _$script.add((_) => answer);

  /// The next call answers what [answer] gives for its request, which may
  /// wait (a test holding the server's answer).
  void answerBy(
    FutureOr<OutgoingSendAnswer<M>> Function(OutgoingSendRequest<M> request)
    answer,
  ) => _$script.add(answer);

  /// The next call throws [error].
  void throwOnNext(Object error) =>
      _$script.add((_) => Error.throwWithStackTrace(error, StackTrace.current));

  @override
  Future<OutgoingSendAnswer<M>> send(OutgoingSendRequest<M> request) {
    _requests.add(request);
    if (_$script.isEmpty) {
      return Future.value(
        OutgoingSendAnswer<M>.sent(serverMessageId: request.proposedId),
      );
    }
    final next = _$script.removeFirst();
    return Future.sync(() => next(request));
  }
}
