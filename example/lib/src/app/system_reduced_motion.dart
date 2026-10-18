import 'package:flutter/widgets.dart';

/// Whether the system asks for less motion, as a value a
/// `PlaybackActivity` can follow.
///
/// Read from `PlatformDispatcher.accessibilityFeatures.disableAnimations`,
/// which the engine fills on Linux and on the phones. On macOS and Windows the
/// engine at this revision reports nothing, so the value stays false there
/// until a host reads the setting through a platform channel and feeds the
/// same layer itself (docs/host-integration.md, "Pause layers"). The chrome
/// motion already follows the same flag through `MediaQuery`.
final class SystemReducedMotion extends ValueNotifier<bool>
    with WidgetsBindingObserver {
  /// Starts observing the platform. Call [dispose] to stop.
  SystemReducedMotion() : super(_current()) {
    WidgetsBinding.instance.addObserver(this);
  }

  static bool _current() => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  bool _disposed = false;

  @override
  void didChangeAccessibilityFeatures() => value = _current();

  @override
  void dispose() {
    // A `ChangeNotifier` asserts on a second dispose.
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
