import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/engine/lottie_engine_work.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:meta/meta.dart';

/// A [LottieEngine] whose [LottieBinding] lives on one long-lived isolate of
/// its own, so parsing and rasterizing never take a frame from the UI isolate
/// (ADR 042 "Workers").
///
/// The isolate creates its own binding (a binding is single-isolate state),
/// owns every handle, and answers requests one at a time in arrival order:
/// a `render` sent after a `dispose` of the same handle sees it disposed.
///
/// A fault inside native code ends the whole process and cannot be caught;
/// nothing here pretends otherwise. What is handled is a Dart exception in
/// one request (that request fails, the isolate stays usable) and the
/// isolate ending (every pending request fails, the engine is closed).
///
/// [close] lets requests already sent finish: a render's future completes
/// only after native code is done with the address it was given.
final class IsolateLottieEngine implements LottieEngine {
  IsolateLottieEngine._() {
    // Listening before the isolate exists means no message can arrive unheard;
    // closing a port ends its subscription.
    _replies.listen(_onReply);
    _errors.listen((error) => _lastError = '$error');
    _exits.listen((_) => _onExit());
  }

  /// Starts the render isolate.
  ///
  /// [bindingFactory] builds the isolate's binding and must be a top-level or
  /// static function, since it crosses isolates; it defaults to
  /// [NativeLottieBinding.probe]. Throws a [LottieUnavailable] carrying the
  /// reported [LottieAvailability] when that binding is not available (the
  /// isolate is shut down first), and a [StateError] when the isolate ends
  /// before it is ready; the host decides what to log and does not register the decoder.
  ///
  /// [codecFactory] builds the isolate's frame codec the same way (top-level
  /// or static, since it crosses isolates) and defaults to
  /// [NativeLottieFrameCodec.probe]. It runs only once the binding is
  /// available, and a codec that is not available is dropped: the engine then
  /// renders without compressing, and the cache sees only misses. Compressed
  /// bytes cross isolates as `TransferableTypedData`.
  static Future<IsolateLottieEngine> spawn({
    LottieBinding Function()? bindingFactory,
    LottieFrameCodec Function()? codecFactory,
  }) async {
    final engine = IsolateLottieEngine._();
    // The isolate can end before anyone awaits readiness (a binding factory
    // that throws): the error is then recorded on the future but not left
    // unhandled; the await below still receives it.
    final ready = engine._ready.future..ignore();
    try {
      engine._isolate = await Isolate.spawn(
        _renderIsolateMain,
        _Boot(engine._replies.sendPort, bindingFactory, codecFactory),
        onError: engine._errors.sendPort,
        onExit: engine._exits.sendPort,
      );
      await ready;
      return engine;
      // Whatever stopped the start-up, the isolate and the ports go with it.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Ports first: the isolate may never have existed (spawn itself threw),
      // and nothing here may throw in place of the original error.
      engine
        .._releasePorts()
        .._isolate?.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  // --- State ---

  /// How the engine makes its three ports; tests swap it to see them close.
  @visibleForTesting
  static ReceivePort Function() debugPortFactory = ReceivePort.new;

  final _replies = debugPortFactory();
  final _errors = debugPortFactory();
  final _exits = debugPortFactory();
  Isolate? _isolate;
  late final SendPort _commands;

  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  var _closed = false;
  String? _lastError;

  // --- LottieEngine ---

  @override
  Future<LottieLoadResult> load(Uint8List bytes) {
    // The bytes move to the isolate without a copy; the caller's list is
    // read once here and not again.
    final data = TransferableTypedData.fromList([bytes]);
    return _request((id) => _Load(id, data));
  }

  @override
  Future<List<LottieRenderStatus>> renderBatch(List<LottieEngineJob> jobs) =>
      _request((id) => _Render(id, jobs));

  @override
  Future<List<LottieCapture>> renderCapturing(
    List<LottieEngineJob> jobs,
  ) async {
    final wire =
        await _request<List<(LottieRenderStatus, TransferableTypedData?)>>(
          (id) => _RenderCapturing(id, jobs),
        );
    return [
      for (final (status, bytes) in wire)
        LottieCapture(status, bytes?.materialize().asUint8List()),
    ];
  }

  @override
  Future<List<LottieRenderStatus>> restore(List<LottieRestoreJob> jobs) {
    final wire = [
      for (final job in jobs)
        _RestoreWire(
          TransferableTypedData.fromList([job.compressed]),
          job.width,
          job.height,
          job.address,
          job.strideBytes,
        ),
    ];
    return _request((id) => _Restore(id, wire));
  }

  @override
  Future<void> dispose(LottieHandle handle) =>
      _request((id) => _Dispose(id, handle));

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      // Requests already sent are not failed here: the isolate answers them
      // in order before it handles the close, and native code may still be
      // writing to the address a render was given. Failing the future early
      // would let the caller free that memory under it. Only the isolate
      // ending (_onExit) fails what is still pending, as a last resort.
      _commands.send(const _Close());
    }
    await _exited.future;
  }

  // --- Requests and replies ---

