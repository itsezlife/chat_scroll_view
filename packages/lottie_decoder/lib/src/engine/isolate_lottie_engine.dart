import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:lottie_decoder/src/cache/cached_frame.dart';
import 'package:lottie_decoder/src/cache/frame_file_reader.dart';
import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/engine/lottie_engine_work.dart';
import 'package:lottie_decoder/src/engine/lottie_slot_engine.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:meta/meta.dart';

/// A [LottieSlotEngine] whose [LottieBinding]s live on long-lived isolates of
/// their own, a pool of one to [maxWorkers], so parsing and rasterizing never
/// take a frame from the UI isolate (ADR 042 "Workers").
///
/// Each isolate creates its own binding (a binding is single-isolate state),
/// owns the handles it loaded, and answers its requests one at a time in
/// arrival order: a `render` sent after a `dispose` of the same handle sees it
/// disposed. A handle is pinned to the isolate that loaded it, which keeps
/// that order for every request naming it. Isolates render different handles
/// at the same time, which the wrapper's contract allows (`chat_lottie.h`:
/// handles are independent; ADR 042, *Amendment: a pool of render isolates*,
/// records the evidence).
///
/// A new animation goes to the isolate holding the fewest handles (the lowest
/// index on a tie), counted when the load is sent so a burst of loads
/// spreads. A request over several handles is split by isolate, one request
/// to each, and answered in job order once all have answered; a job that
/// names no handle (a restore of a cached frame into a page slot) goes to the
/// isolate with the fewest requests waiting. The handles the engine gives out
/// encode their isolate (`local * workers + index`), so routing needs no
/// table; with one isolate they are the binding's own.
///
/// A fault inside native code ends the whole process and cannot be caught;
/// nothing here pretends otherwise. What is handled is a Dart exception in
/// one request (that request fails, the isolate stays usable) and an isolate
/// ending: its pending requests fail, the engine is closed, and the other
/// isolates finish what they were sent and shut down. The handles of an ended
/// isolate are gone with it, and a pool that lived on without it would answer
/// for animations it no longer has.
///
/// [close] lets requests already sent finish: a render's future completes
/// only after native code is done with the address it was given.
final class IsolateLottieEngine implements LottieSlotEngine {
  IsolateLottieEngine._(this._workers) {
    for (final worker in _workers) {
      worker.onEnded = _onWorkerEnded;
    }
  }

