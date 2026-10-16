import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:meta/meta.dart';

/// Work a [PriorityLane] orders and starts.
@internal
abstract interface class LaneWork {
  /// How urgent the work is right now. Read each time the lane picks, so it
  /// can change while the work waits.
  AssetPriority get priority;
}

/// A queue that runs at most [capacity] pieces of work at once, most urgent
/// first and oldest first among equals.
///
/// Work holds its slot from the moment the lane starts it until [release];
/// the lane does not preempt running work when something more urgent arrives.
/// [canStart] lets the owner hold the whole lane back (backpressure); the
/// owner calls [pump] when that answer may have changed.
///
/// Internal to the pipeline.
@internal
final class PriorityLane<T extends LaneWork> {
  /// Creates a lane of [capacity] slots that calls [start] for each piece of
  /// work it lets go.
  PriorityLane({
    required this.capacity,
    required void Function(T work) start,
    bool Function()? canStart,
  }) : _start = start,
       _canStart = canStart ?? _always,
       assert(capacity > 0, 'A lane needs at least one slot.');

  static bool _always() => true;

  /// How many pieces of work run at once.
  final int capacity;

  final void Function(T work) _start;
  final bool Function() _canStart;
  final List<T> _waiting = [];
  final Set<T> _running = Set.identity();
  bool _pumping = false;

  /// How many pieces of work wait for a slot.
  int get waitingCount => _waiting.length;

  /// How many pieces of work hold a slot.
  int get runningCount => _running.length;

  /// Queues [work] and starts what fits.
  void enqueue(T work) {
    _waiting.add(work);
    pump();
  }

  /// Takes [work] out of the queue if it still waits there.
  bool remove(T work) => _waiting.remove(work);

  /// Gives back the slot of [work] and starts what fits. Releasing work that
  /// holds no slot does nothing.
  void release(T work) {
    if (_running.remove(work)) pump();
  }

  /// Starts waiting work while there are free slots and [canStart] agrees.
  void pump() {
    // A start may end the work inside the call and so re-enter; the outer
    // loop picks up what that freed.
    if (_pumping) return;
    _pumping = true;
    try {
      while (_running.length < capacity && _waiting.isNotEmpty && _canStart()) {
        final next = _mostUrgent();
        _waiting.remove(next);
        _running.add(next);
        _start(next);
      }
    } finally {
      _pumping = false;
    }
  }

  T _mostUrgent() {
    var best = _waiting.first;
    for (final work in _waiting) {
      if (work.priority.index > best.priority.index) best = work;
    }
    return best;
  }
}
