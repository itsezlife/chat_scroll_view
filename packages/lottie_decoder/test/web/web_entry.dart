// Compiled to JavaScript by web_compile_test.dart, never run: it only has to
// build the neutral decode path through the public barrel, over an engine
// that returns pixels and nothing else, and the web engine with its browser
// worker port.
import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/web.dart';
import 'package:lottie_native/lottie_native.dart';

/// The engine a web host has: no slot method, only pixels.
final class _PixelEngine implements LottieEngine {
  @override
  Future<LottieLoadResult> load(Uint8List bytes) async =>
      const LottieRejected(LottieRejection.malformed);

  @override
  Future<List<LottiePixels?>> renderPixels(List<LottiePixelJob> jobs) async => [
    for (final _ in jobs) null,
  ];

  @override
  Future<void> dispose(LottieHandle handle) async {}

  @override
  Future<void> close() async {}
}

void main() {
  final engine = _PixelEngine();
  final memory = ListFramePageMemory();
  final scheduler = LottieFrameScheduler(
    atlas: FrameAtlas<Object>(
      renderer: PixelCopyFrameRenderer(engine),
      memory: memory,
    ),
    clock: PlaybackClock(),
  );
  final decoder = LottieDecoder(
    engine: engine,
    scheduler: scheduler,
    cache: FrameCache(directoryPath: null),
  );
  // The web engine and its browser constructor: built, never started.
  // ignore: avoid_print
  print([
    decoder,
    LottieFrameSize,
    LottiePixelJob.maxEdge,
    WebWorkerLottieEngine.spawn,
    JsLottieWorker.spawnFromUrls,
    JsLottieWorkerPort,
  ]);
}
