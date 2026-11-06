import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/video_playback_stub.dart'
    if (dart.library.ffi) 'package:chat_scroll_view_example/src/app/video_playback_native.dart'
    if (dart.library.js_interop) 'package:chat_scroll_view_example/src/app/video_playback_web.dart'
    as platform;
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';

/// The video decoder of a host that can run one, and how to stop what it
/// needs.
///
/// A [VideoPlayback] exists only after the engine was probed by starting it;
/// a host without the library has none. [close] runs the [shutdown] steps in
/// the order given and only once; the platform file that built the playback
/// owns the order (the frame scheduler, then the engine it decodes with).
///
/// This is the shape of `LottiePlayback`, written out again rather than
/// shared: two facades are not yet a repetition worth a third type, and the
/// two differ in what they own (a cache and page memory there, nothing here).
final class VideoPlayback {
  /// Creates a playback of [decoder] that [close] stops by running [shutdown].
  VideoPlayback({
    required this.decoder,
    required List<FutureOr<void> Function()> shutdown,
  }) : _shutdown = List.unmodifiable(shutdown);

  /// The decoder to register for video-coded media.
  final Decoder decoder;

  /// Says, once, that the engine could not start and no decoder is
  /// registered: the one log line of "the probe failed", with the error's
  /// type so a missing library and a bug read apart.
  static void reportUnavailable(Object reason, StackTrace stackTrace) => l.w(
    'Video stickers are off (${reason.runtimeType}): $reason',
    stackTrace,
  );

  final List<FutureOr<void> Function()> _shutdown;
  Future<void>? _closing;

  /// Stops the playback. Idempotent: every call answers the same future.
  ///
  /// A step that fails does not skip the ones after it: the engine must be
  /// disposed even when the scheduler would not stop. The first failure is
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

/// Starts the video decoder over [clock] (the one the frame scheduler
/// follows) and [memoryPressure] (which releases the idle frames), or answers
/// null when this build cannot run one and the decoder must not be registered.
typedef VideoPlaybackStarter =
    Future<VideoPlayback?> Function({
      required PlaybackClock clock,
      required Listenable memoryPressure,
    });

/// The platform's [VideoPlaybackStarter]: the native library behind
/// `dart:ffi` where there is one, the browser's own `<video>` element behind
/// `dart:js_interop` on the web, nothing elsewhere.
///
/// A platform fork is a file, not a condition: `dart:ffi` is not importable
/// in a web build, so the native file must not be reachable from it.
Future<VideoPlayback?> startVideoPlayback({
  required PlaybackClock clock,
  required Listenable memoryPressure,
}) => platform.start(clock: clock, memoryPressure: memoryPressure);
