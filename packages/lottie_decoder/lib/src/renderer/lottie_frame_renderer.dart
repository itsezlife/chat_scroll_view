import 'package:catalog_assets/frame_pool.dart';
import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_decoder/src/memory/native_frame_page_memory.dart';
import 'package:lottie_native/lottie_native.dart';

/// A [FrameRenderer] that draws through a [LottieEngine] into one
/// [NativeFramePageMemory].
///
/// A job's `source` is the [LottieHandle] of a loaded file. A batch is one
/// engine call; an engine error propagates.
final class LottieFrameRenderer implements FrameRenderer {
  /// Creates a renderer of [engine] that writes into [memory] only.
  LottieFrameRenderer(this._engine, this._memory);

  final LottieEngine _engine;
  final NativeFramePageMemory _memory;

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    if (!identical(memory, _memory)) {
      throw StateError('This renderer was built for another page memory.');
    }
    final engineJobs = <LottieEngineJob>[];
    for (final job in jobs) {
      // An extension type on int: the check below is `is int` at run time.
      final source = job.source;
      if (source is! LottieHandle) {
        throw ArgumentError.value(
          source,
          'job.source',
          'must be a LottieHandle',
        );
      }
      final side = _memory.pageSide;
      final left = job.slot.rect.left.toInt();
      final top = job.slot.rect.top.toInt();
      engineJobs.add(
        LottieEngineJob(
          handle: source as LottieHandle,
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
