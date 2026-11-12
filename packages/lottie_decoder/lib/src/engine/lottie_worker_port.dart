import 'dart:typed_data';

/// The host's end of a Lottie worker: the one seam between the engine's
/// protocol and whatever carries the messages.
///
/// A browser `Worker` is one implementation (`JsLottieWorkerPort`, web only);
/// a scripted worker in memory is another (`FakeLottieWorker.port`), which is
/// how the protocol runs on the VM. Messages are the maps of the worker's
/// protocol (`chat_lottie_worker.js` in `lottie_native`), after structured
/// clone: strings, numbers, lists, maps and `Uint8List`s.
abstract interface class LottieWorkerPort {
  /// Sends [message] to the worker. Each buffer of [transfer] is handed over
  /// instead of copied, and is unusable here afterwards.
  void post(Map<String, Object?> message, {List<Uint8List> transfer});

  /// What the worker sends, in order. A broadcast stream: the engine listens
  /// before it posts anything, so no message is missed.
  Stream<Map<String, Object?>> get messages;

  /// Emits once for each way the worker itself fails: a script error, a
  /// message that could not be received, a worker that died. A failed worker
  /// answers nothing more.
  Stream<void> get failures;

  /// Ends the worker. Idempotent.
  void terminate();
}
