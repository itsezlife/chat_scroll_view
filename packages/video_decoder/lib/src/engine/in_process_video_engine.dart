import 'dart:typed_data';

import 'package:video_decoder/src/engine/video_decode_core.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_native/video_native.dart';

/// A [VideoEngine] that runs a [VideoBinding] on the calling isolate; its
/// futures complete at once.
///
/// For tests (over `FakeVideoBinding`), hosts that want no isolate, and as
/// the proof that the worker isolate adds transport only: both run the same
/// `VideoDecodeCore`.
final class InProcessVideoEngine implements VideoEngine {
  /// Creates an engine over [binding], which it owns and closes.
  InProcessVideoEngine(VideoBinding binding) : _core = VideoDecodeCore(binding);

  final VideoDecodeCore _core;
  bool _disposed = false;

  void _requireOpen() {
    if (_disposed) throw VideoEngineClosed();
  }

  @override
  Future<VideoClipOpenResult> open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    _requireOpen();
    return _core.open(bytes, width: width, height: height);
  }

  @override
  Future<VideoFrameResult> nextFrame(
    VideoClip clip, {
    required Uint8List destination,
  }) async {
    _requireOpen();
    return _core.nextFrame(clip.id, destination);
  }

  @override
  Future<bool> rewind(VideoClip clip) async {
    _requireOpen();
    return _core.rewind(clip.id);
  }

  @override
  Future<void> close(VideoClip clip) async => _core.close(clip.id);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _core.dispose();
  }
}
