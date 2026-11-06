import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// A [LottieEngine] that forwards to another and counts the work it was given,
/// so a test can say "this pass rendered nothing" instead of inferring it.
final class CountingLottieEngine implements LottieEngine {
  /// Wraps [inner], which it does not own: [close] closes it too, as an
  /// engine's owner expects.
  CountingLottieEngine(this._inner);

  final LottieEngine _inner;

  /// Jobs sent to [renderBatch] and [renderCapturing] so far.
  int rendered = 0;

  /// Jobs sent to [restore] so far.
  int restored = 0;

  @override
  Future<LottieLoadResult> load(Uint8List bytes) => _inner.load(bytes);

  @override
  Future<List<LottieRenderStatus>> renderBatch(List<LottieEngineJob> jobs) {
    rendered += jobs.length;
    return _inner.renderBatch(jobs);
  }

  @override
  Future<List<LottieCapture>> renderCapturing(List<LottieEngineJob> jobs) {
    rendered += jobs.length;
    return _inner.renderCapturing(jobs);
  }

  @override
  Future<List<LottieRenderStatus>> restore(List<LottieRestoreJob> jobs) {
    restored += jobs.length;
    return _inner.restore(jobs);
  }

  @override
  Future<void> dispose(LottieHandle handle) => _inner.dispose(handle);

  @override
  Future<void> close() => _inner.close();
}
