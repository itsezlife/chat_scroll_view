// What the barrel exports where there is no `dart:js_interop`: nothing. The
// browser worker port and `JsLottieWorker` need a browser; on the VM the web
// engine runs over `FakeLottieWorker` (or any `LottieWorkerPort`) instead.
