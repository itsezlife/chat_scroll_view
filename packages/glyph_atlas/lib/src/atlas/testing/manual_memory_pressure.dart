import 'package:flutter/foundation.dart';

/// A memory pressure signal a test raises by hand, in place of
/// `SystemMemoryPressure`.
final class ManualMemoryPressure extends ChangeNotifier {
  /// Reports memory pressure to the listeners.
  void raise() => notifyListeners();

  /// Whether anything is listening.
  bool get isListened => hasListeners;
}
