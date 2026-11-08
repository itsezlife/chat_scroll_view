import 'dart:ffi';
import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
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

  /// Writes every job into its platform texture (ADR 043, "Writing"), on the
  /// isolate that owns the binding: locks the texture through [entryPoints],
  /// clears its margins, draws or restores the frame centred at the lock's
  /// stride, swaps red and blue when [format] is not the engine's RGBA, and
  /// posts.
  ///
  /// One [LottieTextureResult] per job, in job order: a texture that cannot be
  /// locked at once is [TextureFrameOutcome.notLocked] and untouched; a job the
  /// engine cannot draw (or bytes it cannot restore) is
  /// [TextureFrameOutcome.failed], its texture posted all the same, since a
  /// post is what ends a lock. A captured render carries its compressed
  /// pixels, in the engine's order, for the frame cache.
  Future<List<LottieTextureResult>> writeTextures(
    FrameTextureEntryPoints entryPoints,
    FrameTextureFormat format,
    List<LottieTextureJob> jobs,
  );
}

/// One frame to write into a platform texture by its id; the render isolate
/// locks it.
@immutable
final class LottieTextureJob {
  /// Creates a job that does [work] into [texture], the frame [width] x
  /// [height] pixels.
  const LottieTextureJob({
    required this.texture,
    required this.width,
    required this.height,
    required this.work,
  });

  /// The texture: its id and its size.
  final AssetTexture texture;

  /// Pixels of a row of the frame, at most the texture's width.
  final int width;

  /// Rows of the frame, at most the texture's height.
  final int height;

  /// What goes into the frame.
  final LottieTextureWork work;
}

/// What a [LottieTextureJob] puts into its frame: a closed set.
sealed class LottieTextureWork {
  const LottieTextureWork();
}

/// Draws [frame] of [handle]; with [capture] the result also carries the
/// frame compressed for the cache.
final class LottieTextureRender extends LottieTextureWork {
  /// Creates the work.
  const LottieTextureRender(
    this.handle, {
    required this.frame,
    this.capture = false,
  });

  /// The animation to draw.
  final LottieHandle handle;

  /// The frame; fractions are allowed.
  final double frame;

  /// Whether to compress what was drawn.
  final bool capture;
}

/// Writes a frame [LottieSlotEngine.renderCapturing] (or a capturing texture
/// render) compressed.
final class LottieTextureRestore extends LottieTextureWork {
  /// Creates the work.
  const LottieTextureRestore(this.compressed);

  /// The compressed frame.
  final Uint8List compressed;
}

/// How one [LottieTextureJob] ended.
@immutable
final class LottieTextureResult {
  /// Creates a result.
  const LottieTextureResult(this.outcome, [this.compressed]);

  /// Whether the frame was posted, skipped or failed.
  final TextureFrameOutcome outcome;

  /// The drawn frame compressed, for a posted capturing render with a codec;
  /// else null.
  final Uint8List? compressed;
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
