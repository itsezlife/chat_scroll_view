/// A callback with no arguments, run when something an [Observable] guards
/// has changed.
typedef ObservableListener = void Function();

/// A callback that receives each event an [EventObservable] publishes.
typedef EventListener<T> = void Function(T event);

/// The read side of the one synchronous change-notification primitive: a
/// source of "something changed" signals.
///
/// Delivery is synchronous: listeners run inside the call that changed the
/// state, before it returns, so a listener always sees the state the signal
/// is about. Consumers that need to read the new state do so from the owner;
/// the signal carries none.
///
/// ## Listener contract
///
/// - **Dedup-on-add.** Adding a listener that is already registered (same
///   function, by `==`) does nothing; it is called once per signal, and one
///   [removeListener] unregisters it.
/// - **Snapshot dispatch.** A signal is delivered to the listeners registered
///   when it started, in registration order. A listener may add or remove
///   listeners, itself included, while it runs. A listener added meanwhile
///   first hears the next signal; one removed meanwhile is not called again,
///   even if the running signal has not reached it yet.
/// - **Isolation.** A listener that throws does not stop the others; its
///   error goes to the current zone's uncaught-error handler. The code that
///   changed the state is not told.
/// - **Disposal.** After the owner is disposed no signal is delivered,
///   [addListener] registers nothing and [removeListener] does nothing.
///
/// Owners publish through [ObservableNotifier]; the interface exists so that
/// a consumer holding only an [Observable] cannot signal. Adapters to a
/// framework's own listenable type live at the framework edge, not here.
abstract interface class Observable {
  /// Registers [listener] to be run for every signal until it is removed.
  void addListener(ObservableListener listener);

  /// Unregisters [listener]. A listener that is not registered is ignored.
  void removeListener(ObservableListener listener);
}

/// An [Observable] that guards a current [value], the snapshot a signal is
/// about.
///
/// The signal carries no payload: a listener reads [value]. Several changes
/// made inside one batch therefore reach listeners as one signal and one
/// value, never as a trail of intermediate states.
///
/// [value] is an immutable snapshot. The owner replaces it, never mutates it
/// in place, so a reference taken earlier stays valid and unchanged.
abstract interface class ValueObservable<T> implements Observable {
  /// The current snapshot.
  T get value;
}

/// The read side of a typed stream of events delivered synchronously.
///
/// Unlike an [Observable], there is no state to read back: each event is
/// handed to the listeners once, in the order published, and is gone. Use it
/// for things that happen (a scroll started, a section came near), not for
/// things that are (the current sections).
///
/// Listener registration follows the [Observable] contract: dedup-on-add,
/// snapshot dispatch, isolation of throwing listeners and silence after
/// disposal. An event published from inside a listener is delivered to all
/// listeners before the publishing call returns, so listeners may see events
/// nested inside the one they are handling.
abstract interface class EventObservable<T> {
  /// Registers [listener] to receive every event until it is removed.
  void addListener(EventListener<T> listener);

  /// Unregisters [listener]. A listener that is not registered is ignored.
  void removeListener(EventListener<T> listener);
}
