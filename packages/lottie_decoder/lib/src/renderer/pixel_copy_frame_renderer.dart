import 'package:catalog_assets/frame_pool.dart';
import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/renderer/lottie_source.dart';

/// A [FrameRenderer] that asks a [LottieEngine] for pixels and copies them
/// into the page memory: the renderer of an engine that cannot write to an
/// address, which is every web engine.
///
/// A job's `source` is the [LottieSource] of a loaded file. A batch is one
/// `renderPixels` call; an engine error propagates. The result lists the jobs
/// whose engine answered pixels.
///
/// There is no frame cache here: the compressed frames of `FrameCache` come
/// from a slot engine's codec, which a pixel engine does not have, so the web
/// renders every frame it shows and keeps nothing between sessions. A
/// [LottieSource.cacheKey] is ignored.
///
/// Any [FramePageMemory] serves: `ListFramePageMemory` on the web, native
/// memory where a host wants one memory for both renderers.
final class PixelCopyFrameRenderer implements FrameRenderer {
  /// Creates a renderer of [engine].
  PixelCopyFrameRenderer(this._engine);

  final LottieEngine _engine;

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    if (jobs.isEmpty) return const <int>[];
    final pixelJobs = [
      for (final job in jobs)
        LottiePixelJob(
          handle: _sourceOf(job).handle,
          frame: job.frame.toDouble(),
          width: job.width,
          height: job.height,
        ),
    ];
    final frames = await _engine.renderPixels(pixelJobs);
    final held = <int>[];
    for (var i = 0; i < jobs.length; i++) {
      final pixels = frames[i];
      if (pixels == null) continue;
      _copy(pixels, jobs[i], memory);
      held.add(i);
    }
    return held;
  }

  static LottieSource _sourceOf(FrameJob job) => switch (job.source) {
    final LottieSource source => source,
    final other => throw ArgumentError.value(
      other,
      'job.source',
      'must be a LottieSource',
    ),
  };

  /// Writes the rows of [pixels] from the slot's top left corner, one row at
  /// a time: the slot's rows are a page width apart, the frame's are not.
  static void _copy(LottiePixels pixels, FrameJob job, FramePageMemory memory) {
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
