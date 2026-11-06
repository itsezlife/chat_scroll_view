import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

/// Starts the render isolate, which is the probe: it throws a [StateError]
/// naming why when the library is missing or speaks another version.
///
/// [spawn] is `IsolateLottieEngine.spawn` unless a test passes an engine of
/// its own. On failure it logs once and answers null, so nothing is registered
/// and vector animations keep their placeholder.
Future<({Decoder decoder, Future<void> Function() close})?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  Future<LottieEngine> Function() spawn = IsolateLottieEngine.spawn,
}) async {
  final LottieEngine engine;
  try {
    engine = await spawn();
    // The engine reports a library it cannot use as a StateError: that is
    // the probe's answer, not a bug to propagate.
    // ignore: avoid_catching_errors
  } on StateError catch (reason) {
    l.w('Lottie stickers are off: ${reason.message}');
    return null;
  }
  // One memory for the renderer and the atlas, native so the render isolate
  // can write it.
  final memory = NativeFramePageMemory(pageSide: FrameAtlas.defaultPageSide);
  final scheduler = LottieFrameScheduler(
    atlas: FrameAtlas<Object>(
      renderer: LottieFrameRenderer(engine, memory),
      memory: memory,
      memoryPressure: memoryPressure,
    ),
    clock: clock,
  );
  return (
    decoder: LottieDecoder(engine: engine, scheduler: scheduler),
    // The atlas goes first: its last batch may still be rendering. The engine
    // is closed before the memory, because its isolate writes into it and a
    // freed page under a running render would be a native fault. Not the
    // reverse of creation, on purpose.
    close: () async {
      scheduler.dispose();
      await engine.close();
      memory.dispose();
    },
  );
}
