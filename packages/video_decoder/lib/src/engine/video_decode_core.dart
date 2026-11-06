import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_native/video_native.dart';

/// What the in-process engine and every worker isolate do with a binding, on
/// the isolate that owns it, so the two cannot drift.
///
/// Owns one native scratch buffer per open clip (the binding writes frames to
/// an address; a caller's `Uint8List` has none) and frees it with the clip.
/// Clip ids are the binding's handle ids. Not thread-safe: one isolate, one
/// core.
final class VideoDecodeCore {
  /// Creates a core over [_binding], which it owns and closes.
  VideoDecodeCore(this._binding);

  final VideoBinding _binding;
  final _clips = <int, _OpenClip>{};

  /// How many clips are open.
  int get openClips => _clips.length;

  /// Opens [bytes] at [width] by [height].
  VideoClipOpenResult open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) {
    switch (_binding.open(bytes, width: width, height: height)) {
      case VideoRejected(:final reason):
        return VideoClipRejected(reason);
      case VideoOpened(:final handle, :final info):
        final clip = VideoClip(
          id: handle.id,
          info: info,
          width: width,
          height: height,
        );
        _clips[clip.id] = _OpenClip(handle, width, height);
        return VideoClipOpened(clip);
    }
  }

  /// Decodes the next frame of clip [id] and copies it into [destination].
  VideoFrameResult nextFrame(int id, Uint8List destination) {
    final open = _clips[id];
    if (open == null) {
      return const VideoFrameResult(VideoFrameStatus.badArgument);
    }
    if (destination.length < open.frameBytes) {
      return const VideoFrameResult(VideoFrameStatus.badSize);
    }
    final result = _binding.nextFrame(
      open.handle,
      target: open.scratch,
      strideBytes: open.rowBytes,
    );
    if (result.status == VideoFrameStatus.frame) {
      destination.setRange(
        0,
        open.frameBytes,
        open.scratch.asTypedList(open.frameBytes),
      );
    }
    return result;
  }

  /// Seeks clip [id] to its start.
  bool rewind(int id) {
    final open = _clips[id];
    return open != null && _binding.rewind(open.handle);
  }

  /// Closes clip [id]; idempotent.
  void close(int id) {
    final open = _clips.remove(id);
    if (open == null) return;
    _binding.dispose(open.handle);
    calloc.free(open.scratch);
  }

  /// Closes every clip and the binding.
  void dispose() {
    for (final open in _clips.values) {
      calloc.free(open.scratch);
    }
    _clips.clear();
    _binding.close();
  }
}

final class _OpenClip {
  _OpenClip(this.handle, int width, int height)
    : rowBytes = width * 4,
      frameBytes = width * height * 4,
      scratch = calloc<Uint8>(width * height * 4);

  final VideoHandle handle;
  final int rowBytes;
  final int frameBytes;
  final Pointer<Uint8> scratch;
}
