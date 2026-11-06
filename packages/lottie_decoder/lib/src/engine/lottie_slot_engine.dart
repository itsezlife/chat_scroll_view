import 'dart:ffi';
import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:meta/meta.dart';

/// A [LottieEngine] that can also draw straight into native page memory by
/// address: the zero-copy path of the in-process and isolate engines.
///
/// Native only (it needs `dart:ffi`); the barrel does not export it where
/// there is none. A host that wants the frame cache or zero-copy rendering
/// holds a slot engine, any other code holds a [LottieEngine].
abstract interface class LottieSlotEngine implements LottieEngine {
  /// Renders every job; one status per job, in job order.
  Future<List<LottieRenderStatus>> renderBatch(List<LottieEngineJob> jobs);

  /// Renders like [renderBatch] and, for every job that rendered, also
  /// returns the slot's pixels compressed, for the frame cache.
  ///
  /// One [LottieCapture] per job, in job order. Where the engine has no frame
  /// codec the frames still render and carry no bytes.
  Future<List<LottieCapture>> renderCapturing(List<LottieEngineJob> jobs);

  /// Writes each job's compressed frame into its slot: [LottieRenderStatus.ok],
  /// or [LottieRenderStatus.failed] for corrupt data, data of another size or
  /// an engine without a frame codec, in which case the slot is unchanged.
  /// One status per job, in job order.
  Future<List<LottieRenderStatus>> restore(List<LottieRestoreJob> jobs);
}

/// One frame to draw: a [LottieRenderJob] whose target is a raw address, an
/// `int` because it crosses isolates.
@immutable
final class LottieEngineJob {
  /// Creates a job.
  const LottieEngineJob({
    required this.handle,
    required this.frame,
    required this.width,
    required this.height,
    required this.address,
    required this.strideBytes,
  });

  /// The animation to draw.
  final LottieHandle handle;

  /// The frame; fractions are allowed.
  final double frame;

  /// The slot width in pixels.
  final int width;

  /// The slot height in pixels.
  final int height;

  /// The address of the slot's top-left pixel.
  final int address;

  /// The distance in bytes between the starts of two rows.
  final int strideBytes;

  /// The binding's own job, with [address] turned back into a pointer. An
  /// engine calls it on the isolate that owns the binding.
  LottieRenderJob toBindingJob() => LottieRenderJob(
    handle: handle,
    frame: frame,
    width: width,
    height: height,
    target: Pointer<Uint8>.fromAddress(address),
    strideBytes: strideBytes,
  );

  /// The slot this job writes, as the frame codec reads it.
  LottieFrameRegion toRegion() => LottieFrameRegion(
    target: Pointer<Uint8>.fromAddress(address),
    width: width,
    height: height,
    strideBytes: strideBytes,
  );
}

/// What [LottieSlotEngine.renderCapturing] made of one job.
@immutable
final class LottieCapture {
  /// Creates a capture of a job that ended with [status].
  const LottieCapture(this.status, [this.compressed]);

  /// How the render ended.
  final LottieRenderStatus status;

  /// The slot's pixels compressed; null when the job did not render or the
  /// engine has no frame codec.
  final Uint8List? compressed;
}

/// One compressed frame to write back into a slot.
@immutable
final class LottieRestoreJob {
  /// Creates a job.
  const LottieRestoreJob({
    required this.compressed,
    required this.width,
    required this.height,
    required this.address,
    required this.strideBytes,
  });

  /// What [LottieSlotEngine.renderCapturing] returned for the frame.
  final Uint8List compressed;

  /// The slot width in pixels.
  final int width;

  /// The slot height in pixels.
  final int height;

  /// The address of the slot's top-left pixel.
  final int address;

  /// The distance in bytes between the starts of two rows.
  final int strideBytes;

  /// The slot this job writes, as the frame codec writes it.
  LottieFrameRegion toRegion() => LottieFrameRegion(
    target: Pointer<Uint8>.fromAddress(address),
    width: width,
    height: height,
    strideBytes: strideBytes,
  );
}
