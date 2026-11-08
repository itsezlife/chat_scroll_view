import 'dart:async';

import 'package:catalog_assets/src/texture/texture_frame_writer.dart';

/// A [TextureFrameWriter] that writes nothing and records what it was asked.
///
/// Every job is [TextureFrameOutcome.posted] unless [outcomeOf] says
/// otherwise for its texture id; a job whose source is [rejected] is
/// [TextureFrameOutcome.failed], as a writer whose engine cannot render it.
/// [pause] holds every batch until [resume], to model a late frame.
final class FakeTextureFrameWriter implements TextureFrameWriter {
  /// The source that makes a job fail.
  static const Object rejected = 'rejected';

  Completer<void>? _gate;

  /// Batches written, in order, each as its jobs.
  final List<List<TextureFrameJob>> batches = [];

  /// The outcome of a job by its texture's id; absent ids are posted.
  final Map<int, TextureFrameOutcome> outcomeOf = {};

  /// Every texture id posted, in order.
  Iterable<int> get posts => [
    for (final batch in batches)
      for (final job in batch)
        if (_outcome(job) == TextureFrameOutcome.posted) job.texture.id,
  ];

  /// Holds every batch from now until [resume].
  void pause() => _gate ??= Completer<void>();

  /// Lets the held batches go.
  void resume() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<List<TextureFrameOutcome>> write(List<TextureFrameJob> jobs) async {
    final gate = _gate;
    if (gate != null) await gate.future;
    if (jobs.isEmpty) return const [];
    batches.add(List.unmodifiable(jobs));
    return [for (final job in jobs) _outcome(job)];
  }

  TextureFrameOutcome _outcome(TextureFrameJob job) => job.source == rejected
      ? TextureFrameOutcome.failed
      : outcomeOf[job.texture.id] ?? TextureFrameOutcome.posted;
}
