import 'package:catalog_assets/src/playback/playback_lifecycle_source.dart';
import 'package:flutter/widgets.dart';

/// The production [PlaybackLifecycleSource]: the lifecycle the widgets binding
/// receives from the embedder.
///
/// Starts from the binding's current state (the platform may not have said
/// anything yet, which is `null`). It needs the widgets binding, so a host
/// creates it once the app runs and disposes it with the shell, as it does
/// `SystemMemoryPressure`.
final class WidgetsPlaybackLifecycleSource extends ChangeNotifier
    with WidgetsBindingObserver
    implements PlaybackLifecycleSource {
  /// Starts observing the platform. Call [dispose] to stop.
  WidgetsPlaybackLifecycleSource()
    : _state = WidgetsBinding.instance.lifecycleState {
    WidgetsBinding.instance.addObserver(this);
  }

  AppLifecycleState? _state;
  bool _disposed = false;

  @override
  AppLifecycleState? get state => _state;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == _state) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    // A `ChangeNotifier` asserts on a second dispose; a host that frees its
    // shell twice should not crash on this one.
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
