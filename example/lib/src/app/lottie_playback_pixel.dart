import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

/// Starts the Lottie decoder over a pixel-returning [LottieEngine], the form
/// of every host without native memory (the web), or answers null.
///
/// [engineFactory] is the probe: it throws a `LottieUnavailable` when the
/// engine cannot start. Neutral Dart on purpose, with no `dart:js_interop`,
/// so the composition runs on the VM in tests over an engine on a fake worker;
/// the web file supplies only the factory.
///
/// Memory is the Dart heap and there is no frame cache: frames are copied out
/// of the engine's pixels and kept for as long as the atlas holds them.
Future<LottiePlayback?> startPixelLottiePlayback({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  required Future<LottieEngine> Function() engineFactory,
}) async {
  final LottieEngine engine;
  try {
    engine = await engineFactory();
  } on Object catch (reason, stackTrace) {
    // The probe's answer, not a bug to propagate: whatever stopped the
    // engine starting, the app boots without stickers.
    LottiePlayback.reportUnavailable(reason, stackTrace);
    return null;
  }
  final memory = ListFramePageMemory();
  final scheduler = LottieFrameScheduler(
    atlas: FrameAtlas<Object>(
      renderer: PixelCopyFrameRenderer(engine),
      memory: memory,
      memoryPressure: memoryPressure,
    ),
    clock: clock,
  );
  // The atlas goes first: its last batch may still be rendering. Then the
  // engine, whose requests under way finish first. The memory is garbage
  // collected (nothing native writes into it), so it has no step: unlike the
  // native playback, where the engine's isolate writes into freed pages.
  return LottiePlayback(
    decoder: LottieDecoder(engine: engine, scheduler: scheduler),
    shutdown: [scheduler.dispose, engine.close],
  );
}