  /// Starts [workers] render isolates, 1 to [maxWorkers] (a [RangeError]
  /// otherwise); a host usually asks for [defaultWorkers].
  ///
  /// [bindingFactory] builds each isolate's binding and must be a top-level
  /// or static function, since it crosses isolates; it defaults to
  /// [NativeLottieBinding.probe]. Throws a [LottieUnavailable] carrying the
  /// reported [LottieAvailability] when that binding is not available (every
  /// isolate is shut down first), and a [StateError] when an isolate ends
  /// before it is ready; the host decides what to log and does not register
  /// the decoder.
  ///
  /// [codecFactory] builds each isolate's frame codec the same way (top-level
  /// or static, since it crosses isolates) and defaults to
  /// [NativeLottieFrameCodec.probe]. It runs only once the binding is
  /// available, and a codec that is not available is dropped: the engine then
  /// renders without compressing, and the cache sees only misses. Compressed
  /// bytes cross isolates as `TransferableTypedData`.
  ///
  /// [close] waits at most [closeTimeout] for the isolates to finish what
  /// they were asked; after that they are killed and what is still pending
  /// fails with [LottieEngineClosed].
  static Future<IsolateLottieEngine> spawn({
    int workers = 1,
    LottieBinding Function()? bindingFactory,
    LottieFrameCodec Function()? codecFactory,
    Duration closeTimeout = const Duration(seconds: 10),
  }) async {
    RangeError.checkValueInInterval(workers, 1, maxWorkers, 'workers');
    final engine = IsolateLottieEngine._([
      for (var i = 0; i < workers; i++) _RenderWorker(closeTimeout),
    ]);
    try {
      // All settle before an error is rethrown, so none is left half-started.
      await Future.wait([
        for (final worker in engine._workers)
          worker.start(bindingFactory, codecFactory),
      ]);
      return engine;
      // Whatever stopped the start-up, the isolates and the ports go with it.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      for (final worker in engine._workers) {
        worker.abandon();
      }
      rethrow;
    }
  }

  /// The most render isolates a pool has: four threads render animations, and
  /// more would compete with the UI and raster threads and the video workers.
  static const int maxWorkers = 4;

  /// The pool size for this device: one isolate per core but one, from one
  /// to [maxWorkers].
  static int get defaultWorkers =>
      math.max(1, math.min(maxWorkers, Platform.numberOfProcessors - 1));

  /// How each isolate's three ports are made; tests swap it to see them close.
  @visibleForTesting
  static ReceivePort Function() debugPortFactory = ReceivePort.new;

  final List<_RenderWorker> _workers;
  // Handles given out and not disposed, so a second dispose is not counted.
  final Set<LottieHandle> _live = {};
  var _closed = false;

  /// How many render isolates the engine started.
  int get workerCount => _workers.length;

  /// The index of the isolate that holds [handle].
  @visibleForTesting
  int workerOf(LottieHandle handle) => _route(handle).$1;

  // --- LottieSlotEngine ---

  @override
  Future<LottieLoadResult> load(Uint8List bytes) async {
    if (_closed) throw LottieEngineClosed();
    final index = _fewest((worker) => worker.handles);
    final worker = _workers[index];
    // Reserved now, returned if no handle comes of it, so loads sent before
    // the first answer still spread.
    worker.handles++;
    // The bytes move to the isolate without a copy; the caller's list is
    // read once here and not again.
    final data = TransferableTypedData.fromList([bytes]);
    final LottieLoadResult result;
    try {
      result = await worker.request<LottieLoadResult>((id) => _Load(id, data));
    } on Object {
      worker.handles--;
      rethrow;
    }
    switch (result) {
      case LottieRejected():
        worker.handles--;
        return result;
      case LottieLoaded(:final handle, :final info):
        final named = LottieHandle(handle.id * _workers.length + index);
        _live.add(named);
        return LottieLoaded(named, info);
    }
  }

  @override
  Future<List<LottiePixels?>> renderPixels(List<LottiePixelJob> jobs) async {
    final wire = await _scatter<LottiePixelJob, TransferableTypedData?>(
      jobs,
      placeOf: (job) {
        final (index, local) = _route(job.handle);
        return (
          index,
          LottiePixelJob(
            handle: local,
            frame: job.frame,
            width: job.width,
            height: job.height,
          ),
        );
      },
      send: (worker, local) => worker.request((id) => _RenderPixels(id, local)),
    );
    return [for (final bytes in wire) bytes?.materialize().asUint8List()];
  }

  @override
  Future<List<LottieRenderStatus>> renderBatch(List<LottieEngineJob> jobs) =>
      _scatter<LottieEngineJob, LottieRenderStatus>(
        jobs,
        placeOf: _placeEngineJob,
        send: (worker, local) => worker.request((id) => _Render(id, local)),
      );

  @override
  Future<List<LottieCapture>> renderCapturing(
    List<LottieEngineJob> jobs,
  ) async {
    final wire =
        await _scatter<
          LottieEngineJob,
          (LottieRenderStatus, TransferableTypedData?)
        >(
          jobs,
          placeOf: _placeEngineJob,
          send: (worker, local) =>
              worker.request((id) => _RenderCapturing(id, local)),
        );
    return [
      for (final (status, bytes) in wire)
        LottieCapture(status, bytes?.materialize().asUint8List()),
    ];
  }

  @override
  Future<List<LottieRenderStatus>> restore(List<LottieRestoreJob> jobs) {
    // A restore names no handle: the batch goes where the fewest wait.
    final index = _fewest((worker) => worker.pending);
    return _scatter<_RestoreWire, LottieRenderStatus>(
      [
        for (final job in jobs)
          _RestoreWire(
            _toWire(job.frame),
            job.width,
            job.height,
            job.address,
            job.strideBytes,
          ),
      ],
      placeOf: (job) => (index, job),
      send: (worker, local) => worker.request((id) => _Restore(id, local)),
    );
  }

  @override
  Future<List<LottieTextureResult>> writeTextures(
    FrameTextureEntryPoints entryPoints,
    FrameTextureFormat format,
    List<LottieTextureJob> jobs,
  ) async {
    // A restore names no handle: it goes where the fewest requests wait.
    final idle = _fewest((worker) => worker.pending);
    final wire =
        await _scatter<
          _TextureWire,
          (TextureFrameOutcome, TransferableTypedData?)
        >(
          [
            for (final job in jobs)
              (
                job.texture,
                job.width,
                job.height,
                switch (job.work) {
                  final LottieTextureRender render => render,
                  LottieTextureRestore(:final frame) => _toWire(frame),
                },
              ),
          ],
          placeOf: (job) => switch (job) {
            (
              final texture,
              final width,
              final height,
              final LottieTextureRender render,
            ) =>
              switch (_route(render.handle)) {
                (final index, final local) => (
                  index,
                  (
                    texture,
                    width,
                    height,
                    LottieTextureRender(
                      local,
                      frame: render.frame,
                      capture: render.capture,
                    ),
                  ),
                ),
              },
            _ => (idle, job),
          },
          send: (worker, local) => worker.request(
            (id) => _WriteTextures(id, entryPoints, format, local),
          ),
        );
    return [
      for (final (outcome, bytes) in wire)
        LottieTextureResult(outcome, bytes?.materialize().asUint8List()),
    ];
  }

  @override
  Future<void> dispose(LottieHandle handle) {
    final (index, local) = _route(handle);
    if (_live.remove(handle)) _workers[index].handles--;
    return _workers[index].request((id) => _Dispose(id, local));
  }

  @override
  Future<void> close() async {
    _closed = true;
    await Future.wait([for (final worker in _workers) worker.close()]);
  }

  // --- Routing ---

  /// The isolate that holds [handle], and the handle as that isolate knows it.
  (int, LottieHandle) _route(LottieHandle handle) =>
      (handle.id % _workers.length, LottieHandle(handle.id ~/ _workers.length));

  (int, LottieEngineJob) _placeEngineJob(LottieEngineJob job) {
    final (index, local) = _route(job.handle);
    return (
      index,
      LottieEngineJob(
        handle: local,
        frame: job.frame,
        width: job.width,
        height: job.height,
        address: job.address,
        strideBytes: job.strideBytes,
      ),
    );
  }

  /// The index of the live isolate with the least of [measure], the lowest
  /// on a tie; 0 when none is live (its request then fails as closed).
  int _fewest(int Function(_RenderWorker worker) measure) {
    var best = 0;
    for (var i = 1; i < _workers.length; i++) {
      if (measure(_workers[i]) < measure(_workers[best])) best = i;
    }
    return best;
  }

  /// Sends [jobs] to their isolates, one request to each that has any, and
  /// answers one result per job in job order. Every request is awaited before
  /// an error is rethrown, so no isolate still writes to a caller's memory
  /// once the future completes.
  Future<List<R>> _scatter<J, R>(
    List<J> jobs, {
    required (int, J) Function(J job) placeOf,
    required Future<List<R>> Function(_RenderWorker worker, List<J> jobs) send,
  }) {
    if (_closed) return Future.error(LottieEngineClosed());
    // A pool of one: the handles are the binding's own and the jobs go as
    // they are, an empty request included.
    if (_workers.length == 1) return send(_workers.single, jobs);
    final byWorker = <int, (List<int>, List<J>)>{};
    for (var i = 0; i < jobs.length; i++) {
      final (index, local) = placeOf(jobs[i]);
      final (indices, placed) = byWorker[index] ??= (<int>[], <J>[]);
      indices.add(i);
      placed.add(local);
    }
    if (byWorker.isEmpty) return send(_workers.first, <J>[]);
    if (byWorker.length == 1) {
      final MapEntry(key: index, value: (_, placed)) = byWorker.entries.single;
      return send(_workers[index], placed);
    }
    return _gather(jobs.length, byWorker, send);
  }

  Future<List<R>> _gather<J, R>(
    int count,
    Map<int, (List<int>, List<J>)> byWorker,
    Future<List<R>> Function(_RenderWorker worker, List<J> jobs) send,
  ) async {
    final entries = byWorker.entries.toList();
    final answers = await Future.wait([
      for (final MapEntry(key: index, value: (_, placed)) in entries)
        send(_workers[index], placed),
    ]);
    final results = List<R?>.filled(count, null);
    for (var k = 0; k < entries.length; k++) {
      final (indices, _) = entries[k].value;
      for (var j = 0; j < indices.length; j++) {
        results[indices[j]] = answers[k][j];
      }
    }
    return results.cast<R>();
  }

  // One isolate ended: its handles are gone, so the engine closes, and the
  // others finish what they were sent before they shut down.
  void _onWorkerEnded() {
    _closed = true;
    for (final worker in _workers) {
      unawaited(worker.close());
    }
  }
}

