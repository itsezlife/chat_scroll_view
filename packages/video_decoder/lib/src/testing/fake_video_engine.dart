import 'dart:convert';
import 'dart:typed_data';

import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_native/video_native.dart';

/// A [VideoEngine] in plain Dart, with no binding and no isolate: scripted
/// files, and frames that fill their buffer with one premultiplied colour
/// derived from the frame index (the same pixels as `FakeVideoBinding`).
///
/// For tests of what sits above the engine (paintables, schedulers); it
/// compiles for the web. Futures complete at once.
final class FakeVideoEngine implements VideoEngine {
  final _scripted = <String, _Script>{};
  final _clips = <int, _Playback>{};
  var _nextId = 1;
  var _disposed = false;

  /// How many clips are open.
  int get openClips => _clips.length;

  /// Makes [bytes] open as a video described by [info] with [frameCount]
  /// frames.
  void accept(Uint8List bytes, VideoInfo info, {required int frameCount}) {
    _scripted[_key(bytes)] = _Script(info, frameCount, null);
  }

  /// Makes [bytes] refuse to open for [reason]. Bytes never scripted are
  /// refused as [VideoRejection.malformed].
  void reject(Uint8List bytes, VideoRejection reason) {
    _scripted[_key(bytes)] = _Script(null, 0, reason);
  }

  static String _key(Uint8List bytes) => base64.encode(bytes);

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
    if (width <= 0 || height <= 0) {
      return const VideoClipRejected(VideoRejection.badSize);
    }
    final script = _scripted[_key(bytes)];
    if (script == null)
      return const VideoClipRejected(VideoRejection.malformed);
    final rejection = script.rejection;
    if (rejection != null) return VideoClipRejected(rejection);

    final clip = VideoClip(
      id: _nextId++,
      info: script.info!,
      width: width,
      height: height,
    );
    _clips[clip.id] = _Playback(clip, script.frameCount);
    return VideoClipOpened(clip);
  }

  @override
  Future<VideoFrameResult> nextFrame(
    VideoClip clip, {
    required Uint8List destination,
  }) async {
    _requireOpen();
    final playback = _clips[clip.id];
    if (playback == null) {
      return const VideoFrameResult(VideoFrameStatus.badArgument);
    }
    if (destination.length < clip.frameBytes) {
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
    for (var at = 0; at < clip.frameBytes; at += 4) {
      destination.setRange(at, at + 4, pixel);
    }
    final rate = clip.info.frameRate;
    final ptsMs = rate > 0 ? (index * 1000 / rate).round() : index * 40;
    return VideoFrameResult(VideoFrameStatus.frame, ptsMs);
  }

  @override
  Future<bool> rewind(VideoClip clip) async {
    _requireOpen();
    final playback = _clips[clip.id];
    if (playback == null) return false;
    playback.next = 0;
    return true;
  }

  @override
  Future<void> close(VideoClip clip) async {
    _clips.remove(clip.id);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _clips.clear();
  }
}

final class _Script {
  const _Script(this.info, this.frameCount, this.rejection);

  final VideoInfo? info;
  final int frameCount;
  final VideoRejection? rejection;
}

final class _Playback {
  _Playback(this.clip, this.frameCount);

  final VideoClip clip;
  final int frameCount;
  int next = 0;
}
