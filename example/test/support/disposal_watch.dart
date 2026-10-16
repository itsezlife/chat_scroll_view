import 'package:flutter/foundation.dart';

/// Which framework objects (change notifiers, focus nodes, lifecycle
/// listeners: whatever reports to `FlutterMemoryAllocations`) were created
/// since it started and have not been disposed.
///
/// Lets a test say "a failed construction freed everything it had made"
/// without the failed object's handle, which a thrown constructor never
/// returns.
final class DisposalWatch {
  /// Starts watching.
  DisposalWatch() {
    FlutterMemoryAllocations.instance.addListener(_onEvent);
  }

  final Map<Object, String> _live = Map<Object, String>.identity();

  void _onEvent(ObjectEvent event) {
    switch (event) {
      case ObjectCreated(:final object, :final className):
        _live[object] = className;
      case ObjectDisposed(:final object):
        _live.remove(object);
      default:
        break;
    }
  }

  /// The class names of what is still alive.
  List<String> get undisposed => _live.values.toList()..sort();

  /// Stops watching.
  void stop() => FlutterMemoryAllocations.instance.removeListener(_onEvent);
}
