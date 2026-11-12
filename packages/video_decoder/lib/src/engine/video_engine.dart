import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:video_native/video_native.dart';

/// The async face of a video decoder: open a file as a clip, pull its frames
/// one by one into a caller's buffer, rewind to loop, close.
///
/// The one seam every platform has: a native engine decodes in a worker and
/// copies the pixels out, a web engine would hand over what the browser
/// decoded. Handles, statuses and rejections are the binding's own
/// (`VideoInfo`, `VideoFrameResult`, `VideoRejection`); an engine adds the
/// asynchrony and the pixel copy.
///
/// Decoding is sequential, and that is the contract, not an implementation
/// detail: frames of one clip come in presentation order, there is no seek to
/// a time, and looping is [rewind] followed by the next [nextFrame]. Calls on
/// one clip are served in the order they were made, so a caller may issue
/// several without awaiting each; calls on different clips may run
/// concurrently.
abstract interface class VideoEngine {
  /// Opens [bytes] for frames of exactly [width] by [height] pixels: frames
  /// are scaled to that size, not letterboxed.
  ///
  /// A refused file is a [VideoClipRejected], never a throw.
  Future<VideoClipOpenResult> open(
    Uint8List bytes, {
    required int width,
    required int height,
  });

  /// Decodes the next frame of [clip] into the first `clip.frameBytes` bytes
  /// of [destination]: tightly packed premultiplied BGRA, byte order
  /// `[B, G, R, A]`, rows `clip.width * 4` bytes apart.
  ///
  /// The result is the binding's: a frame with its time, the end of the
  /// stream (which stays until [rewind]), or a failure. A [destination]
  /// shorter than `clip.frameBytes` is `VideoFrameStatus.badSize`, and a
  /// closed or unknown clip is `VideoFrameStatus.badArgument`; neither
  /// touches the clip. [destination] is written only when the status is
  /// `VideoFrameStatus.frame`, and not after the returned future completes.
  Future<VideoFrameResult> nextFrame(
    VideoClip clip, {
    required Uint8List destination,
  });

  /// Seeks [clip] to its first frame. False for a closed or unknown clip, or
  /// a stream that cannot seek.
  Future<bool> rewind(VideoClip clip);

  /// Releases [clip]. Idempotent, and harmless once the engine is disposed
  /// (its clips went with it).
  Future<void> close(VideoClip clip);

  /// Retires the engine and every clip it holds. Requests already made run
  /// to completion first (or until a bound the engine documents), so nothing
  /// writes to a caller's buffer after its future completes. Idempotent;
  /// [open], [nextFrame] and [rewind] afterwards throw a [VideoEngineClosed].
  Future<void> dispose();
}

/// One open video: what an engine hands back from `open` and takes in every
/// other call.
///
/// A value naming a clip inside the engine that issued it; it holds no
/// resources, so dropping it without [VideoEngine.close] leaks the clip in
/// the engine, not in the caller.
@immutable
final class VideoClip {
  /// Creates the description of an open clip.
  const VideoClip({
    required this.id,
    required this.info,
    required this.width,
    required this.height,
  });

  /// The engine's name for the clip; unique within one engine.
  final int id;

  /// What the file declares about itself.
  final VideoInfo info;

  /// The width of delivered frames, as asked at open.
  final int width;

  /// The height of delivered frames, as asked at open.
  final int height;

  /// The bytes one frame occupies: `width * height * 4`.
  int get frameBytes => width * height * 4;

  @override
  bool operator ==(Object other) => other is VideoClip && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VideoClip($id, ${width}x$height)';
}

/// The outcome of [VideoEngine.open]: a closed set, so a caller handles both
/// and a bad file is a value, never an exception.
sealed class VideoClipOpenResult {
  const VideoClipOpenResult();
}

/// The file opened; [clip] yields frames until it is closed.
final class VideoClipOpened extends VideoClipOpenResult {
  /// Creates the result of a successful open.
  const VideoClipOpened(this.clip);

  /// The open clip.
  final VideoClip clip;
}

/// The file did not open; nothing is held.
final class VideoClipRejected extends VideoClipOpenResult {
  /// Creates the result of a refused file.
  const VideoClipRejected(this.reason);

  /// Why, as the binding reported it (carried through unchanged).
  final VideoRejection reason;
}

/// An engine was used after it was disposed (or after every worker ended):
/// the clips it issued are gone with it, so a caller closing one may ignore
/// this and nothing else.
///
/// A [StateError] so code that only wants "unusable engine" keeps working;
/// a catch site that must tell this case apart matches this type, never the
/// bare [StateError].
final class VideoEngineClosed extends StateError {
  /// Creates the error; [message] says which way the engine ended.
  VideoEngineClosed([super.message = 'The video engine is disposed.']);
}

/// A worker could not serve: its binding reported [availability] other than
/// `available`. The host does not register the decoder.
final class VideoUnavailable extends StateError {
  /// Creates the error for a binding that reported [availability].
  VideoUnavailable(this.availability)
    : super(
        'The video binding is not available in the decode worker: '
        '${availability.name}.',
      );

  /// Why the binding cannot serve.
  final VideoAvailability availability;
}

/// The worker holding a clip ended, so the clip is gone; other clips are
/// unaffected.
///
/// A [StateError] like [VideoEngineClosed]. A caller drops the clip and may
/// open the file again, which lands on a worker that still runs.
final class VideoClipLost extends StateError {
  /// Creates the error; [message] says what ended the worker, when known.
  VideoClipLost([super.message = 'The decode worker holding the clip ended.']);
}
