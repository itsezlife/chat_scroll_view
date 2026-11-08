import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/engine/lottie_slot_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// A [LottieSlotEngine] that forwards to another and counts the work it was given,
/// so a test can say "this pass rendered nothing" instead of inferring it.
final class CountingLottieEngine implements LottieSlotEngine {
  /// Wraps [inner], which it does not own: [close] closes it too, as an
  /// engine's owner expects.
  CountingLottieEngine(this._inner);

  final LottieSlotEngine _inner;

  /// Jobs sent to [renderPixels], [renderBatch] and [renderCapturing] so far.
  int rendered = 0;

  /// Jobs sent to [restore] so far.
  int restored = 0;

  /// Renders sent to [writeTextures] so far.
  int texturesRendered = 0;

  /// Restores sent to [writeTextures] so far.
  int texturesRestored = 0;

  @override
  Future<LottieLoadResult> load(Uint8List bytes) => _inner.load(bytes);

  @override
  Future<List<LottiePixels?>> renderPixels(List<LottiePixelJob> jobs) {
    rendered += jobs.length;
    return _inner.renderPixels(jobs);
  }

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
  Future<List<LottieTextureResult>> writeTextures(
    FrameTextureEntryPoints entryPoints,
    FrameTextureFormat format,
    List<LottieTextureJob> jobs,
  ) {
    for (final job in jobs) {
      switch (job.work) {
        case LottieTextureRender():
          texturesRendered++;
        case LottieTextureRestore():
          texturesRestored++;
      }
    }
    return _inner.writeTextures(entryPoints, format, jobs);
  }

  @override
  Future<void> dispose(LottieHandle handle) => _inner.dispose(handle);

  @override
  Future<void> close() => _inner.close();
}
