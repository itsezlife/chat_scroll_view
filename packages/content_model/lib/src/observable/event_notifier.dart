import 'package:content_model/src/observable/listener_set.dart';
import 'package:content_model/src/observable/observable.dart';

/// The owner side of an [EventObservable]: publishes typed events to its
/// listeners.
///
/// Events are not state, so there is no batching and no deduplication: every
/// [publish] reaches every listener, equal events included. The listener
/// contract is the one on [EventObservable]. After [dispose] every entry
/// point is a silent no-op.
final class EventNotifier<T> implements EventObservable<T> {
  final _listeners = ListenerSet<EventListener<T>>();

  /// Whether [dispose] has been called.
  bool get isDisposed => _listeners.isDisposed;

  @override
  void addListener(EventListener<T> listener) => _listeners.add(listener);

  @override
  void removeListener(EventListener<T> listener) => _listeners.remove(listener);

  /// Hands [event] to every registered listener.
  void publish(T event) => _listeners.dispatch((listener) => listener(event));

  /// Drops every listener for good. Idempotent; safe from inside a listener.
  void dispose() => _listeners.dispose();
}
