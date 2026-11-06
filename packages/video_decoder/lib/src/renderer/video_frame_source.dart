import 'dart:typed_data';

/// What a [VideoFrameRenderer] renders: a clip's decoded frames, by number.
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
}
