import 'dart:io';

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
///
/// The rendered frames are kept in a `FrameCache`: on disk under
/// [cacheDirectory] when there is one, in memory only when it is null. The
/// playback owns the cache and disposes it on close.
Future<LottiePlayback?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  String? cacheDirectory,
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
  final memory = NativeFramePageMemory();
  final cache = FrameCache(
    directory: cacheDirectory == null ? null : Directory(cacheDirectory),
    // A cache that cannot touch its folder serves from memory; saying so once
    // is enough (the cache reports only the first failure).
    onError: (error, stackTrace) =>
        l.w('The Lottie frame cache is memory only: $error', stackTrace),
  );
  final scheduler = LottieFrameScheduler(
    atlas: FrameAtlas<Object>(
      renderer: LottieFrameRenderer(
        engine: engine,
        memory: memory,
        cache: cache,
      ),
      memory: memory,
      memoryPressure: memoryPressure,
    ),
    clock: clock,
  );
  // The atlas goes first: its last batch may still be rendering. The cache
  // goes before the engine: it finishes the writes under way, and a render
  // still in flight then finds it disposed and stores nothing. The engine is
  // closed before the memory, because its isolate writes into it and a freed
  // page under a running render would be a native fault. Not the reverse of
  // creation, on purpose.
  return LottiePlayback(
    decoder: LottieDecoder(engine: engine, scheduler: scheduler, cache: cache),
    shutdown: [scheduler.dispose, cache.dispose, engine.close, memory.dispose],
  );
}

/// Where this platform keeps the cache of rendered frames, or null where
/// there is no known folder (the frames are then kept in memory only).
///
/// The platform's user cache folder, read from the environment: macOS
/// `~/Library/Caches`, Linux `$XDG_CACHE_HOME` else `~/.cache`, Windows
/// `%LOCALAPPDATA%`. The example does not depend on `path_provider`, so
/// Android and iOS keep memory only; a host that does passes its own folder.
/// [operatingSystem] and [environment] default to the running process's.
String? defaultCacheDirectory({
  String? operatingSystem,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  const app = 'chat_scroll_view_example';
  const folder = 'lottie_frames';
  switch (os) {
    case 'macos':
      final home = env['HOME'];
      return home == null ? null : '$home/Library/Caches/$app/$folder';
    case 'linux':
      final base = env['XDG_CACHE_HOME'] ?? _under(env['HOME'], '.cache');
      return base == null ? null : '$base/$app/$folder';
    case 'windows':
      final base = env['LOCALAPPDATA'];
      return base == null ? null : '$base\\$app\\$folder';
    default:
      return null;
  }
}

String? _under(String? home, String child) =>
    home == null ? null : '$home/$child';
