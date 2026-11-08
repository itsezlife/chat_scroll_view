import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:chat_scroll_view_example/src/common/scroll_lab.dart';
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

/// The VM hook behind [LottiePlayback.start]: starts the render isolate,
/// which is the probe: it throws a [LottieUnavailable] naming why when the
/// library is missing or speaks another version.
///
/// [spawn] is `IsolateLottieEngine.spawn` unless a test passes an engine of
/// its own. The probe means "the engine could not start, for any reason": on
/// any failure it logs once, with the error's type, and answers null, so
/// nothing is registered and vector animations keep their placeholder.
///
/// The rendered frames are kept in a `FrameCache`: on disk under
/// [cacheDirectory] when there is one, in memory only when it is null. The
/// directory is the media store's (`MediaDiskCache`), which removes what goes
/// unused, so the cache keeps no disk budget of its own. The playback owns
/// the cache and disposes it on close.
///
/// With [textures] (ADR 043) the render isolate also writes playing
/// animations into the pool's platform textures; the scroll lab's `textures`
/// switch turns that off and on at run time.
Future<LottiePlayback?> $startLottiePlayback({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  FrameTexturePool? textures,
  String? cacheDirectory,
  Future<LottieSlotEngine> Function() spawn = IsolateLottieEngine.spawn,
}) async {
  final LottieSlotEngine engine;
  try {
    engine = await spawn();
  } on Object catch (reason, stackTrace) {
    // The probe's answer, not a bug to propagate: whatever stopped the
    // engine starting, the app boots without stickers.
    LottiePlayback.reportUnavailable(reason, stackTrace);
    return null;
  }
  // One memory for the renderer and the atlas, native so the render isolate
  // can write it.
  final memory = NativeFramePageMemory();
  final cache = FrameCache(
    directoryPath: cacheDirectory,
    diskBudgetBytes: null,
    // A cache that cannot touch its folder serves from memory; saying so once
    // is enough (the cache reports only the first failure).
    onError: (error, stackTrace) =>
        l.w('The Lottie frame cache is memory only: $error', stackTrace),
  );
  final renderer = LottieFrameRenderer(
    engine: engine,
    memory: memory,
    cache: cache,
    textureHost: textures?.host,
  );
  final scheduler = LottieFrameScheduler(
    atlas: FrameAtlas<Object>(
      renderer: renderer,
      memory: memory,
      memoryPressure: memoryPressure,
    ),
    clock: clock,
    textures: textures,
    textureWriter: textures == null ? null : renderer,
  )..texturesEnabled = ScrollLab.textures.value;
  void applyTextures() => scheduler.texturesEnabled = ScrollLab.textures.value;
  ScrollLab.textures.addListener(applyTextures);
  // The atlas goes first: its last batch may still be rendering. The cache
  // goes before the engine: it finishes the writes under way, and a render
  // still in flight then finds it disposed and stores nothing. The engine is
  // closed before the memory, because its isolate writes into it and a freed
  // page under a running render would be a native fault. Not the reverse of
  // creation, on purpose.
  return LottiePlayback(
    decoder: LottieDecoder(engine: engine, scheduler: scheduler, cache: cache),
    shutdown: [
      () => ScrollLab.textures.removeListener(applyTextures),
      scheduler.dispose,
      cache.dispose,
      engine.close,
      memory.dispose,
    ],
  );
}
