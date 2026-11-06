import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:video_native/video_native.dart';

/// One playing video as the engine sees it, whatever carries it: a hidden
/// `<video>` element in a browser, a script in a test.
///
/// The seam of [WebVideoEngine]. Everything that needs `dart:js_interop`
/// is behind it, so the engine's own rules (the element cap, timeouts,
/// ordering, the pixel conversion, the mapping of failures) run on the VM.
/// A port is real time: the browser decides when a frame is presented, and
/// [nextFrame] waits for it.
///
/// Calls on one port never overlap: the engine serves one clip's requests in
/// order.
abstract interface class VideoElementPort {
  /// Waits for the video to be ready to draw and describes it.
  ///
  /// Throws a [VideoElementFailure] for bytes the browser refuses. The engine
  /// bounds the wait, so a port may wait as long as the browser does.
  Future<VideoElementMetadata> loadMetadata();

  /// Completes with the next frame the browser presents, drawn at the size the
  /// port was made for, or with [VideoElementEnded] once the video ended.
  ///
  /// Starts playback when the video is not playing. Throws a
  /// [VideoElementFailure] when it cannot draw.
  Future<VideoElementFrameResult> nextFrame();

  /// Seeks to the start; the next [nextFrame] plays from there. Throws a
  /// [VideoElementFailure] when the video cannot seek.
  Future<void> rewind();

  /// Releases the element and everything it holds, and completes any request
  /// still waiting with a [VideoElementFailure]. Idempotent.
  void dispose();
}

/// What a video declares once its first frame is ready.
@immutable
final class VideoElementMetadata {
  /// Creates the description.
  const VideoElementMetadata({
    required this.width,
    required this.height,
    required this.duration,
    required this.hasAlpha,
  });

  /// The source width in pixels.
  final int width;

  /// The source height in pixels.
  final int height;

  /// The duration, or null for a stream without a finite one.
  final Duration? duration;

  /// Whether the first frame has transparent pixels (see
  /// `VideoFramePixels.hasTransparency`): a browser declares no alpha, so
  /// this is what the port saw.
  final bool hasAlpha;
}

/// The answer of [VideoElementPort.nextFrame].
sealed class VideoElementFrameResult {
  const VideoElementFrameResult();
}

/// A presented frame: straight (not premultiplied) RGBA, tightly packed, at
/// the size the port draws, which is the engine's target size.
final class VideoElementFrame extends VideoElementFrameResult {
  /// Creates a frame presented [ptsMs] milliseconds into the video.
  const VideoElementFrame(this.rgba, this.ptsMs);

  /// The pixels, `width * height * 4` bytes.
  final Uint8List rgba;

  /// The presentation time in milliseconds from the start.
  final int ptsMs;
}

/// The video played to its end; it stays so until [VideoElementPort.rewind].
final class VideoElementEnded extends VideoElementFrameResult {
  /// Creates the end marker.
  const VideoElementEnded();
}

/// A port could not do what it was asked.
///
/// For [loadMetadata][VideoElementPort.loadMetadata] the [reason] is the
/// rejection the open ends in; for the other calls only "it failed" matters.
final class VideoElementFailure implements Exception {
  /// Creates the failure.
  const VideoElementFailure(this.reason, [this.message = '']);

  /// Why, in the vocabulary of the native binding.
  final VideoRejection reason;

  /// What the browser said, when it said anything.
  final String message;

  @override
  String toString() => 'VideoElementFailure($reason, $message)';
}
