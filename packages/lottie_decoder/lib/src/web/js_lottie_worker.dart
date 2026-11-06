import 'package:lottie_decoder/src/engine/web_worker_lottie_engine.dart';
import 'package:lottie_decoder/src/web/js_lottie_worker_port.dart';

/// Starting the web engine in a browser.
///
/// A namespace and not a static on [WebWorkerLottieEngine]: that class is
/// neutral Dart that compiles (and is tested) on the VM, and a static that
/// starts a browser worker would drag `dart:js_interop` into it.
abstract final class JsLottieWorker {
  /// Starts the worker at [workerUrl] and a [WebWorkerLottieEngine] over it.
  ///
  /// [wasmUrl] and [wasmNoSimdUrl] are the two builds of the module; the
  /// worker fetches the one the browser can run. Relative urls are resolved
  /// against the page, here, so that the worker (whose own base is its
  /// script's url) fetches what the host meant.
  ///
  /// Throws a `LottieUnavailable` when the worker cannot be made ready; see
  /// [WebWorkerLottieEngine.spawn]. The three files come from
  /// `dart native/tool/build_web.dart` of `lottie_native`.
  static Future<WebWorkerLottieEngine> spawnFromUrls({
    required Uri workerUrl,
    required Uri wasmUrl,
    required Uri wasmNoSimdUrl,
  }) => WebWorkerLottieEngine.spawn(
    JsLottieWorkerPort(Uri.base.resolveUri(workerUrl)),
    wasmUrl: Uri.base.resolveUri(wasmUrl),
    wasmNoSimdUrl: Uri.base.resolveUri(wasmNoSimdUrl),
  );
}
