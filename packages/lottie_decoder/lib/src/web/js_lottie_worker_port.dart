import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_worker_port.dart';
import 'package:web/web.dart' as web;

/// A [LottieWorkerPort] over a browser module worker: the
/// `chat_lottie_worker.js` of `lottie_native`, started as
/// `new Worker(url, {type: 'module'})`.
///
/// Compile-checked only (`web_compile_test`): nothing in this repository runs
/// it in a browser. The worker and the wasm core it wraps are run in Node by
/// `lottie_native`'s own tests; this file is the part between them and Dart.
final class JsLottieWorkerPort implements LottieWorkerPort {
  /// Starts the worker at [workerUrl]; its `chat_lottie_core.mjs` must sit
  /// beside it. Throws what the browser throws for a url it refuses.
  JsLottieWorkerPort(Uri workerUrl)
    : _worker = web.Worker(
        workerUrl.toString().toJS,
        web.WorkerOptions(type: 'module'),
      ) {
    _worker
      ..addEventListener(
        'message',
        ((web.MessageEvent event) => _messages.add(_fromJs(event.data))).toJS,
      )
      // A script that failed to load or threw, and a message that could not
      // be deserialised: either way the worker answers nothing more.
      ..addEventListener('error', ((web.Event _) => _failures.add(null)).toJS)
      ..addEventListener(
        'messageerror',
        ((web.Event _) => _failures.add(null)).toJS,
      );
  }

  final web.Worker _worker;
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  final _failures = StreamController<void>.broadcast();

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Stream<void> get failures => _failures.stream;

  @override
  void post(
    Map<String, Object?> message, {
    List<Uint8List> transfer = const [],
  }) {
    _worker.postMessage(
      _toJs(message),
      <JSAny>[for (final buffer in transfer) buffer.buffer.toJS].toJS,
    );
  }

  @override
  void terminate() {
    _worker.terminate();
    unawaited(_messages.close());
    unawaited(_failures.close());
  }

  // --- Structured-clone values ---------------------------------------------

  /// Dart message value to JS: maps become objects, lists arrays, a
  /// `Uint8List` a `Uint8Array`. `jsify` alone would not take a typed array.
  static JSAny? _toJs(Object? value) => switch (value) {
    null => null,
    Uint8List() => value.toJS,
    Map() => _object(value),
    List() => <JSAny?>[for (final item in value) _toJs(item)].toJS,
    _ => value.jsify(),
  };

  static JSObject _object(Map<Object?, Object?> map) {
    final object = JSObject();
    for (final MapEntry(:key, :value) in map.entries) {
      object.setProperty('$key'.toJS, _toJs(value));
    }
    return object;
  }

  /// A worker message to the engine's map. `dartify` turns an object into a
  /// map and a `Uint8Array` into a `Uint8List`; a message that is not an
  /// object is dropped as an empty map (the engine ignores what it does not
  /// know).
  static Map<String, Object?> _fromJs(JSAny? data) {
    final value = data.dartify();
    return value is Map
        ? {for (final MapEntry(:key, :value) in value.entries) '$key': value}
        : const {};
  }
}
