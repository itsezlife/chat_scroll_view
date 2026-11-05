import 'dart:ffi';
import 'dart:typed_data';

import 'package:lottie_native/src/lottie_load_result.dart';

/// The native Lottie renderer as the host sees it: load a file, render frames
/// into page memory, dispose.
///
/// Contract that a native binding, a fake and a later web binding satisfy;
/// `NativeBindingContract` in `testing.dart` states the behaviour they share.
/// A binding is single-isolate state: calls come from the isolate that
/// created it unless the implementation says otherwise.
abstract interface class LottieBinding {
  /// Whether the native library loaded and speaks the ABI version this
  /// package expects.
  ///
  /// Decided once at construction, so it never changes. The host registers a
  /// binding only when it is available; [load] and [renderBatch] on one that
  /// is not throw a [StateError].
  bool get isAvailable;

  /// Parses [bytes] (gzip or JSON).
  ///
  /// Never throws for bad data: a refused file is a [LottieRejected].
  LottieLoadResult load(Uint8List bytes);

  /// Renders every job into its target and returns one status per job, in job
  /// order. A bad job never stops the others.
  List<LottieRenderStatus> renderBatch(List<LottieRenderJob> jobs);

  /// Releases [handle]. Idempotent; a disposed handle is refused by
  /// [renderBatch] with [LottieRenderStatus.badArgument].
  void dispose(LottieHandle handle);
}

/// An opaque reference to a loaded animation.
///
/// An integer, not a pointer, so a fake and a web binding can issue them too.
extension type const LottieHandle(int id) {}

/// One frame to draw into a slot of page memory.
final class LottieRenderJob {
  /// Creates a job.
  ///
  /// The `Pointer` limits jobs to the VM; the web binding revisits this
  /// behind a conditional import.
  const LottieRenderJob({
    required this.handle,
    required this.frame,
    required this.width,
    required this.height,
    required this.target,
    required this.strideBytes,
  });

  /// The animation to draw.
  final LottieHandle handle;

  /// The frame, in `[0, frameCount)`; fractions are allowed.
  final double frame;

  /// The slot width in pixels.
  final int width;

  /// The slot height in pixels.
  final int height;

  /// The slot's top-left pixel inside page memory. Premultiplied RGBA, byte
  /// order `[R, G, B, A]`.
  final Pointer<Uint8> target;

  /// The distance in bytes between the starts of two rows.
  final int strideBytes;
}

/// What happened to one [LottieRenderJob].
enum LottieRenderStatus {
  /// The slot holds the frame.
  ok,

  /// An unknown or disposed handle, a null target or an invalid frame.
  badArgument,

  /// A zero size, or a stride under the row width.
  badSize,

  /// The renderer failed on this job.
  failed,
}
