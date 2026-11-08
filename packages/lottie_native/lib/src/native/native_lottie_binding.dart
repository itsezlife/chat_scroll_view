import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:lottie_native/src/lottie_availability.dart';
import 'package:lottie_native/src/lottie_binding.dart';
import 'package:lottie_native/src/lottie_features.dart';
import 'package:lottie_native/src/lottie_handle.dart';
import 'package:lottie_native/src/lottie_load_result.dart';
import 'package:lottie_native/src/lottie_render_status.dart';
import 'package:lottie_native/src/native/chat_lottie_symbols.dart';
import 'package:meta/meta.dart';

/// [LottieBinding] over the compiled `chat_lottie` library.
///
/// Register it only when [isAvailable]. The binding hands out integer
/// handles and keeps the native pointers behind them, so a disposed or
/// invented handle is a `badArgument` and never reaches native code as a
/// dangling pointer.
final class NativeLottieBinding implements LottieBinding {
  /// Probes the library once: a guarded `chat_lottie_abi_version()` call.
  ///
  /// A missing library or symbol (an `ArgumentError` at the first call) is
  /// [LottieAvailability.missingLibrary]; a version other than 1 is
  /// [LottieAvailability.abiMismatch]. Any other error is not an answer about
  /// the library and propagates. Nothing is logged here; the host logs once
  /// through its diagnostics.
  factory NativeLottieBinding.probe() =>
      NativeLottieBinding.probing(chatLottieAbiVersion);

  /// Probes with [abiVersion] instead of the real symbol, so a test can stand
  /// in a library that lacks it or speaks another version.
  @visibleForTesting
  NativeLottieBinding.probing(int Function() abiVersion)
    : availability = _probe(abiVersion);

  static LottieAvailability _probe(int Function() abiVersion) {
    try {
      return abiVersion() == ChatLottieAbi.expectedVersion
          ? LottieAvailability.available
          : LottieAvailability.abiMismatch;
      // A symbol the library lacks surfaces as exactly this Error: it is the
      // dynamic-linking answer being probed for, not a bug to propagate.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return LottieAvailability.missingLibrary;
    }
  }

  @override
  final LottieAvailability availability;

  @override
  bool get isAvailable => availability == LottieAvailability.available;

  final Map<int, Pointer<Void>> _handles = {};
  int _nextId = 1;
  bool _closed = false;

  @override
  LottieLoadResult load(Uint8List bytes) {
    _requireAvailable();
    // Never a zero-length allocation: the library gets a valid pointer and
    // refuses the empty file itself.
    final data = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final info = calloc<ChatLottieInfo>();
    final out = calloc<Pointer<Void>>();
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      final status = chatLottieLoad(data, bytes.length, info, out);
      if (status != ChatLottieStatus.ok) {
        return LottieRejected(rejectionFor(status));
      }

      final id = _nextId++;
      _handles[id] = out.value;
      return LottieLoaded(
        LottieHandle(id),
        LottieInfo(
          width: info.ref.width,
          height: info.ref.height,
          frameCount: info.ref.frameCount,
          frameRate: info.ref.frameRate,
          features: LottieFeatures(info.ref.features),
        ),
      );
    } finally {
      calloc
        ..free(data)
        ..free(info)
        ..free(out);
    }
  }

  @override
  List<LottieRenderStatus> renderBatch(List<LottieRenderJob> jobs) {
    _requireAvailable();
    if (jobs.isEmpty) return const [];
    final native = calloc<ChatLottieJob>(jobs.length);
    final statuses = calloc<Int32>(jobs.length);
    try {
      for (var i = 0; i < jobs.length; i++) {
        final job = jobs[i];
        native[i]
          // An unknown handle is a null pointer: the library answers it with
          // its own bad-argument status, in the batch, like any bad job.
          ..handle = _handles[job.handle.id] ?? nullptr
          ..frame = job.frame
          ..width = job.width
          ..height = job.height
          ..target = job.target
          ..strideBytes = job.strideBytes;
      }
      final status = chatLottieRenderBatch(native, jobs.length, statuses);
      // A nonzero batch status means jobs or statuses was null, which this
      // code cannot produce: a bug here, not a verdict on any job.
      if (status != ChatLottieStatus.ok) {
        throw StateError('chat_lottie_render_batch returned $status.');
      }
      return [
        for (var i = 0; i < jobs.length; i++) renderStatusFor(statuses[i]),
      ];
    } finally {
      calloc
        ..free(native)
        ..free(statuses);
    }
  }

  @override
  void dispose(LottieHandle handle) {
    final pointer = _handles.remove(handle.id);
    if (pointer != null) chatLottieFree(pointer);
  }

  @override
  void close() {
    _closed = true;
    _handles.values.forEach(chatLottieFree);
    _handles.clear();
  }

  void _requireAvailable() {
    if (!isAvailable) {
      throw StateError(
        'The native Lottie library is not available; register a '
        'NativeLottieBinding only when isAvailable is true.',
      );
    }
    if (_closed) throw StateError('The native Lottie binding is closed.');
  }

  /// The rejection a load [status] stands for; anything unknown reads as a
  /// bad file.
  @visibleForTesting
  static LottieRejection rejectionFor(int status) => switch (status) {
    ChatLottieStatus.tooLarge => LottieRejection.tooLarge,
    ChatLottieStatus.limitExceeded => LottieRejection.limitExceeded,
    ChatLottieStatus.unsupported => LottieRejection.unsupported,
    ChatLottieStatus.internal => LottieRejection.internal,
    _ => LottieRejection.malformed,
  };

  /// The job status a render [status] stands for; anything unknown is a
  /// failed render.
  @visibleForTesting
  static LottieRenderStatus renderStatusFor(int status) => switch (status) {
    ChatLottieStatus.ok => LottieRenderStatus.ok,
    ChatLottieStatus.invalidArgument => LottieRenderStatus.badArgument,
    ChatLottieStatus.badSize => LottieRenderStatus.badSize,
    _ => LottieRenderStatus.failed,
  };
}
