import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:lottie_native/src/lottie_binding.dart';
import 'package:lottie_native/src/lottie_features.dart';
import 'package:lottie_native/src/lottie_load_result.dart';
import 'package:lottie_native/src/native/chat_lottie_symbols.dart';
import 'package:meta/meta.dart';

/// The ABI version of `chat_lottie.h` this binding was written against.
const _expectedAbiVersion = 1;

/// [LottieBinding] over the compiled `chat_lottie` library.
///
/// Register it only when [isAvailable]. The binding hands out integer
/// handles and keeps the native pointers behind them, so a disposed or
/// invented handle is a `badArgument` and never reaches native code as a
/// dangling pointer.
final class NativeLottieBinding implements LottieBinding {
  /// Probes the library once: a guarded `chat_lottie_abi_version()` call.
  ///
  /// A missing library or symbol (an `ArgumentError` at the first call) or a
  /// version other than 1 yields a binding that is not available. Nothing is
  /// logged here; the host logs once through its diagnostics.
  factory NativeLottieBinding.probe() =>
      NativeLottieBinding.probing(chatLottieAbiVersion);

  /// Probes with [abiVersion] instead of the real symbol, so a test can stand
  /// in a library that lacks it or speaks another version.
  @visibleForTesting
  NativeLottieBinding.probing(int Function() abiVersion)
    : isAvailable = _probe(abiVersion);

  static bool _probe(int Function() abiVersion) {
    try {
      return abiVersion() == _expectedAbiVersion;
      // A symbol the library lacks surfaces as an ArgumentError; any other
      // failure to call is the same answer for the host: not available.
    } on Object {
      return false;
    }
  }

  @override
  final bool isAvailable;

  final Map<int, Pointer<Void>> _handles = {};
  int _nextId = 1;

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
      if (status != 0) return LottieRejected(_rejection(status));

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
      if (status != 0) {
        return List.filled(jobs.length, LottieRenderStatus.badArgument);
      }
      return [
        for (var i = 0; i < jobs.length; i++) _jobStatus(jobs[i], statuses[i]),
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

  void _requireAvailable() {
    if (!isAvailable) {
      throw StateError(
        'The native Lottie library is not available; register a '
        'NativeLottieBinding only when isAvailable is true.',
      );
    }
  }

  // Header: -2 over a size cap, -4 a renderer limit, -5 nothing to draw;
  // -3 and anything unknown (including -1) read as a bad file.
  static LottieRejection _rejection(int status) => switch (status) {
    -2 => LottieRejection.tooLarge,
    -4 => LottieRejection.limitExceeded,
    -5 => LottieRejection.unsupported,
    _ => LottieRejection.malformed,
  };

  // The library answers a zero size with -1; the interface (and its fake)
  // call that badSize once the handle, target and frame are fine, so the
  // contract reads the same over both.
  LottieRenderStatus _jobStatus(LottieRenderJob job, int status) {
    final mapped = _renderStatus(status);
    if (mapped == LottieRenderStatus.badArgument &&
        (job.width <= 0 || job.height <= 0) &&
        _handles.containsKey(job.handle.id) &&
        job.target.address != 0 &&
        job.frame.isFinite &&
        job.frame >= 0) {
      return LottieRenderStatus.badSize;
    }
    return mapped;
  }

  // Header: -1 bad argument, -2 stride or size overflow, -3 render failed.
  static LottieRenderStatus _renderStatus(int status) => switch (status) {
    0 => LottieRenderStatus.ok,
    -1 => LottieRenderStatus.badArgument,
    -2 => LottieRenderStatus.badSize,
    _ => LottieRenderStatus.failed,
  };
}
