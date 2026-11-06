import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// What both engines do with a binding and a frame codec on the isolate that
/// owns them, so the in-process engine and the render isolate cannot drift.
///
/// A codec that is null is an engine without one: frames render and carry no
/// bytes, and a restore fails.
abstract final class LottieEngineWork {
  /// Renders [jobs] and compresses the slot of each that rendered.
  static List<LottieCapture> renderCapturing(
    LottieBinding binding,
    LottieFrameCodec? codec,
    List<LottieEngineJob> jobs,
  ) {
    final statuses = binding.renderBatch([
      for (final job in jobs) job.toBindingJob(),
    ]);
    return [
      for (var i = 0; i < jobs.length; i++)
        LottieCapture(
          statuses[i],
          statuses[i] == LottieRenderStatus.ok
              ? codec?.compress(jobs[i].toRegion())
              : null,
        ),
    ];
  }

  /// Decompresses each job into its slot.
  static List<LottieRenderStatus> restore(
    LottieFrameCodec? codec,
    List<LottieRestoreJob> jobs,
  ) => [
    for (final job in jobs)
      codec != null && codec.decompress(job.compressed, job.toRegion())
          ? LottieRenderStatus.ok
          : LottieRenderStatus.failed,
  ];

  /// [codec] when it can run, else null.
  static LottieFrameCodec? usable(LottieFrameCodec? codec) =>
      codec != null && codec.isAvailable ? codec : null;
}
