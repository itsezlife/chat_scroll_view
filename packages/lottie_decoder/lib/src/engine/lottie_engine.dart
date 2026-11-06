import 'dart:typed_data';

import 'package:lottie_native/lottie_native.dart';
import 'package:meta/meta.dart';

/// The async face of a [LottieBinding].
///
/// The real binding lives on another isolate, so every call is a `Future`.
/// Handles, results and statuses are the binding's own; an engine adds only
/// the asynchrony and the address-based job.
abstract interface class LottieEngine {
  /// Parses [bytes]; a refused file is a [LottieRejected], never a throw.
  Future<LottieLoadResult> load(Uint8List bytes);

  /// Renders every job; one status per job, in job order.
  Future<List<LottieRenderStatus>> renderBatch(List<LottieEngineJob> jobs);

  /// Releases [handle]. Idempotent.
  Future<void> dispose(LottieHandle handle);

  /// Retires the engine and what it holds. Idempotent; every other call
  /// afterwards throws a [LottieEngineClosed].
  Future<void> close();
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

/// The render isolate could not serve: its binding reported [availability]
/// other than `available`. The host does not register the decoder.
final class LottieUnavailable extends StateError {
  /// Creates the error for a binding that reported [availability].
  LottieUnavailable(this.availability)
    : super(
        'The Lottie binding is not available in the render isolate: '
        '${availability.name}.',
      );

  /// Why the binding cannot serve.
  final LottieAvailability availability;
}
