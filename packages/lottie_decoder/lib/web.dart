/// The browser's end of the web Lottie engine: a module `Worker` over
/// `package:web`, and the one call that starts it with the engine.
///
/// Imported by a web build only (it needs `dart:js_interop`); everything else
/// of the web path, `WebWorkerLottieEngine` and `LottieWorkerPort` included,
/// is in `package:lottie_decoder/lottie_decoder.dart` and runs on the VM.
library;

export 'src/web/js_lottie_worker.dart';
export 'src/web/js_lottie_worker_port.dart';
