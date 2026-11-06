import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';

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
  static Future<IsolateLottieEngine> spawn({
    LottieBinding Function()? bindingFactory,
  }) async {
    final engine = IsolateLottieEngine._();
    try {
      engine._isolate = await Isolate.spawn(
        _renderIsolateMain,
        _Boot(engine._replies.sendPort, bindingFactory),
        onError: engine._errors.sendPort,
        onExit: engine._exits.sendPort,
      );
      await engine._ready.future;
      return engine;
      // Whatever stopped the start-up, the isolate and the ports go with it.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      engine._isolate.kill(priority: Isolate.immediate);
      engine._releasePorts();
      rethrow;
    }
  }

  // --- State ---

  final _replies = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  late final Isolate _isolate;
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
    switch (message) {
      case _Ready(:final commands, :final availability):
        if (commands == null) {
          _ready.completeError(LottieUnavailable(availability));
        } else {
          _commands = commands;
          _ready.complete();
        }
      case _Reply(:final id, :final error, :final stack, :final value):
        final completer = _pending.remove(id);
        if (error == null) {
          completer?.complete(value);
        } else {
          completer?.completeError(RemoteError(error, stack!));
        }
      default:
        throw StateError('Unexpected render isolate message: $message');
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
  const _Boot(this.replies, this.bindingFactory);
  final SendPort replies;
  final LottieBinding Function()? bindingFactory;
}

/// The isolate's first message: where to send requests, or `null` and why
/// the binding cannot serve (the isolate ends right after).
final class _Ready {
  const _Ready(this.commands, this.availability);
  final SendPort? commands;
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

/// The one reply type: the request id, and either a value or a failure.
final class _Reply {
  const _Reply.value(this.id, this.value) : error = null, stack = null;
  const _Reply.failure(this.id, String this.error, String this.stack)
    : value = null;
  final int id;
  final Object? value;
  final String? error;
  final String? stack;
}

// --- The isolate side ---

void _renderIsolateMain(_Boot boot) {
  final binding = boot.bindingFactory?.call() ?? NativeLottieBinding.probe();
  if (!binding.isAvailable) {
    boot.replies.send(_Ready(null, binding.availability));
    return;
  }

  final commands = ReceivePort();
  void answer(int id, Object? Function() work) {
    try {
      boot.replies.send(_Reply.value(id, work()));
      // One request's failure must not end the isolate; it is reported with
      // its stack to the caller of that request.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      boot.replies.send(_Reply.failure(id, '$error', '$stack'));
    }
  }

  commands.listen((message) {
    switch (message as _Request) {
      case _Load(:final id, :final data):
        answer(id, () => binding.load(data.materialize().asUint8List()));
      case _Render(:final id, :final jobs):
        answer(
          id,
          () => binding.renderBatch([
            for (final job in jobs)
              LottieRenderJob(
                handle: job.handle,
                frame: job.frame,
                width: job.width,
                height: job.height,
                target: Pointer<Uint8>.fromAddress(job.address),
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
  boot.replies.send(_Ready(commands.sendPort, binding.availability));
}
