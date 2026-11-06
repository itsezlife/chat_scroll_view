import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/engine/lottie_engine_work.dart';
import 'package:lottie_decoder/src/engine/lottie_slot_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// A [LottieSlotEngine] that runs a [LottieBinding] on the calling isolate; its
/// futures complete at once.
///
/// For tests (over `FakeLottieBinding`) and hosts that want no isolate.
final class InProcessLottieEngine implements LottieSlotEngine {
  /// Creates an engine over [binding], which it owns and closes.
  ///
  /// [codec] compresses and restores frames for the frame cache; without one
  /// (or with one that is not available) frames render and carry no bytes.
  InProcessLottieEngine(this._binding, {LottieFrameCodec? codec})
    : _codec = LottieEngineWork.usable(codec);

  final LottieBinding _binding;
  final LottieFrameCodec? _codec;
  bool _closed = false;

  void _requireOpen() {
    if (_closed) throw LottieEngineClosed();
  }

  @override
  Future<LottieLoadResult> load(Uint8List bytes) async {
    _requireOpen();
    return _binding.load(bytes);
  }

  @override
  Future<List<LottiePixels?>> renderPixels(List<LottiePixelJob> jobs) async {
    _requireOpen();
    return LottieEngineWork.renderPixels(_binding, jobs);
  }

  @override
  Future<List<LottieRenderStatus>> renderBatch(
    List<LottieEngineJob> jobs,
  ) async {
    _requireOpen();
    return _binding.renderBatch([for (final job in jobs) job.toBindingJob()]);
  }

  @override
  Future<List<LottieCapture>> renderCapturing(
    List<LottieEngineJob> jobs,
  ) async {
    _requireOpen();
    return LottieEngineWork.renderCapturing(_binding, _codec, jobs);
  }

  @override
  Future<List<LottieRenderStatus>> restore(List<LottieRestoreJob> jobs) async {
    _requireOpen();
    return LottieEngineWork.restore(_codec, jobs);
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
