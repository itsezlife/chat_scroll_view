import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_lottie/web.dart';

/// The web hook behind [LottiePlayback.start]: starts the WebAssembly Lottie
/// worker, which is the probe: it throws a `LottieUnavailable` when the files
/// are not served beside the page (see `example/README.md`), and then nothing
/// is registered.
///
/// The files are resolved against the page's url. There is no cache folder:
/// the frames are kept in memory only, whatever [cacheDirectory] says, so
/// nothing counts against [bytesStore].
Future<LottiePlayback?> $startLottiePlayback({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  FrameTexturePool? textures,
  String? cacheDirectory,
  IBytesStore? bytesStore,
}) => LottiePlayback.startPixel(
  clock: clock,
  memoryPressure: memoryPressure,
  engineFactory: () => JsLottieWorker.spawnFromUrls(
    workerUrl: Uri.parse('lottie/chat_lottie_worker.js'),
    wasmUrl: Uri.parse('lottie/chat_lottie.wasm'),
    wasmNoSimdUrl: Uri.parse('lottie/chat_lottie.nosimd.wasm'),
  ),
);
