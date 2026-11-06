import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback_stub.dart'
    if (dart.library.ffi) 'package:chat_scroll_view_example/src/app/lottie_playback_native.dart'
    if (dart.library.js_interop) 'package:chat_scroll_view_example/src/app/lottie_playback_web.dart'
    as platform;
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';

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
typedef LottiePlaybackStarter =
    Future<LottiePlayback?> Function({
      required PlaybackClock clock,
      required Listenable memoryPressure,
      String? cacheDirectory,
    });

/// The platform's [LottiePlaybackStarter]: the native library behind
/// `dart:ffi` where there is one, the WebAssembly worker behind
/// `dart:js_interop` on the web, nothing elsewhere.
///
/// A platform fork is a file, not a condition: `dart:ffi` is not importable
/// in a web build, so the native file must not be reachable from it.
Future<LottiePlayback?> startLottiePlayback({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  String? cacheDirectory,
}) => platform.start(
  clock: clock,
  memoryPressure: memoryPressure,
  cacheDirectory: cacheDirectory,
);

/// Where this platform keeps the cache of rendered frames, or null for none
/// (see `defaultCacheDirectory` in the native fork). Only `main` asks: a test
/// passes no folder and keeps the frames in memory.
String? defaultLottieCacheDirectory() => platform.defaultCacheDirectory();
