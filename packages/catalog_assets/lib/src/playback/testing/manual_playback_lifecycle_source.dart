import 'dart:ui' show AppLifecycleState;

import 'package:catalog_assets/src/playback/playback_lifecycle_source.dart';
import 'package:flutter/foundation.dart';

/// A [PlaybackLifecycleSource] a test moves by hand with [emit].
final class ManualPlaybackLifecycleSource extends ChangeNotifier
    implements PlaybackLifecycleSource {
  /// Creates a source that already reports [initial] (`null`: the platform has
  /// not said anything yet).
  ManualPlaybackLifecycleSource({AppLifecycleState? initial})
    : _state = initial;

  AppLifecycleState? _state;
  bool _disposed = false;

  @override
  AppLifecycleState? get state => _state;

  /// Whether anything is listening.
  bool get isListened => hasListeners;

  /// Reports [state]; the state it already has changes nothing.
  void emit(AppLifecycleState state) {
    if (_disposed || state == _state) return;
    _state = state;
    notifyListeners();
  }

  /// Reports each of [states] in turn: how the platform delivers a jump such as
  /// `resumed -> hidden` (`inactive`, then `hidden`).
  void emitAll(Iterable<AppLifecycleState> states) => states.forEach(emit);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
