import 'dart:async';
import 'dart:collection';

/// Publishes events to a synchronous broadcast [stream], in order, also when a
/// listener publishes while an event is being delivered.
///
/// A synchronous broadcast controller throws a [StateError] if an event is
/// added while it is delivering one, and a listener that answers an event with
/// another is the normal case here: the bake activity reports "moving" from
/// inside the motion event that made it so. Such an event is queued and
/// delivered, to every listener, once the one in flight has reached them all.
/// It is still delivered before the outermost [publish] returns, which an
/// asynchronous controller could not promise, so a caller that publishes and
/// then reads state sees every consequence.
///
/// A listener that throws is reported to the zone and the others still run
/// (the stream's own behaviour).
final class EventPublisher<T> {
  final _controller = StreamController<T>.broadcast(sync: true);
  final _pending = Queue<T>();
  var _delivering = false;
  var _disposed = false;

  /// The events, to listen to. A subscription added while an event is being
  /// delivered first hears the next one.
  Stream<T> get stream => _controller.stream;

  /// Delivers [event] to every subscriber, or queues it behind the event being
  /// delivered. Does nothing after [dispose].
  void publish(T event) {
    if (_disposed) return;
    _pending.add(event);
    if (_delivering) return;
    _delivering = true;
    try {
      while (_pending.isNotEmpty && !_disposed) {
        _controller.add(_pending.removeFirst());
      }
    } finally {
      _delivering = false;
      if (_disposed) _close();
    }
  }

  /// Ends the stream: subscribers are told it is done and nothing more is
  /// delivered. Idempotent; from inside a listener it takes effect once the
  /// event in flight has reached everyone.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending.clear();
    if (!_delivering) _close();
  }

  // Closing a controller that is delivering throws, hence the deferral above.
  void _close() => unawaited(_controller.close());
}
