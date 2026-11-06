import 'package:catalog_assets/frame_pool.dart';
import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/memory/native_frame_page_memory.dart';
import 'package:lottie_decoder/src/renderer/lottie_source.dart';
import 'package:lottie_native/lottie_native.dart';

/// A [FrameRenderer] that draws through a [LottieEngine] into one
/// [NativeFramePageMemory].
///
/// A job's `source` is the [LottieSource] of a loaded file. A batch is one
/// engine call; an engine error propagates.
final class LottieFrameRenderer implements FrameRenderer {
  /// Creates a renderer of [engine] that writes into [memory] only.
  LottieFrameRenderer({
    required LottieEngine engine,
    required NativeFramePageMemory memory,
  }) : _engine = engine,
       _memory = memory;

  final LottieEngine _engine;
  final NativeFramePageMemory _memory;

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    if (!identical(memory, _memory)) {
      throw StateError('This renderer was built for another page memory.');
    }
    final engineJobs = <LottieEngineJob>[];
    for (final job in jobs) {
      final handle = switch (job.source) {
        final LottieSource source => source.handle,
        final other => throw ArgumentError.value(
          other,
          'job.source',
          'must be a LottieSource',
        ),
      };
      final side = _memory.pageSide;
      final left = job.slot.rect.left.toInt();
      final top = job.slot.rect.top.toInt();
      engineJobs.add(
        LottieEngineJob(
          handle: handle,
          frame: job.frame.toDouble(),
          width: job.width,
          height: job.height,
          address:
              _memory.addressOf(job.slot.pageIndex) +
              (top * side + left) * FramePageMemory.bytesPerPixel,
          strideBytes: side * FramePageMemory.bytesPerPixel,
        ),
      );
    }
    if (engineJobs.isEmpty) return const <int>[];
    final statuses = await _engine.renderBatch(engineJobs);
    return [
      for (var i = 0; i < statuses.length; i++)
        if (statuses[i] == LottieRenderStatus.ok) i,
    ];
  }
}
