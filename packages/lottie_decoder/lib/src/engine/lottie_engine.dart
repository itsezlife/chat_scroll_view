import 'dart:typed_data';

import 'package:lottie_native/lottie_native.dart';
import 'package:meta/meta.dart';

/// The pixels of one rendered frame: tightly packed premultiplied RGBA, byte
/// order `[R, G, B, A]`, rows `width * 4` bytes apart, exactly
/// `width * height * 4` bytes.
typedef LottiePixels = Uint8List;

/// The async, pixel-returning face of a Lottie renderer.
///
/// The one seam every platform has: a native engine draws into memory and
/// copies out, the web engine (WebAssembly in a worker) transfers the bytes
/// it drew. Handles, results and statuses are the binding's own; an engine
/// adds the asynchrony and the pixel job. What only a native engine can do,
/// drawing straight into page memory by address, is a [LottieSlotEngine].
abstract interface class LottieEngine {
  /// Parses [bytes]; a refused file is a [LottieRejected], never a throw.
  Future<LottieLoadResult> load(Uint8List bytes);

  /// Renders every job; one entry per job, in job order: its [LottiePixels],
  /// or null for a job that did not render (a disposed handle, an invalid
  /// size, a renderer failure). Never throws for one bad job.
  Future<List<LottiePixels?>> renderPixels(List<LottiePixelJob> jobs);

  /// Releases [handle]. Idempotent.
  Future<void> dispose(LottieHandle handle);

  /// Retires the engine and what it holds. Requests already made run to
  /// completion first, so no native code writes to a caller's memory after
  /// its future completes. Idempotent; every other call
  /// afterwards throws a [LottieEngineClosed].
  Future<void> close();
}

/// One frame to draw and return as pixels.
@immutable
final class LottiePixelJob {
  /// Creates a job.
  const LottiePixelJob({
    required this.handle,
    required this.frame,
    required this.width,
    required this.height,
  });

  /// The largest edge, in pixels, an engine renders; the same limit as
  /// `LottieRenderJob.maxEdge`, repeated here because that type needs
  /// `dart:ffi` and this one compiles for the web. A native test holds the
  /// two equal.
  static const int maxEdge = 512;

  /// The animation to draw.
  final LottieHandle handle;

  /// The frame; fractions are allowed.
  final double frame;

  /// The width in pixels, from 1 to [maxEdge].
  final int width;

  /// The height in pixels, from 1 to [maxEdge].
  final int height;

  /// Whether the size can be rendered at all; an engine answers null to a job
  /// that is not, before it allocates anything for it.
  bool get hasValidSize =>
      width >= 1 && width <= maxEdge && height >= 1 && height <= maxEdge;
}

/// An engine was used after it closed (or after its isolate ended): the
/// handles it issued are gone with it, so a caller freeing one may ignore
/// this and nothing else.
///
/// A [StateError] so code that only wants "unusable engine" keeps working;
/// a catch site that must tell this case apart matches this type, never the
/// bare [StateError].
final class LottieEngineClosed extends StateError {
  /// Creates the error; [message] says which way the engine ended.
  LottieEngineClosed([super.message = 'The Lottie engine is closed.']);
}

/// The render isolate or worker could not serve: its binding reported
/// [availability] other than `available`. The host does not register the
/// decoder.
final class LottieUnavailable extends StateError {
  /// Creates the error for a binding that reported [availability]; [reason]
  /// is what the binding said, when it said anything.
  LottieUnavailable(this.availability, {this.reason})
    : super(
        'The Lottie binding is not available in the render isolate: '
        '${availability.name}'
        '${reason == null ? '' : ' ($reason)'}.',
      );

  /// Why the binding cannot serve.
  final LottieAvailability availability;

  /// The binding's own words (a worker's `unavailable` reason), when it gave
  /// any.
  final String? reason;
}