/// A texture job on the wire: the texture, the frame's size, and a render as
/// itself or a restore's frame as [_toWire] spells it.
typedef _TextureWire = (AssetTexture, int, int, Object);

// --- One render isolate, seen from the owning isolate ---

final class _RenderWorker {
  _RenderWorker(this._closeTimeout) {
    // Listening before the isolate exists means no message can arrive unheard;
    // closing a port ends its subscription.
    _replies.listen(_onReply);
    _errors.listen((error) => _lastError = '$error');
    _exits.listen((_) => _onExit());
  }

  final Duration _closeTimeout;
  final _replies = IsolateLottieEngine.debugPortFactory();
  final _errors = IsolateLottieEngine.debugPortFactory();
  final _exits = IsolateLottieEngine.debugPortFactory();
  Isolate? _isolate;
  late final SendPort _commands;

  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  var _closed = false;
  String? _lastError;

  /// Called once when the isolate ends, however it went.
  void Function()? onEnded;

  /// Handles the engine placed here, loads in flight included.
  int handles = 0;

  /// Requests sent and not answered yet.
  int get pending => _pending.length;

  Future<void> start(
    LottieBinding Function()? bindingFactory,
    LottieFrameCodec Function()? codecFactory,
  ) async {
    // The isolate can end before anyone awaits readiness (a binding factory
    // that throws): the error is then recorded on the future but not left
    // unhandled; the await below still receives it.
    final ready = _ready.future..ignore();
    _isolate = await Isolate.spawn(
      _renderIsolateMain,
      _Boot(_replies.sendPort, bindingFactory, codecFactory),
      onError: _errors.sendPort,
      onExit: _exits.sendPort,
    );
    await ready;
  }

