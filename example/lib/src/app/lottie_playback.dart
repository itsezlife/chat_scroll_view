import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback_stub.dart'
    if (dart.library.ffi) 'package:chat_scroll_view_example/src/app/lottie_playback_native.dart'
    as platform;
import 'package:flutter/foundation.dart';

/// The Lottie decoder of a host that can run one, and how to stop what it
/// needs.
///
/// [close] frees the frame atlas, then the render engine, then the page memory
/// the engine writes: in that order, and idempotent. A [LottiePlayback] exists
/// only after the engine was probed by starting it; a host without the library
/// has none.
typedef LottiePlayback = ({Decoder decoder, Future<void> Function() close});

/// Starts the Lottie decoder over [clock] (the one the frame scheduler
/// follows) and [memoryPressure] (which releases the idle frames), or answers
/// null when this build cannot run one and the decoder must not be registered.
typedef LottiePlaybackStarter =
    Future<LottiePlayback?> Function({
      required PlaybackClock clock,
      required Listenable memoryPressure,
    });

/// The platform's [LottiePlaybackStarter]: the native library behind
/// `dart:ffi` where there is one, nothing on the web.
///
/// A platform fork is a file, not a condition: `dart:ffi` is not importable
/// in a web build, so the native file must not be reachable from it.
Future<LottiePlayback?> startLottiePlayback({
  required PlaybackClock clock,
  required Listenable memoryPressure,
}) => platform.start(clock: clock, memoryPressure: memoryPressure);
