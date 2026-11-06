import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:video_native/src/native/chat_video_symbols.dart';
import 'package:video_native/src/video_availability.dart';
import 'package:video_native/src/video_binding.dart';
import 'package:video_native/src/video_frame_result.dart';
import 'package:video_native/src/video_handle.dart';
import 'package:video_native/src/video_open_result.dart';

/// [VideoBinding] over the compiled `chat_video` library.
final class NativeVideoBinding implements VideoBinding {
  /// Probes the library once: a guarded `chat_video_abi_version()` call.
  ///
  /// A missing library or symbol (an `ArgumentError` at the first call) is
  /// [VideoAvailability.missingLibrary]; a version other than the expected
  /// one is [VideoAvailability.abiMismatch]. Any other error is not an answer
  /// about the library and propagates.
  factory NativeVideoBinding.probe() =>
      NativeVideoBinding.probing(chatVideoAbiVersion);

  /// Probes with [abiVersion] instead of the real symbol, so a test can stand
  /// in a library that lacks it or speaks another version.
  @visibleForTesting
  NativeVideoBinding.probing(int Function() abiVersion)
    : availability = _probe(abiVersion);

  static VideoAvailability _probe(int Function() abiVersion) {
    try {
      return abiVersion() == chatVideoExpectedAbiVersion
          ? VideoAvailability.available
          : VideoAvailability.abiMismatch;
      // A symbol the library lacks surfaces as exactly this Error: it is the
      // dynamic-linking answer being probed for, not a bug to propagate.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return VideoAvailability.missingLibrary;
    }
  }

  @override
  final VideoAvailability availability;

  @override
  bool get isAvailable => availability == VideoAvailability.available;

  final Map<int, Pointer<Void>> _handles = {};
  int _nextId = 1;
  bool _closed = false;

  @override
  VideoOpenResult open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) {
    _requireAvailable();
    // Never a zero-length allocation: the library gets a valid pointer and
    // refuses the empty file itself.
    final data = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final info = calloc<ChatVideoInfo>();
    final out = calloc<Pointer<Void>>();
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      final status = chatVideoOpen(data, bytes.length, width, height, out);
      if (status != ChatVideoStatus.ok) {
        return VideoRejected(rejectionFor(status));
      }
      final handle = out.value;
      if (chatVideoInfo(handle, info) != ChatVideoStatus.ok) {
        chatVideoFree(handle);
        throw StateError(
          'chat_video_info refused a handle chat_video_open made.',
        );
      }
      final id = _nextId++;
      _handles[id] = handle;
      return VideoOpened(
        VideoHandle(id),
        VideoInfo(
          width: info.ref.width,
          height: info.ref.height,
          duration: info.ref.durationMs < 0
              ? null
              : Duration(milliseconds: info.ref.durationMs),
          frameRate: info.ref.frameRate,
          hasAlpha: info.ref.hasAlpha != 0,
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
  VideoFrameResult nextFrame(
    VideoHandle handle, {
    required Pointer<Uint8> target,
    required int strideBytes,
  }) => throw UnimplementedError();

  @override
  bool rewind(VideoHandle handle) => throw UnimplementedError();

  @override
  void dispose(VideoHandle handle) {
    final pointer = _handles.remove(handle.id);
    if (pointer != null) chatVideoFree(pointer);
  }

  @override
  void close() {
    _closed = true;
    _handles.values.forEach(chatVideoFree);
    _handles.clear();
  }

  void _requireAvailable() {
    if (!isAvailable) {
      throw StateError(
        'The native video library is not available; register a '
        'NativeVideoBinding only when isAvailable is true.',
      );
    }
    if (_closed) throw StateError('The native video binding is closed.');
  }

  /// The rejection an open [status] stands for; anything unknown is a
  /// malformed file.
  @visibleForTesting
  static VideoRejection rejectionFor(int status) => switch (status) {
    ChatVideoStatus.tooLarge => VideoRejection.tooLarge,
    ChatVideoStatus.limitExceeded => VideoRejection.limitExceeded,
    ChatVideoStatus.unsupported => VideoRejection.unsupported,
    ChatVideoStatus.badSize => VideoRejection.badSize,
    ChatVideoStatus.internal => VideoRejection.internal,
    _ => VideoRejection.malformed,
  };
}