  Future<T> _request<T>(_Request Function(int id) make) {
    if (_closed) {
      return Future<T>.error(LottieEngineClosed());
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send(make(id));
    return completer.future.then((value) => value as T);
  }

  void _onReply(Object? message) {
    switch (message as _Event) {
      case _Ready(:final commands):
        _commands = commands;
        _ready.complete();
      case _Unavailable(:final availability):
        _ready.completeError(LottieUnavailable(availability));
      case _Value(:final id, :final value):
        _pending.remove(id)?.complete(value);
      case _Failure(:final id, :final error, :final stack):
        _pending.remove(id)?.completeError(RemoteError(error, stack));
    }
  }

  void _onExit() {
    _closed = true;
    _failPending(LottieEngineClosed('the render isolate ended'));
    if (!_ready.isCompleted) {
      _ready.completeError(
        StateError(
          'the render isolate ended before it was ready'
          '${_lastError == null ? '' : ': $_lastError'}',
        ),
      );
    }
    _releasePorts();
    if (!_exited.isCompleted) _exited.complete();
  }

  void _failPending(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }

  void _releasePorts() {
    _replies.close();
    _errors.close();
    _exits.close();
  }
}

// --- Protocol (data, not control flow) ---

/// What the isolate is started with.
final class _Boot {
  const _Boot(this.replies, this.bindingFactory, this.codecFactory);
  final SendPort replies;
  final LottieBinding Function()? bindingFactory;
  final LottieFrameCodec Function()? codecFactory;
}

/// What the isolate sends back: its start-up verdict, then one answer per
/// request. Closed, so the receiving side matches every case and reads no
/// nullable field.
sealed class _Event {
  const _Event();
}

/// The isolate's first message when the binding can serve: where to send
/// requests.
final class _Ready extends _Event {
  const _Ready(this.commands);
  final SendPort commands;
}

/// The isolate's first message when the binding cannot serve, and why (the
/// isolate ends right after).
final class _Unavailable extends _Event {
  const _Unavailable(this.availability);
  final LottieAvailability availability;
}

sealed class _Request {
  const _Request();
}

final class _Load extends _Request {
  const _Load(this.id, this.data);
  final int id;
  final TransferableTypedData data;
}

final class _Render extends _Request {
  const _Render(this.id, this.jobs);
  final int id;
  final List<LottieEngineJob> jobs;
}

final class _RenderCapturing extends _Request {
  const _RenderCapturing(this.id, this.jobs);
  final int id;
  final List<LottieEngineJob> jobs;
}

/// A restore job with its bytes in transferable form.
final class _RestoreWire {
  const _RestoreWire(
    this.data,
    this.width,
    this.height,
    this.address,
    this.strideBytes,
  );
  final TransferableTypedData data;
  final int width;
  final int height;
  final int address;
  final int strideBytes;
}

final class _Restore extends _Request {
  const _Restore(this.id, this.jobs);
  final int id;
  final List<_RestoreWire> jobs;
}

final class _Dispose extends _Request {
  const _Dispose(this.id, this.handle);
  final int id;
  final LottieHandle handle;
}

/// Frees the binding and ends the isolate; it has no reply, the exit is the
/// answer.
final class _Close extends _Request {
  const _Close();
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

// --- The isolate side ---

void _renderIsolateMain(_Boot boot) {
  final binding = boot.bindingFactory?.call() ?? NativeLottieBinding.probe();
  if (!binding.isAvailable) {
    boot.replies.send(_Unavailable(binding.availability));
    return;
  }

  // Only a serving binding gets a codec; one that cannot run is dropped.
  final codec = LottieEngineWork.usable(
    (boot.codecFactory ?? NativeLottieFrameCodec.probe)(),
  );

  final commands = ReceivePort();
  void answer(int id, Object? Function() work) {
    try {
      boot.replies.send(_Value(id, work()));
      // One request's failure must not end the isolate; it is reported with
      // its stack to the caller of that request.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      boot.replies.send(_Failure(id, '$error', '$stack'));
    }
  }

  commands.listen((message) {
    switch (message as _Request) {
      case _Load(:final id, :final data):
        answer(id, () => binding.load(data.materialize().asUint8List()));
      case _Render(:final id, :final jobs):
        answer(
          id,
          () =>
              binding.renderBatch([for (final job in jobs) job.toBindingJob()]),
        );
      case _RenderCapturing(:final id, :final jobs):
        // Bytes leave as transferables: no copy through the port.
        answer(
          id,
          () => [
            for (final capture in LottieEngineWork.renderCapturing(
              binding,
              codec,
              jobs,
            ))
              (
                capture.status,
                capture.compressed == null
                    ? null
                    : TransferableTypedData.fromList([capture.compressed!]),
              ),
          ],
        );
      case _Restore(:final id, :final jobs):
        answer(
          id,
          () => LottieEngineWork.restore(codec, [
            for (final job in jobs)
              LottieRestoreJob(
                compressed: job.data.materialize().asUint8List(),
                width: job.width,
                height: job.height,
                address: job.address,
                strideBytes: job.strideBytes,
              ),
          ]),
        );
      case _Dispose(:final id, :final handle):
        answer(id, () => binding.dispose(handle));
      case _Close():
        // Closing the port is what ends the isolate, even if the binding
        // throws while closing.
        try {
          binding.close();
        } finally {
          commands.close();
        }
    }
  });
  boot.replies.send(_Ready(commands.sendPort));
}
