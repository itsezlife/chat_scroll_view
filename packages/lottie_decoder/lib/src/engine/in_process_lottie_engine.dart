import 'dart:ffi';
import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// A [LottieEngine] that runs a [LottieBinding] on the calling isolate; its
/// futures complete at once.
///
/// For tests (over `FakeLottieBinding`) and hosts that want no isolate.
final class InProcessLottieEngine implements LottieEngine {
  /// Creates an engine over [binding], which it owns and closes.
  InProcessLottieEngine(this._binding);

  final LottieBinding _binding;
  bool _closed = false;

  void _requireOpen() {
    if (_closed) throw StateError('The Lottie engine is closed.');
  }

  @override
  Future<LottieLoadResult> load(Uint8List bytes) async {
    _requireOpen();
    return _binding.load(bytes);
  }

  @override
  Future<List<LottieRenderStatus>> renderBatch(
    List<LottieEngineJob> jobs,
  ) async {
    _requireOpen();
    return _binding.renderBatch([
      for (final job in jobs)
        LottieRenderJob(
          handle: job.handle,
          frame: job.frame,
          width: job.width,
          height: job.height,
          target: Pointer<Uint8>.fromAddress(job.address),
          strideBytes: job.strideBytes,
        ),
    ]);
  }

  @override
  Future<void> dispose(LottieHandle handle) async {
    _requireOpen();
    _binding.dispose(handle);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _binding.close();
  }
}
