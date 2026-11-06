import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/engine/lottie_slot_engine.dart';
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

  /// Renders [jobs] into temporary native buffers, one per job, and copies
  /// each frame that rendered out into a list of its own.
  ///
  /// A job whose size is invalid never gets a buffer (nothing is allocated
  /// for a size the binding would refuse), and a job the binding refuses
  /// (a disposed handle) is null; the others are unaffected.
  static List<LottiePixels?> renderPixels(
    LottieBinding binding,
    List<LottiePixelJob> jobs,
  ) {
    final pixels = List<LottiePixels?>.filled(jobs.length, null);
    final drawn = [
      for (var i = 0; i < jobs.length; i++)
        if (jobs[i].hasValidSize) i,
    ];
    if (drawn.isEmpty) return pixels;
    final buffers = [
      for (final i in drawn) calloc<Uint8>(jobs[i].width * jobs[i].height * 4),
    ];
    try {
      final statuses = binding.renderBatch([
        for (var k = 0; k < drawn.length; k++)
          LottieRenderJob(
            handle: jobs[drawn[k]].handle,
            frame: jobs[drawn[k]].frame,
            width: jobs[drawn[k]].width,
            height: jobs[drawn[k]].height,
            target: buffers[k],
            strideBytes: jobs[drawn[k]].width * 4,
          ),
      ]);
      for (var k = 0; k < drawn.length; k++) {
        if (statuses[k] != LottieRenderStatus.ok) continue;
        final job = jobs[drawn[k]];
        // A copy: the buffer is freed right below.
        pixels[drawn[k]] = Uint8List.fromList(
          buffers[k].asTypedList(job.width * job.height * 4),
        );
      }
    } finally {
      buffers.forEach(calloc.free);
    }
    return pixels;
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
