import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Starts the worker's isolate: runs [entryPoint] with [message] on a new
/// isolate that sends null to [onExit] when it ends, as `Isolate.spawn` does
/// (the default).
typedef LottieHashWorkerSpawner =
    Future<Isolate> Function(
      void Function(SendPort) entryPoint,
      SendPort message, {
      required SendPort onExit,
    });

/// One long-lived isolate that hashes Lottie files for the frame cache: the
/// default `LottieContentHasher` of a `LottieDecoder` on the VM.
///
/// Hashing a sticker file on the calling isolate took 2-10 ms at a time on a
/// phone, between frames, so the hash runs elsewhere. It ran on a short-lived
/// isolate per decode (`compute`), and a panel that scrolls new stickers in
/// decodes dozens a second: a device trace counted 1,718 isolate spawns in
/// 62 s, about 0.5 ms of helper-thread work each, allocating in the shared
/// isolate group and feeding its garbage collector. The worker is spawned at
/// the first [hash] and serves every later one; it hashes one file at a time,
/// in the order asked.
///
/// The render isolate of an `IsolateLottieEngine` is not used: a hash there
/// would sit in front of the frames it renders and make them late.
///
/// The bytes are copied to the worker, a memory copy far cheaper than the
/// hash. An isolate that ends on its own (killed, out of memory) fails the
/// hashes it had, and the next [hash] spawns a new one.
final class LottieContentHashWorker {
  /// Creates a worker that has not started; [spawn] starts its isolate.
  LottieContentHashWorker({LottieHashWorkerSpawner spawn = _isolateSpawn})
    : _spawn = spawn;

  /// The worker every `LottieDecoder` without its own hasher shares. It is
  /// never closed: an idle isolate waiting on a port costs no CPU.
  static final LottieContentHashWorker shared = LottieContentHashWorker();

  static Future<Isolate> _isolateSpawn(
    void Function(SendPort) entryPoint,
    SendPort message, {
    required SendPort onExit,
  }) => Isolate.spawn(
    entryPoint,
    message,
    onExit: onExit,
    debugName: 'lottie content hash',
  );

  final LottieHashWorkerSpawner _spawn;
  Future<_Running>? _running;
  final _pending = <int, Completer<String>>{};
  var _nextId = 0;
  var _closed = false;

  /// The SHA-256 of [bytes] in lowercase hex, computed on the worker.
  ///
  /// Throws a [StateError] once the worker is closed.
  Future<String> hash(Uint8List bytes) async {
    if (_closed) throw StateError('The content hash worker is closed.');
    final running = await (_running ??= _start());
    if (_closed) throw StateError('The content hash worker is closed.');
    final id = _nextId++;
    final completer = Completer<String>();
    _pending[id] = completer;
    running.commands.send((id, bytes));
    return completer.future;
  }

  /// Ends the isolate. Hashes not answered yet fail with a [StateError], and
  /// so does every later [hash]. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final running = _running;
    _running = null;
    _failPending('The content hash worker is closed.');
    if (running == null) return;
    try {
      (await running).end();
    } on Object {
      // It never started; there is nothing to end.
    }
  }

  Future<_Running> _start() async {
    final replies = ReceivePort('lottie content hash replies');
    final exits = ReceivePort('lottie content hash exit');
    final ready = Completer<SendPort>();
    _Running? running;
    replies.listen((message) {
      switch (message) {
        case final SendPort port when !ready.isCompleted:
          ready.complete(port);
        case (final int id, final String hex):
          _pending.remove(id)?.complete(hex);
        case (final int id, final String error, final String stack):
          _pending
              .remove(id)
              ?.completeError(RemoteError(error, stack), StackTrace.current);
      }
    });
    // Only an isolate that ends on its own gets here: a close closes this
    // port first. The hashes it had are lost; the next one starts anew.
    exits.listen((_) {
      replies.close();
      exits.close();
      if (!ready.isCompleted) {
        ready.completeError(StateError('The content hash worker ended.'));
      }
      if (running != null) _running = null;
      _failPending('The content hash worker ended.');
    });
    try {
      final isolate = await _spawn(
        _workerMain,
        replies.sendPort,
        onExit: exits.sendPort,
      );
      return running = _Running(isolate, await ready.future, replies, exits);
    } on Object {
      replies.close();
      exits.close();
      _running = null;
      rethrow;
    }
  }

  void _failPending(String reason) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(StateError(reason));
    }
  }
}

final class _Running {
  _Running(this.isolate, this.commands, this._replies, this._exits);

  final Isolate isolate;
  final SendPort commands;
  final ReceivePort _replies;
  final ReceivePort _exits;

  void end() {
    _replies.close();
    _exits.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

// The worker: answers each (id, bytes) with (id, hex), or (id, error, stack)
// if hashing throws.
void _workerMain(SendPort replies) {
  final commands = ReceivePort('lottie content hash commands');
  replies.send(commands.sendPort);
  commands.listen((message) {
    final (int id, Uint8List bytes) = message as (int, Uint8List);
    try {
      replies.send((id, sha256.convert(bytes).toString()));
    } on Object catch (error, stack) {
      replies.send((id, '$error', '$stack'));
    }
  });
}
