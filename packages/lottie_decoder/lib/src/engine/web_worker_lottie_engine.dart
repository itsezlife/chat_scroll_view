import 'dart:async';
import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/engine/lottie_worker_port.dart';
import 'package:lottie_native/lottie_native.dart';

/// The status numbers the worker answers with: `include/chat_lottie.h` of
/// `lottie_native`, which the worker passes through untouched. Repeated here
/// because the header's own Dart copy (`ChatLottieStatus`) sits behind
/// `dart:ffi`; `lottie_worker_status_test` parses the header and fails if one
/// of these drifts.
abstract final class LottieWorkerStatus {
  /// The call succeeded.
  static const ok = 0;

  /// load: the encoded or inflated input is over its cap.
  static const tooLarge = -2;

  /// load: not gzip, not JSON, a parse error.
  static const malformed = -3;

  /// load: a renderer limit tripped.
  static const limitExceeded = -4;

  /// load: nothing to draw, or a non-finite frame rate.
  static const unsupported = -5;

  /// A panic caught at the wrapper's boundary: a bug, not the file's fault.
  static const internal = -6;

  /// render: a zero or oversized edge, or a bad stride.
  static const badSize = -7;

  /// The rejection a load [status] stands for; any other non-zero status
  /// reads as a bad file, as it does in the native binding.
  static LottieRejection rejectionFor(int status) => switch (status) {
    tooLarge => LottieRejection.tooLarge,
    limitExceeded => LottieRejection.limitExceeded,
    unsupported => LottieRejection.unsupported,
    internal => LottieRejection.internal,
    _ => LottieRejection.malformed,
  };
}

/// A [LottieEngine] over a Lottie worker: WebAssembly in a browser worker
/// that draws the frames and transfers their pixels back.
///
/// The protocol is the one documented at the top of `chat_lottie_worker.js`
/// in `lottie_native`. Requests are posted in call order, at once, each under
/// its own `id`; the worker serves them one at a time in arrival order, but
/// replies are matched by `id`, never by position, so the engine does not
/// depend on that order.
final class WebWorkerLottieEngine implements LottieEngine {
  WebWorkerLottieEngine._(this._port, this.simd) {
    _subscriptions = [
      _port.messages.listen(_onMessage),
      _port.failures.listen((_) => _onWorkerEnded()),
    ];
  }

  static const _workerEnded = 'the worker ended';

  final LottieWorkerPort _port;

  /// Whether the worker runs the SIMD build of the module.
  final bool simd;

  late final List<StreamSubscription<void>> _subscriptions;
  final _pending = <int, Completer<Map<Object?, Object?>>>{};
  var _nextId = 1;
  Future<void>? _closing;
  var _ended = false;

  /// Starts the protocol over [port]: posts `init` with both wasm urls and
  /// waits for the worker's `ready`.
  ///
  /// Throws a [LottieUnavailable] (and terminates the worker) when the worker
  /// answers `unavailable`, fails before it is ready, or says nothing within
  /// [readyTimeout].
  static Future<WebWorkerLottieEngine> spawn(
    LottieWorkerPort port, {
    required Uri wasmUrl,
    required Uri wasmNoSimdUrl,
    Duration readyTimeout = const Duration(seconds: 10),
  }) async {
    final ready = Completer<bool>();
    void fail(String reason) {
      if (!ready.isCompleted) {
        ready.completeError(
          LottieUnavailable(LottieAvailability.missingLibrary, reason: reason),
        );
      }
    }

    final subscriptions = [
      port.messages.listen((message) {
        switch (message['type']) {
          case 'ready':
            if (!ready.isCompleted) ready.complete(message['simd'] == true);
          case 'unavailable':
            fail('${message['reason']}');
        }
      }),
      port.failures.listen(
        (_) => fail('the worker failed before it was ready'),
      ),
    ];
    port.post({
      'type': 'init',
      'wasmUrl': wasmUrl.toString(),
      'wasmNoSimdUrl': wasmNoSimdUrl.toString(),
    });
    try {
      final simd = await ready.future.timeout(
        readyTimeout,
        onTimeout: () => throw LottieUnavailable(
          LottieAvailability.missingLibrary,
          reason: 'the worker was not ready within $readyTimeout',
        ),
      );
      return WebWorkerLottieEngine._(port, simd);
    } on Object {
      port.terminate();
      rethrow;
    } finally {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    }
  }

  // --- Requests and replies ------------------------------------------------

  void _requireOpen() {
    if (_ended || _closing != null) throw LottieEngineClosed();
  }

