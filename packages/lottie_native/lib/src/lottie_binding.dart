import 'dart:ffi';
import 'dart:typed_data';

import 'package:lottie_native/src/lottie_availability.dart';
import 'package:lottie_native/src/lottie_handle.dart';
import 'package:lottie_native/src/lottie_load_result.dart';
import 'package:lottie_native/src/lottie_render_status.dart';

/// The native Lottie renderer as the host sees it: load a file, render frames
/// into page memory, dispose.
///
/// Contract that a native binding, a fake and a later web binding satisfy;
/// `NativeBindingContract` in `testing.dart` states the behaviour they share.
/// A binding is single-isolate state: calls come from the isolate that
/// created it unless the implementation says otherwise.
abstract interface class LottieBinding {
  /// Whether the native library loaded and speaks the ABI version this
  /// package expects, and why not when it does not.
  ///
  /// Decided once at construction, so it never changes.
  LottieAvailability get availability;

  /// Whether [availability] is [LottieAvailability.available].
  ///
  /// The host registers a binding only when it is available; [load] and
  /// [renderBatch] on one that is not throw a [StateError].
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

  /// Frees every live handle and retires the binding. Idempotent; [load] and
  /// [renderBatch] afterwards throw a [StateError], as on an unavailable
  /// binding, and [dispose] stays harmless.
  void close();
}

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

  /// The largest slot edge, in pixels, a renderer accepts; a decoder's size
  /// classes must not exceed it.
  static const int maxEdge = 512;

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
