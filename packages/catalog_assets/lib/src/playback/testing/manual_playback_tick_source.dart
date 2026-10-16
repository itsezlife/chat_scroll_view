import 'package:catalog_assets/src/playback/playback_tick_source.dart';

/// A [PlaybackTickSource] a test steps by hand with [tick].
final class ManualPlaybackTickSource implements PlaybackTickSource {
  void Function(Duration timestamp)? _onTick;

  /// How many times [start] actually started it.
  int starts = 0;

  /// How many times [stop] actually stopped it.
  int stops = 0;

  /// Whether a frame is being asked for.
  bool get isRunning => _onTick != null;

  /// Delivers a frame at [timestamp] if running; otherwise does nothing.
  void tick(Duration timestamp) => _onTick?.call(timestamp);

  @override
  void start(void Function(Duration timestamp) onTick) {
    if (_onTick != null) return;
    starts++;
    _onTick = onTick;
  }

  @override
  void stop() {
    if (_onTick == null) return;
    stops++;
    _onTick = null;
  }
}
