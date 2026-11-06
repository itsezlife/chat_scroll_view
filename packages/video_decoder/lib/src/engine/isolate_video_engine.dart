import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:video_decoder/src/engine/video_decode_core.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_native/video_native.dart';

/// A [VideoEngine] that decodes on a pool of long-lived worker isolates, so
/// opening, demuxing and decoding never take a frame from the UI isolate
/// (ADR 042 "Workers").
///
/// Each worker builds its own binding (a binding is single-isolate state),
/// owns the clips it opened, and answers its requests one at a time in
/// arrival order. A clip is pinned to the worker that opened it, which is what
/// makes the per-clip order free: the order requests were sent in is the order
/// they run in, so a caller may issue several without awaiting, and
/// `rewind` sent after `nextFrame` sees the frame decoded. Clips on different
/// workers decode at the same time.
///
/// A new clip goes to the live worker holding the fewest clips (the lowest
/// index on a tie), counted when the open is requested so a burst of opens
/// spreads. Not by queue depth: a clip's cost is its frame rate, which the
/// engine does not know, and the count is the one number it does.
///
/// Frames cross isolates as `TransferableTypedData`, which costs one copy
/// out of the worker's scratch buffer and one into the caller's list. The
/// seam hands out a `Uint8List`, which has no address a worker could write
/// to; a native-only engine that decodes into caller-owned native memory
/// (the way lottie's slot engines do) removes both copies and is a later
/// part, to be built when a paintable shows the copy in a profile. Measured on
/// an Apple-silicon Mac at 512 by 512 (1 MiB): a destination copy is about
/// 30 microseconds of a 1.4 millisecond awaited round trip that includes a
/// VP9 decode, so the copies are not where the time goes.
///
/// A fault inside native code ends the whole process and cannot be caught;
/// nothing here pretends otherwise. What is handled: a Dart exception in one
/// request (that request fails with a [RemoteError], the worker stays usable)
/// and a worker isolate ending (the requests pending on it, and every later
/// call on its clips, fail with [VideoClipLost]; the other workers and the
/// engine go on). An ended worker is not respawned: the pool shrinks, and the
/// engine is closed for [open] when none is left. Respawning is the growth
/// point if workers prove to die in practice.
final class IsolateVideoEngine implements VideoEngine {
  IsolateVideoEngine._(this._workers);

