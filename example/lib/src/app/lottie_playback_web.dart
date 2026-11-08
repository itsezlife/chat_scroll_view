import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback_pixel.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie_decoder/web.dart';

/// Starts the WebAssembly Lottie worker, which is the probe: it throws a
/// `LottieUnavailable` when the files are not served beside the page (see
/// `example/README.md`), and then nothing is registered.
///
/// The files are resolved against the page's url. There is no cache folder:
/// the frames are kept in memory only, whatever [cacheDirectory] says.
Future<LottiePlayback?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  FrameTexturePool? textures,
  String? cacheDirectory,
}) => startPixelLottiePlayback(
  clock: clock,
  memoryPressure: memoryPressure,
  engineFactory: () => JsLottieWorker.spawnFromUrls(
    workerUrl: Uri.parse('lottie/chat_lottie_worker.js'),
    wasmUrl: Uri.parse('lottie/chat_lottie.wasm'),
    wasmNoSimdUrl: Uri.parse('lottie/chat_lottie.nosimd.wasm'),
  ),
);

/// There is no folder to keep frames in.
String? defaultCacheDirectory() => null;
