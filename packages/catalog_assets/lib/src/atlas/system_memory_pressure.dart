import 'package:flutter/widgets.dart';

/// Notifies its listeners whenever the platform reports memory pressure: the
/// system asks running apps to give back what they can.
///
/// The production `memoryPressure` of a `GlyphPageResidency`. It needs the
/// widgets binding (as `ImageCache` does for the same signal), so a host
/// creates it once the app runs and disposes it with the shell.
final class SystemMemoryPressure extends ChangeNotifier
    with WidgetsBindingObserver {
  /// Starts observing the platform. Call [dispose] to stop.
  SystemMemoryPressure() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() => notifyListeners();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
