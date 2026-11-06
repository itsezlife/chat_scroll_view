import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

/// Starts the render isolate, which is the probe: it throws a
/// [LottieUnavailable] naming why when the library is missing or speaks
/// another version.
///
/// [spawn] is `IsolateLottieEngine.spawn` unless a test passes an engine of
/// its own. The probe means "the engine could not start, for any reason": on
/// any failure it logs once, with the error's type, and answers null, so
/// nothing is registered and vector animations keep their placeholder.
Future<LottiePlayback?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  Future<LottieEngine> Function() spawn = IsolateLottieEngine.spawn,
}) async {
  final LottieEngine engine;
  try {
    engine = await spawn();
  } on Object catch (reason, stackTrace) {
    // The probe's answer, not a bug to propagate: whatever stopped the
    // engine starting, the app boots without stickers.
    l.w('Lottie stickers are off (${reason.runtimeType}): $reason', stackTrace);
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
  // The atlas goes first: its last batch may still be rendering. The engine
  // is closed before the memory, because its isolate writes into it and a
  // freed page under a running render would be a native fault. Not the
  // reverse of creation, on purpose.
  return LottiePlayback(
    decoder: LottieDecoder(engine: engine, scheduler: scheduler),
    shutdown: [scheduler.dispose, engine.close, memory.dispose],
  );
}