  /// Kills the isolate and closes the ports without waiting for anything.
  void abandon() {
    _closed = true;
    // Ports first: the isolate may never have existed (spawn itself threw),
    // and nothing here may throw in place of the original error.
    _releasePorts();
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<T> request<T>(_Request Function(int id) make) {
    if (_closed) {
      return Future<T>.error(LottieEngineClosed());
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
    await _exited.future.timeout(
      _closeTimeout,
      onTimeout: () {
        // A render that never returns holds the host's shutdown; the isolate
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
        _ready.completeError(LottieUnavailable(availability));
      case _Value(:final id, :final value):
        _pending.remove(id)?.complete(value);
      case _Failure(:final id, :final error, :final stack):
        _pending.remove(id)?.completeError(RemoteError(error, stack));
    }
  }

  void _onExit() {
    if (_exited.isCompleted) return;
    _closed = true;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(LottieEngineClosed('the render isolate ended'));
    }
    if (!_ready.isCompleted) {
      _ready.completeError(
        StateError(
          'the render isolate ended before it was ready'
          '${_lastError == null ? '' : ': $_lastError'}',
        ),
      );
    }
    _releasePorts();
    _exited.complete();
    onEnded?.call();
  }

  void _releasePorts() {
    _replies.close();
    _errors.close();
    _exits.close();
  }
}

// --- Protocol (data, not control flow) ---

/// A cached frame as it crosses to the isolate: bytes as a transferable (no
/// copy through the port), a file reference as itself (a path and a key,
/// read on the far side).
Object _toWire(CachedFrame frame) => switch (frame) {
  CachedFrameBytes(:final bytes) => TransferableTypedData.fromList([bytes]),
  final CachedFrameFile file => file,
};

/// The cached frame [wire] stands for, on the isolate.
CachedFrame _fromWire(Object wire) => switch (wire) {
  final TransferableTypedData bytes => CachedFrame.bytes(
    bytes.materialize().asUint8List(),
  ),
  final CachedFrameFile file => file,
  _ => throw ArgumentError.value(wire, 'frame'),
};

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

final class _RenderPixels extends _Request {
  const _RenderPixels(this.id, this.jobs);
  final int id;
  final List<LottiePixelJob> jobs;
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

  /// See [_toWire].
  final Object data;
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

/// Texture jobs on the wire: a render as itself, a restore's frame as
/// [_toWire] spells it.
final class _WriteTextures extends _Request {
  const _WriteTextures(this.id, this.entryPoints, this.format, this.jobs);
  final int id;
  final FrameTextureEntryPoints entryPoints;
  final FrameTextureFormat format;
  final List<(AssetTexture, int, int, Object)> jobs;
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

  // Frames of cache files are read here, where they are decompressed: the UI
  // isolate sends only where a frame is (ADR 022, frames read from the file).
  final reader = FrameFileReader();
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
      case _RenderPixels(:final id, :final jobs):
        // Pixels leave as transferables too: the copy out of the temporary
        // buffer is the only one.
        answer(
          id,
          () => [
            for (final pixels in LottieEngineWork.renderPixels(binding, jobs))
              pixels == null ? null : TransferableTypedData.fromList([pixels]),
          ],
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
          () => LottieEngineWork.restore(codec, reader, [
            for (final job in jobs)
              LottieRestoreJob(
                frame: _fromWire(job.data),
                width: job.width,
                height: job.height,
                address: job.address,
                strideBytes: job.strideBytes,
              ),
          ]),
        );
      case _WriteTextures(
        :final id,
        :final entryPoints,
        :final format,
        :final jobs,
      ):
        // Compressed frames leave as transferables, as from a capture.
        answer(
          id,
          () => [
            for (final result in LottieEngineWork.writeTextures(
              binding,
              codec,
              reader,
              entryPoints,
              format,
              [
                for (final (texture, width, height, work) in jobs)
                  LottieTextureJob(
                    texture: texture,
                    width: width,
                    height: height,
                    work: switch (work) {
                      final LottieTextureRender render => render,
                      _ => LottieTextureRestore(_fromWire(work)),
                    },
                  ),
              ],
            ))
              (
                result.outcome,
                result.compressed == null
                    ? null
                    : TransferableTypedData.fromList([result.compressed!]),
              ),
          ],
        );
      case _Dispose(:final id, :final handle):
        answer(id, () => binding.dispose(handle));
      case _Close():
        // Closing the port is what ends the isolate, even if the binding
        // throws while closing.
        try {
          reader.close();
          binding.close();
        } finally {
          commands.close();
        }
    }
  });
  boot.replies.send(_Ready(commands.sendPort));
}
