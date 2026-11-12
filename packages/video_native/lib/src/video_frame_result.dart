import 'package:meta/meta.dart';

/// What `VideoBinding.nextFrame` did.
enum VideoFrameStatus {
  /// The target holds the next frame; `VideoFrameResult.ptsMs` is its time.
  frame,

  /// The stream has no more frames. Stays so until `VideoBinding.rewind`.
  endOfStream,

  /// An unknown or disposed handle, or a null target.
  badArgument,

  /// A stride under the row width, or too small a target for the size the
  /// video was opened at.
  badSize,

  /// The data could not be decoded (damaged stream, or a decode budget
  /// exceeded). The handle is spent until a successful rewind.
  failed,
}

/// The status of one `nextFrame` call and, for a frame, its presentation time.
@immutable
final class VideoFrameResult {
  /// Creates a result.
  const VideoFrameResult(this.status, [this.ptsMs = 0]);

  /// What happened.
  final VideoFrameStatus status;

  /// The frame's presentation time in milliseconds from the start; 0 unless
  /// [status] is [VideoFrameStatus.frame].
  final int ptsMs;

  @override
  bool operator ==(Object other) =>
      other is VideoFrameResult &&
      other.status == status &&
      other.ptsMs == ptsMs;

  @override
  int get hashCode => Object.hash(status, ptsMs);

  @override
  String toString() => 'VideoFrameResult($status, $ptsMs ms)';
}
