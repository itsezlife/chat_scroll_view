import 'dart:typed_data';

import 'package:catalog_assets/frame_pool.dart';
import 'package:video_decoder/src/renderer/video_frame_source.dart';

/// A [FrameRenderer] that copies frames the engine already decoded into the
/// pool's pages: the job's `frame` is the number of a decoded frame and its
/// `source` a [VideoFrameSource].
///
/// Nothing is decoded here. A video decodes sequentially and ahead of the
/// clock (see `VideoFrameScheduler`), so by the time a frame is asked for its
/// pixels exist; the renderer is the last copy, from the scheduler's buffer
/// into the slot, one row at a time because the slot's rows are a page width
/// apart and the frame's are not.
///
/// The bytes stay BGRA: the video pool's pages are BGRA from the first copy to
/// the upload (see `VideoFrameAtlas`), so no channel is swapped on the way.
/// A job whose frame is gone is left out of the result, as the contract says.
final class VideoFrameRenderer implements FrameRenderer {
  /// Creates the renderer.
  const VideoFrameRenderer();

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    final held = <int>[];
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      final source = job.source;
      if (source is! VideoFrameSource) {
        throw ArgumentError.value(
          source,
          'job.source',
          'must be a VideoFrameSource',
        );
      }
      final pixels = source.pixelsOf(job.frame);
      if (pixels == null) continue;
      _copy(pixels, job, memory);
      held.add(i);
    }
    return held;
  }

  static void _copy(Uint8List pixels, FrameJob job, FramePageMemory memory) {
    final side = job.slot.pageSide;
    final page = memory.page(job.slot.pageIndex, side: side);
    final left = job.slot.rect.left.toInt();
    final top = job.slot.rect.top.toInt();
    const bytes = FramePageMemory.bytesPerPixel;
    final rowBytes = job.width * bytes;
    for (var y = 0; y < job.height; y++) {
      final to = ((top + y) * side + left) * bytes;
      page.setRange(to, to + rowBytes, pixels, y * rowBytes);
    }
  }
}
