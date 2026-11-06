// The part of the public API that needs `dart:js_interop`. The barrel exports
// the stub by default and this file where `dart.library.js_interop` is true
// (every web compiler), so a VM build never reaches `package:web`.
export 'package:lottie_decoder/src/web/js_lottie_worker.dart';
export 'package:lottie_decoder/src/web/js_lottie_worker_port.dart';