  /// Starts [workers] decode isolates, 1 to 4 (a [RangeError] otherwise).
  ///
  /// [bindingFactory] builds each isolate's binding and must be a top-level
  /// or static function, or a closure that captures nothing that cannot cross
  /// isolates; it defaults to [NativeVideoBinding.probe]. Throws a
  /// [VideoUnavailable] carrying the reported availability when that binding
  /// is not available (every isolate is shut down first), and a [StateError]
  /// when an isolate ends before it is ready; the host decides what to log and
  /// does not register the decoder.
  ///
  /// [dispose] waits at most [closeTimeout] for the workers to finish what
  /// they were asked; after that they are killed and what is still pending
  /// fails with [VideoEngineClosed].
  static Future<IsolateVideoEngine> spawn({
    int workers = 2,
    VideoBinding Function()? bindingFactory,
    Duration closeTimeout = const Duration(seconds: 10),
  }) async {
    RangeError.checkValueInInterval(workers, 1, maxWorkers, 'workers');
    final engine = IsolateVideoEngine._([
      for (var i = 0; i < workers; i++) _Worker(closeTimeout),
    ]);
    try {
      // All settle before any error is rethrown, so none is left half-started.
      await Future.wait([
        for (final worker in engine._workers) worker.start(bindingFactory),
      ]);
      return engine;
      // Whatever stopped the start-up, the isolates and ports go with it.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      for (final worker in engine._workers) {
        worker.abandon();
      }
      rethrow;
    }
  }

  /// The most workers a pool has; decoding is CPU-bound and a chat list
  /// plays a few clips at a time, so more would only compete with the UI.
  static const int maxWorkers = 4;

  final List<_Worker> _workers;
  final _placements = <int, _Placement>{};
  var _nextClipId = 0;
  var _disposed = false;

  /// The index of the worker that holds [clip], or -1 when it is not open.
  @visibleForTesting
  int workerOf(VideoClip clip) {
    final placement = _placements[clip.id];
    return placement == null ? -1 : _workers.indexOf(placement.worker);
  }

  // --- VideoEngine ---

  @override
  Future<VideoClipOpenResult> open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    _requireOpen();
    final live = _workers.where((worker) => !worker.ended);
    if (live.isEmpty) throw VideoEngineClosed('every decode worker ended');
    final worker = live.reduce((a, b) => b.clips < a.clips ? b : a);
    // Reserved now, returned if the open does not yield a clip, so opens made
    // before the first answer still spread.
    worker.clips++;
    final data = TransferableTypedData.fromList([bytes]);
    final VideoClipOpenResult result;
    try {
      result = await worker.request<VideoClipOpenResult>(
        (id) => _Open(id, data, width, height),
      );
    } on Object {
      worker.clips--;
      rethrow;
    }
    switch (result) {
      case VideoClipRejected():
        worker.clips--;
        return result;
      case VideoClipOpened(:final clip):
        final named = VideoClip(
          id: _nextClipId++,
          info: clip.info,
          width: clip.width,
          height: clip.height,
        );
        _placements[named.id] = _Placement(worker, clip.id);
        return VideoClipOpened(named);
    }
  }

  @override
  Future<VideoFrameResult> nextFrame(
    VideoClip clip, {
    required Uint8List destination,
  }) async {
    _requireOpen();
    final placement = _placements[clip.id];
    if (placement == null) {
      return const VideoFrameResult(VideoFrameStatus.badArgument);
    }
    if (destination.length < clip.frameBytes) {
      return const VideoFrameResult(VideoFrameStatus.badSize);
    }
    final (status, ptsMs, pixels) = await placement.worker
        .request<(VideoFrameStatus, int, TransferableTypedData?)>(
          (id) => _NextFrame(id, placement.localId),
        );
    if (pixels != null) {
      destination.setRange(
        0,
        clip.frameBytes,
        pixels.materialize().asUint8List(),
      );
    }
    return VideoFrameResult(status, ptsMs);
  }

  @override
  Future<bool> rewind(VideoClip clip) async {
    _requireOpen();
    final placement = _placements[clip.id];
    if (placement == null) return false;
    return placement.worker.request<bool>(
      (id) => _Rewind(id, placement.localId),
    );
  }

  @override
  Future<void> close(VideoClip clip) async {
    // Removed before the request is sent: a call made after this one sees the
    // clip gone, and one made before it is already ahead in the worker's queue.
    final placement = _placements.remove(clip.id);
    if (placement == null || _disposed || placement.worker.ended) return;
    placement.worker.clips--;
    await placement.worker.request<void>(
      (id) => _CloseClip(id, placement.localId),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _placements.clear();
    // Requests already sent are not failed here: each worker answers them in
    // order before it handles the shutdown, and a decode may be mid-flight.
    // Only a worker ending (or the timeout) fails what is still pending.
    await Future.wait([for (final worker in _workers) worker.shutdown()]);
  }

  void _requireOpen() {
    if (_disposed) throw VideoEngineClosed();
  }
}

/// Where a clip lives: its worker and the id that worker knows it by.
final class _Placement {
  const _Placement(this.worker, this.localId);
  final _Worker worker;
  final int localId;
}

// --- One worker, seen from the owning isolate ---

final class _Worker {
  _Worker(this._closeTimeout) {
    // Listening before the isolate exists means no message can arrive unheard;
    // closing a port ends its subscription.
    _replies.listen(_onReply);
    _errors.listen((error) => _lastError = '$error');
    _exits.listen((_) => _onExit());
  }

  final Duration _closeTimeout;
  final _replies = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  Isolate? _isolate;
  late final SendPort _commands;

  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  var _shuttingDown = false;
  String? _lastError;

  /// How many clips the engine has placed here (including opens in flight).
  int clips = 0;

  /// Whether the isolate is gone, however it went.
  bool ended = false;

  Future<void> start(VideoBinding Function()? bindingFactory) async {
    // The isolate can end before anyone awaits readiness (a binding factory
    // that throws): the error is then recorded on the future but not left
    // unhandled; the await below still receives it.
    final ready = _ready.future..ignore();
    _isolate = await Isolate.spawn(
      _workerMain,
      _Boot(_replies.sendPort, bindingFactory),
      onError: _errors.sendPort,
      onExit: _exits.sendPort,
    );
    await ready;
  }

