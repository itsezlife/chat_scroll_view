/// A per-frame callback, the playback clock's only link to the engine.
///
/// A seam so the clock is driven by hand in tests; the production adapter is
/// `SchedulerPlaybackTickSource`. Everything runs on the UI isolate.
///
/// ## Contract
///
/// - [start] makes [onTick] run once per frame with the frame's timestamp, in
///   order, until [stop]. The timestamps are monotonic.
/// - [start] while running does nothing (the first callback stays).
/// - After [stop] nothing is delivered, including a frame already requested,
///   and no frame stays requested, so an idle clock keeps the engine asleep.
/// - [stop] while stopped does nothing; the source can be started again.
abstract interface class PlaybackTickSource {
  /// Starts delivering frames to [onTick].
  void start(void Function(Duration timestamp) onTick);

  /// Stops delivering frames.
  void stop();
}
