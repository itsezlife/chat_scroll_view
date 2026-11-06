import 'dart:async';
import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/engine/lottie_worker_port.dart';
import 'package:lottie_decoder/src/engine/web_worker_lottie_engine.dart';
import 'package:lottie_decoder/src/testing/fake_pixel_lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// The worker side of the Lottie worker protocol, in memory: it answers the
/// messages of `chat_lottie_worker.js` the way that worker does, over a
/// scripted [core] instead of WebAssembly.
///
/// Like the real worker it serves requests one at a time in arrival order,
/// and replies asynchronously. The knobs below make it misbehave on purpose:
/// hold replies back, answer in another order, fail a request, send a buffer
/// of the wrong size, die.
final class FakeLottieWorker {
  /// Creates a worker that answers `init` with `ready` (choosing the SIMD
  /// build when [simd]), or with `unavailable` and [unavailableReason] when
  /// that is set, or with nothing when [answersInit] is false.
  FakeLottieWorker({
    this.simd = true,
    this.unavailableReason,
    this.answersInit = true,
  });

  /// Whether `ready` reports the SIMD build.
  final bool simd;

  /// When set, `init` is answered with `unavailable` and this reason.
  final String? unavailableReason;

  /// Whether `init` is answered at all.
  final bool answersInit;

  /// The scripted files and drawing; accept a file here before loading it.
  final FakePixelLottieEngine core = FakePixelLottieEngine();

  final _messages = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );
  final _failures = StreamController<void>.broadcast(sync: true);
  final _received = <Map<String, Object?>>[];
  final _held = <Map<String, Object?>>[];
  var _terminated = false;
  var _dead = false;
  var _hold = false;
  final _scriptedFailures = <String>[];
  var _shortPixels = false;

  /// Every message the host posted, in order.
  List<Map<String, Object?>> get received => List.unmodifiable(_received);

  /// Whether the host ended this worker.
  bool get terminated => _terminated;

  /// The host's end of the worker.
  late final LottieWorkerPort port = _HostPort(this);

  /// While true, replies are kept back until [release]; the worker still
  /// serves requests in order.
  set holdReplies(bool value) => _hold = value;

  /// Sends the held replies, in the order [order] picks (default: the order
  /// they were made), and stops holding.
  void release([
    List<Map<String, Object?>> Function(List<Map<String, Object?>>)? order,
  ]) {
    _hold = false;
    final replies = order == null ? [..._held] : order([..._held]);
    _held.clear();
    replies.forEach(_send);
  }

  /// The next request that is not `init` is answered `ok: false` with [error]
  /// (one call, one request).
  void failNextRequest(String error) => _scriptedFailures.add(error);

  /// Every pixel buffer is sent one byte short, as a worker with a bug would.
  void sendShortPixels() => _shortPixels = true;

  /// The worker fails: the host sees a failure and nothing more is answered.
  void die() {
    _dead = true;
    _failures.add(null);
  }

  // The worker serves one request at a time, in arrival order.
  var _queue = Future<void>.value();

  void _receive(Map<String, Object?> message) {
    if (_terminated) return;
    _received.add(message);
    _queue = _queue.then((_) => _serve(message));
  }

  Future<void> _serve(Map<String, Object?> message) async {
    if (_dead || _terminated) return;
    if (message['type'] == 'init') {
      if (!answersInit) return;
      final reason = unavailableReason;
      _reply(
        reason == null
            ? {'type': 'ready', 'simd': simd}
            : {'type': 'unavailable', 'reason': reason},
      );
      return;
    }
    final id = message['id'];
    if (_scriptedFailures.isNotEmpty) {
      _reply({'id': id, 'ok': false, 'error': _scriptedFailures.removeAt(0)});
      return;
    }
    switch (message['type']) {
      case 'load':
        final result = await core.load(message['bytes']! as Uint8List);
        _reply(switch (result) {
          LottieLoaded(:final handle, :final info) => {
            'id': id,
            'ok': true,
            'status': LottieWorkerStatus.ok,
            'info': {
              'handle': handle.id,
              'width': info.width,
              'height': info.height,
              'frameCount': info.frameCount,
              'frameRate': info.frameRate,
              'features': info.features.bits,
            },
          },
          LottieRejected(:final reason) => {
            'id': id,
            'ok': true,
            'status': _statusOf(reason),
          },
        });
      case 'render':
        final jobs = [
          for (final job in message['jobs']! as List)
            LottiePixelJob(
              handle: LottieHandle((job as Map)['handle']! as int),
              frame: (job['frame']! as num).toDouble(),
              width: job['width']! as int,
              height: job['height']! as int,
            ),
        ];
        final pixels = await core.renderPixels(jobs);
        _reply({
          'id': id,
          'ok': true,
          'results': [
            for (final frame in pixels)
              if (frame == null)
                {'status': LottieWorkerStatus.badSize, 'pixels': null}
              else
                {
                  'status': LottieWorkerStatus.ok,
                  'pixels': _shortPixels
                      ? frame.sublist(0, frame.length - 1)
                      : frame,
                },
          ],
        });
      case 'dispose':
        await core.dispose(LottieHandle(message['handle']! as int));
        _reply({'id': id, 'ok': true});
      case 'close':
        await core.close();
        _reply({'id': id, 'ok': true});
      default:
        _reply({
          'id': id,
          'ok': false,
          'error': 'unknown request type "${message['type']}"',
        });
    }
  }

  static int _statusOf(LottieRejection reason) => switch (reason) {
    LottieRejection.tooLarge => LottieWorkerStatus.tooLarge,
    LottieRejection.malformed => LottieWorkerStatus.malformed,
    LottieRejection.limitExceeded => LottieWorkerStatus.limitExceeded,
    LottieRejection.unsupported => LottieWorkerStatus.unsupported,
    LottieRejection.internal => LottieWorkerStatus.internal,
  };

  void _reply(Map<String, Object?> message) {
    if (_hold && message.containsKey('id')) {
      _held.add(message);
    } else {
      _send(message);
    }
  }

  void _send(Map<String, Object?> message) {
    if (_dead || _terminated) return;
    _messages.add(message);
  }
}

final class _HostPort implements LottieWorkerPort {
  _HostPort(this._worker);

  final FakeLottieWorker _worker;

  @override
  void post(
    Map<String, Object?> message, {
    List<Uint8List> transfer = const [],
  }) => _worker._receive(message);

  @override
  Stream<Map<String, Object?>> get messages => _worker._messages.stream;

  @override
  Stream<void> get failures => _worker._failures.stream;

  @override
  void terminate() => _worker._terminated = true;
}
