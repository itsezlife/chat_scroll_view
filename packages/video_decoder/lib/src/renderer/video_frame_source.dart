import 'dart:typed_data';

import 'package:video_decoder/src/engine/video_engine.dart';

/// What a [VideoFrameRenderer] renders, and a texture writer writes: a
/// clip's decoded frames, by number.
///
/// The pool never looks inside a job's source; this is the one thing the video
/// renderer needs of it. The scheduler implements it over the frames it has
/// decoded and not yet drawn.
abstract interface class VideoFrameSource {
  /// The premultiplied BGRA bytes of the decoded frame numbered [frame],
  /// `width * height * 4` of them, or null when the frame is gone (its clip
  /// was released while a batch waited).
  ///
  /// Valid until the batch that asked ends; the renderer copies and keeps
  /// nothing.
  Uint8List? pixelsOf(int frame);

  /// The clip the frames are of: a texture writer copies them on the worker
  /// that decodes it.
  VideoClip get clip;
}
