import 'dart:async';

import 'package:catalog_assets/src/pool/frame_renderer.dart';

/// A [FrameRenderer] that fills the job's region with a colour taken from the
/// frame, so a test can tell which frame a slot holds.
///
/// Every pixel of the region is opaque with red set to the frame index (mod
/// 256) and green set to 255 minus it. A job whose source is [rejected] is
/// left out of the result, as a renderer that cannot parse its file would.
/// [pause] holds every batch until [resume], to model a late frame.
final class FakeFrameRenderer implements FrameRenderer {
  /// The source that makes a job fail.
  static const Object rejected = 'rejected';

  Completer<void>? _gate;

  /// Batches rendered, in order, each as the frames it was asked for.
  final List<List<int>> batches = <List<int>>[];

  /// Holds every batch from now until [resume].
  void pause() => _gate ??= Completer<void>();

  /// Lets the held batches go.
  void resume() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<List<FrameJob>> render(
    List<FrameJob> jobs,
    FramePageMemory memory,
  ) async {
    final gate = _gate;
    if (gate != null) await gate.future;
    if (jobs.isEmpty) return const <FrameJob>[];
    batches.add([for (final job in jobs) job.frame]);

    final rendered = <FrameJob>[];
    for (final job in jobs) {
      if (job.source == rejected) continue;
      _write(job, memory);
      rendered.add(job);
    }
    return rendered;
  }

  void _write(FrameJob job, FramePageMemory memory) {
    final side = memory.pageSide;
    final bytes = memory.page(job.slot.pageIndex);
    final left = job.slot.rect.left.toInt();
    final top = job.slot.rect.top.toInt();
    final red = job.frame % 256;
    for (var y = 0; y < job.height; y++) {
      for (var x = 0; x < job.width; x++) {
        final at = ((top + y) * side + left + x) * 4;
        bytes[at] = red;
        bytes[at + 1] = 255 - red;
        bytes[at + 2] = 0;
        bytes[at + 3] = 255;
      }
    }
  }
}