  Future<Map<Object?, Object?>> _post(
    String type, [
    Map<String, Object?> fields = const {},
  ]) {
    final id = _nextId++;
    final reply = Completer<Map<Object?, Object?>>();
    _pending[id] = reply;
    _port.post({'id': id, 'type': type, ...fields});
    return reply.future;
  }

  void _onMessage(Map<String, Object?> message) {
    final id = message['id'];
    final reply = id is num ? _pending.remove(id.toInt()) : null;
    if (reply == null) return;
    if (message['ok'] == true) {
      reply.complete(message);
    } else {
      reply.completeError(LottieWorkerError('${message['error']}'));
    }
  }

  /// The worker failed or died: nothing it was asked will be answered.
  void _onWorkerEnded() {
    if (_ended) return;
    _end();
    final pending = [..._pending.values];
    _pending.clear();
    for (final reply in pending) {
      reply.completeError(LottieEngineClosed(_workerEnded));
    }
  }

  void _end() {
    _ended = true;
    _port.terminate();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }

  // --- LottieEngine --------------------------------------------------------

  @override
  Future<LottieLoadResult> load(Uint8List bytes) async {
    _requireOpen();
    // A view's whole buffer would be cloned with it: send exactly the bytes.
    final exact = bytes.lengthInBytes == bytes.buffer.lengthInBytes
        ? bytes
        : Uint8List.fromList(bytes);
    final reply = await _post('load', {'bytes': exact});
    final status = (reply['status']! as num).toInt();
    if (status != LottieWorkerStatus.ok) {
      return LottieRejected(LottieWorkerStatus.rejectionFor(status));
    }
    final info = reply['info']! as Map<Object?, Object?>;
    int field(String name) => (info[name]! as num).toInt();
    return LottieLoaded(
      LottieHandle(field('handle')),
      LottieInfo(
        width: field('width'),
        height: field('height'),
        frameCount: field('frameCount'),
        frameRate: (info['frameRate']! as num).toDouble(),
        features: LottieFeatures(field('features')),
      ),
    );
  }

  @override
  Future<List<LottiePixels?>> renderPixels(List<LottiePixelJob> jobs) async {
    _requireOpen();
    // A job that cannot render is answered null here, without a round trip.
    final sent = [
      for (final job in jobs)
        if (job.hasValidSize) job,
    ];
    final results = <LottiePixels?>[];
    if (sent.isNotEmpty) {
      final reply = await _post('render', {
        'jobs': [
          for (final job in sent)
            {
              'handle': job.handle.id,
              'frame': job.frame,
              'width': job.width,
              'height': job.height,
            },
        ],
      });
      final answers = reply['results']! as List<Object?>;
      for (var i = 0; i < sent.length; i++) {
        results.add(
          i < answers.length ? _pixelsOf(answers[i]! as Map, sent[i]) : null,
        );
      }
    }
    var next = 0;
    return [for (final job in jobs) job.hasValidSize ? results[next++] : null];
  }

  /// The pixels of one result, or null when the job failed or the buffer is
  /// not exactly `width * height * 4` bytes (a failed job, never a throw).
  static LottiePixels? _pixelsOf(
    Map<Object?, Object?> answer,
    LottiePixelJob job,
  ) {
    final pixels = answer['pixels'];
    final ok = answer['status'] == LottieWorkerStatus.ok;
    return ok &&
            pixels is Uint8List &&
            pixels.length == job.width * job.height * 4
        ? pixels
        : null;
  }

  @override
  Future<void> dispose(LottieHandle handle) async {
    _requireOpen();
    await _post('dispose', {'handle': handle.id});
  }

  @override
  Future<void> close() => _closing ??= _shutdown();

  Future<void> _shutdown() async {
    // Requests already made run to completion first, as the interface says.
    await Future.wait([
      for (final reply in [..._pending.values])
        reply.future.then<void>((_) {}, onError: (Object _) {}),
    ]);
    try {
      if (!_ended) await _post('close');
      // ignore: avoid_catching_errors, the interface's own closed signal.
    } on LottieEngineClosed {
      // The worker ended while it was asked to: it is closed all the same.
    } finally {
      if (!_ended) _end();
    }
  }
}

/// A request the worker answered `ok: false`: the request failed, the worker
/// did not.
final class LottieWorkerError implements Exception {
  /// Creates the error for a worker's [message].
  const LottieWorkerError(this.message);

  /// The worker's error text.
  final String message;

  @override
  String toString() => 'LottieWorkerError: $message';
}
