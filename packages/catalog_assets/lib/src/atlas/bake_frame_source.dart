import 'package:meta/meta.dart';

/// What the scheduler learns at a frame it asked for.
@immutable
final class BakeFrame {
  /// Creates a frame report.
  const BakeFrame({required this.budget, this.cost});

  /// The vsync interval of the display this frame is on (about 8.3 ms at
  /// 120 Hz).
  final Duration budget;

  /// The longer of the build and raster time of the most recent frame the
  /// engine finished measuring, or null when it has nothing new since the
  /// previous report. A measurement is reported once: the engine delivers
  /// timings in batches, and repeating a stale one would make the governor
  /// react to the same slow frame several times.
  final Duration? cost;
}

/// Tells [BakeFrameSource.requestFrame]'s caller that the frame will not come.
typedef BakeFrameCancel = void Function();

/// Receives a frame the baker asked for.
typedef BakeFrameCallback = void Function(BakeFrame frame);

/// The frame clock the bake is paced on: the only way the scheduler gets time
/// to work in, injected so a test can step it.
///
/// Contract (run [BakeFrameSourceContract.run] against an implementation):
///
/// - [requestFrame] makes the callback run once, on a later frame, never
///   inside the call;
/// - the function it returns cancels the request: the callback then never
///   runs, and calling it after the frame (or twice) does nothing;
/// - every report carries a positive [BakeFrame.budget];
/// - a source holds nothing once its requests are delivered or cancelled: an
///   idle app that pauses the bake asks for no further frames.
///
/// [BakeFrameSourceContract.run]: package:catalog_assets/testing.dart
abstract interface class BakeFrameSource {
  /// Calls [onFrame] once at the next frame.
  BakeFrameCancel requestFrame(BakeFrameCallback onFrame);
}

/// A monotonic clock, used to time one bake step.
typedef BakeClock = Duration Function();