  /// Kills the isolate and closes the ports without waiting for anything.
  void abandon() {
    ended = true;
    _releasePorts();
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<T> request<T>(_Request Function(int id) make) {
    if (ended) {
      return Future<T>.error(
        _shuttingDown ? VideoEngineClosed() : VideoClipLost(),
      );
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      _commands.send(make(id));
    } on Object {
      // Nothing was sent, so nothing will answer: a leftover completer would
      // fail unobserved when the isolate ends.
      _pending.remove(id);
      rethrow;
    }
    return completer.future.then((value) => value as T);
  }

  Future<void> shutdown() async {
    if (ended) return;
    _shuttingDown = true;
    _commands.send(const _Shutdown());
    await _exited.future.timeout(
      _closeTimeout,
      onTimeout: () {
        // A decode that never returns holds the host's shutdown; the isolate
        // goes (a kill lands when native code returns, if it ever does) and
        // the engine stops waiting for an exit message that may not come.
        _isolate?.kill(priority: Isolate.immediate);
        _onExit();
      },
    );
  }

  void _onReply(Object? message) {
    switch (message as _Event) {
      case _Ready(:final commands):
        _commands = commands;
        _ready.complete();
      case _Unavailable(:final availability):
        _ready.completeError(VideoUnavailable(availability));
      case _Value(:final id, :final value):
        _pending.remove(id)?.complete(value);
      case _Failure(:final id, :final error, :final stack):
        _pending.remove(id)?.completeError(RemoteError(error, stack));
    }
  }

  void _onExit() {
    ended = true;
    final cause = _shuttingDown
        ? VideoEngineClosed('the decode worker was shut down')
        : VideoClipLost(
            'the decode worker ended${_lastError == null ? '' : ': $_lastError'}',
          );
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(cause);
    }
    if (!_ready.isCompleted) {
      _ready.completeError(
        StateError(
          'the decode worker ended before it was ready'
          '${_lastError == null ? '' : ': $_lastError'}',
        ),
      );
    }
    _releasePorts();
    if (!_exited.isCompleted) _exited.complete();
  }

  void _releasePorts() {
    _replies.close();
    _errors.close();
    _exits.close();
  }
}

// --- Protocol (data, not control flow) ---

/// What a worker is started with.
final class _Boot {
  const _Boot(this.replies, this.bindingFactory);
  final SendPort replies;
  final VideoBinding Function()? bindingFactory;
}

/// What a worker sends back: its start-up verdict, then one answer per
/// request. Closed, so the receiving side matches every case and reads no
/// nullable field.
sealed class _Event {
  const _Event();
}

/// The first message when the binding can serve: where to send requests.
final class _Ready extends _Event {
  const _Ready(this.commands);
  final SendPort commands;
}

/// The first message when the binding cannot serve, and why (the isolate ends
/// right after).
final class _Unavailable extends _Event {
  const _Unavailable(this.availability);
  final VideoAvailability availability;
}

/// A request that succeeded, with its result.
final class _Value extends _Event {
  const _Value(this.id, this.value);
  final int id;
  final Object? value;
}

/// A request that threw: the error and stack as text (they cross isolates).
final class _Failure extends _Event {
  const _Failure(this.id, this.error, this.stack);
  final int id;
  final String error;
  final String stack;
}

sealed class _Request {
  const _Request();
}

final class _Open extends _Request {
  const _Open(this.id, this.data, this.width, this.height);
  final int id;
  final TransferableTypedData data;
  final int width;
  final int height;
}

final class _NextFrame extends _Request {
  const _NextFrame(this.id, this.localId);
  final int id;
  final int localId;
}

final class _Rewind extends _Request {
  const _Rewind(this.id, this.localId);
  final int id;
  final int localId;
}

final class _CloseClip extends _Request {
  const _CloseClip(this.id, this.localId);
  final int id;
  final int localId;
}

/// Frees the clips and the binding and ends the isolate; it has no reply, the
/// exit is the answer.
final class _Shutdown extends _Request {
  const _Shutdown();
}

// --- The isolate side ---

void _workerMain(_Boot boot) {
  final binding = boot.bindingFactory?.call() ?? NativeVideoBinding.probe();
  if (!binding.isAvailable) {
    boot.replies.send(_Unavailable(binding.availability));
    return;
  }
  final core = VideoDecodeCore(binding);

  final commands = ReceivePort();
  void answer(int id, Object? Function() work) {
    try {
      boot.replies.send(_Value(id, work()));
      // One request's failure must not end the worker; it is reported with
      // its stack to the caller of that request.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      boot.replies.send(_Failure(id, '$error', '$stack'));
    }
  }

  commands.listen((message) {
    switch (message as _Request) {
      case _Open(:final id, :final data, :final width, :final height):
        answer(
          id,
          () => core.open(
            data.materialize().asUint8List(),
            width: width,
            height: height,
          ),
        );
      case _NextFrame(:final id, :final localId):
        answer(id, () {
          final (result, pixels) = core.decodeNext(localId);
          // The pixels are a view of native scratch; the transferable is the
          // copy out of it.
          return (
            result.status,
            result.ptsMs,
            pixels == null ? null : TransferableTypedData.fromList([pixels]),
          );
        });
      case _Rewind(:final id, :final localId):
        answer(id, () => core.rewind(localId));
      case _CloseClip(:final id, :final localId):
        answer(id, () => core.close(localId));
      case _Shutdown():
        // Closing the port is what ends the isolate, even if the binding
        // throws while closing.
        try {
          core.dispose();
        } finally {
          commands.close();
        }
    }
  });
  boot.replies.send(_Ready(commands.sendPort));
}
