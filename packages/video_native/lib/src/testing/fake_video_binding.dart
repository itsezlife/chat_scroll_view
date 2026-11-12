import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:video_native/src/video_availability.dart';
import 'package:video_native/src/video_binding.dart';
import 'package:video_native/src/video_frame_result.dart';
import 'package:video_native/src/video_handle.dart';
import 'package:video_native/src/video_open_result.dart';

/// A [VideoBinding] without a native library: scripted files, and frames that
/// fill their slot with one premultiplied colour derived from the frame
/// index.
final class FakeVideoBinding implements VideoBinding {
  /// Creates a fake that reports [availability]; anything but
  /// [VideoAvailability.available] behaves as an unusable library.
  FakeVideoBinding({this.availability = VideoAvailability.available});

  /// The largest target edge the real library accepts.
  static const maxTargetEdge = 2048;

  @override
  final VideoAvailability availability;

  // What each scripted file answers. A scripted VideoOpened carries a
  // placeholder handle: open issues a fresh one per call.
  final _scripted = <String, _Script>{};
  final _live = <int, _Playback>{};
  var _closed = false;
  var _nextHandle = 1;

  /// How many opened handles are not yet disposed.
  int get liveHandles => _live.length;

  /// Makes [bytes] open as a video described by [info] with [frameCount]
  /// frames.
  void accept(Uint8List bytes, VideoInfo info, {required int frameCount}) {
    _scripted[_key(bytes)] = _Script.accepted(info, frameCount);
  }

  /// Makes [bytes] refuse to open for [reason]. Bytes never scripted are
  /// refused as [VideoRejection.malformed].
  void reject(Uint8List bytes, VideoRejection reason) {
    _scripted[_key(bytes)] = _Script.rejected(reason);
  }

  static String _key(Uint8List bytes) => base64.encode(bytes);

  @override
  bool get isAvailable => availability == VideoAvailability.available;

  void _requireAvailable() {
    if (!isAvailable) throw StateError('The video binding is not available.');
    if (_closed) throw StateError('The video binding is closed.');
  }

  @override
  VideoOpenResult open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) {
    _requireAvailable();
    if (width <= 0 ||
        height <= 0 ||
        width > maxTargetEdge ||
        height > maxTargetEdge) {
      return const VideoRejected(VideoRejection.badSize);
    }
    final script = _scripted[_key(bytes)];
    if (script == null) return const VideoRejected(VideoRejection.malformed);
    final rejection = script.rejection;
    if (rejection != null) return VideoRejected(rejection);

    final id = _nextHandle++;
    _live[id] = _Playback(script.info!, script.frameCount, width, height);
    return VideoOpened(VideoHandle(id), script.info!);
  }

  @override
  VideoFrameResult nextFrame(
    VideoHandle handle, {
    required Pointer<Uint8> target,
    required int strideBytes,
  }) {
    _requireAvailable();
    final playback = _live[handle.id];
    if (playback == null || target.address == 0) {
      return const VideoFrameResult(VideoFrameStatus.badArgument);
    }
    if (strideBytes < playback.width * 4) {
      return const VideoFrameResult(VideoFrameStatus.badSize);
    }
    if (playback.next >= playback.frameCount) {
      return const VideoFrameResult(VideoFrameStatus.endOfStream);
    }

    // Alpha is fixed and the colour channels stay under it, so the pixel is a
    // valid premultiplied one; blue moves with the frame so frames differ.
    const alpha = 200;
    final index = playback.next++;
    final blue = (index * 16) % (alpha + 1);
    final pixel = [blue, blue ~/ 2, 0, alpha];
    final bytes = target.asTypedList(
      strideBytes * (playback.height - 1) + playback.width * 4,
    );
    for (var y = 0; y < playback.height; y++) {
      for (var x = 0; x < playback.width; x++) {
        final at = y * strideBytes + x * 4;
        bytes.setRange(at, at + 4, pixel);
      }
    }
    final rate = playback.info.frameRate;
    final ptsMs = rate > 0 ? (index * 1000 / rate).round() : index * 40;
    return VideoFrameResult(VideoFrameStatus.frame, ptsMs);
  }

  @override
  bool rewind(VideoHandle handle) {
    _requireAvailable();
    final playback = _live[handle.id];
    if (playback == null) return false;
    playback.next = 0;
    return true;
  }

  @override
  void dispose(VideoHandle handle) {
    _live.remove(handle.id);
  }

  @override
  void close() {
    _closed = true;
    _live.clear();
  }
}

final class _Script {
  const _Script.accepted(VideoInfo this.info, this.frameCount)
    : rejection = null;
  const _Script.rejected(VideoRejection this.rejection)
    : info = null,
      frameCount = 0;

  final VideoInfo? info;
  final int frameCount;
  final VideoRejection? rejection;
}

final class _Playback {
  _Playback(this.info, this.frameCount, this.width, this.height);

  final VideoInfo info;
  final int frameCount;
  final int width;
  final int height;
  int next = 0;
}
