import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:chat_scroll_view_example/src/app/environment_specific/lottie_playback.dart'
    as environment_specific;
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

/// The Lottie decoder of a host that can run one, and how to stop what it
/// needs.
///
/// A [LottiePlayback] exists only after the engine was probed by starting it;
/// a host without the library has none. [close] runs the [shutdown] steps in
/// the order given and only once; the platform file that built the playback
/// owns the order (the frame atlas, then the render engine, then the page
/// memory the engine writes).
final class LottiePlayback {
  /// Creates a playback of [decoder] that [close] stops by running [shutdown].
  LottiePlayback({
    required this.decoder,
    required List<FutureOr<void> Function()> shutdown,
  }) : _shutdown = List.unmodifiable(shutdown);

  /// The decoder to register for vector animation.
  final Decoder decoder;

  /// The platform's [LottiePlaybackStarter]: the native library behind
  /// `dart:ffi` where there is one, the WebAssembly worker behind
  /// `dart:js_interop` on the web.
  ///
  /// Decided by which file the build picks (the `$startLottiePlayback` hook):
  /// `dart:ffi` is not importable in a web build, so the native file must not
  /// be reachable from it.
  static Future<LottiePlayback?> start({
    required PlaybackClock clock,
    required Listenable memoryPressure,
    FrameTexturePool? textures,
    String? cacheDirectory,
  }) => environment_specific.$startLottiePlayback(
    clock: clock,
    memoryPressure: memoryPressure,
    textures: textures,
    cacheDirectory: cacheDirectory,
  );

  /// Where this platform keeps the cache of rendered frames, or null for none
  /// (see `$defaultLottieCacheDirectory` in the VM file). Only `main` asks: a
  /// test passes no folder and keeps the frames in memory.
  static String? defaultCacheDirectory() =>
      environment_specific.$defaultLottieCacheDirectory();

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
  static Future<LottiePlayback?> startPixel({
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

  /// Says, once, that the engine could not start and no decoder is
  /// registered: the one log line of "the probe failed", whichever platform
  /// probed, with the error's type so a missing library and a bug read apart.
  static void reportUnavailable(Object reason, StackTrace stackTrace) => l.w(
    'Lottie stickers are off (${reason.runtimeType}): $reason',
    stackTrace,
  );

  final List<FutureOr<void> Function()> _shutdown;
  Future<void>? _closing;

  /// Stops the playback. Idempotent: every call answers the same future.
  ///
  /// A step that fails does not skip the ones after it: the page memory must
  /// be freed even when the engine would not close. The first failure is
  /// rethrown once every step has run.
  Future<void> close() => _closing ??= _run();

  Future<void> _run() async {
    Object? failure;
    StackTrace? trace;
    for (final step in _shutdown) {
      try {
        await step();
        // Every step runs; the first failure is the one reported.
        // ignore: avoid_catches_without_on_clauses
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }
}

/// Starts the Lottie decoder over [clock] (the one the frame scheduler
/// follows) and [memoryPressure] (which releases the idle frames), or answers
/// null when this build cannot run one and the decoder must not be registered.
///
/// `cacheDirectory` is the folder the rendered frames are kept in between
/// launches; null keeps them in memory only. The playback owns that cache.
/// `textures` is the platform's texture pool (ADR 043), null where there is
/// none; a platform whose engine cannot write textures ignores it.
typedef LottiePlaybackStarter =
    Future<LottiePlayback?> Function({
      required PlaybackClock clock,
      required Listenable memoryPressure,
      FrameTexturePool? textures,
      String? cacheDirectory,
    });
