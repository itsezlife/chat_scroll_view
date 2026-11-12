import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:meta/meta.dart';
import 'package:video_decoder/src/engine/texture_calls.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_decoder/src/renderer/video_frame_source.dart';

/// A [VideoEngine] that can also write decoded frames into platform textures
/// on the isolate that decodes them (ADR 043, "Writing").
///
/// Native only (the lock and post are C calls); the in-process engine and the
/// worker pool are both one.
abstract interface class VideoTextureEngine implements VideoEngine {
  /// Writes every job into its texture: locks it through [entryPoints],
  /// clears its margins, copies the frame centred at the lock's stride,
  /// swapping red and blue when [format] is not the decoder's BGRA, and
  /// posts. One outcome per job, in job order; a texture that cannot be
  /// locked at once is [TextureFrameOutcome.notLocked] and untouched.
  Future<List<TextureFrameOutcome>> writeTextures(
    FrameTextureEntryPoints entryPoints,
    FrameTextureFormat format,
    List<VideoTextureJob> jobs,
  );
}

/// One decoded frame to write into a texture.
@immutable
final class VideoTextureJob {
  /// Creates a job: [pixels] of a frame of [clip] into [texture].
  const VideoTextureJob({
    required this.clip,
    required this.texture,
    required this.pixels,
  });

  /// The clip the frame is of: its size, and the worker that decodes it.
  final VideoClip clip;

  /// The texture: its id and its size.
  final AssetTexture texture;

  /// The frame, `clip.frameBytes` bytes of premultiplied BGRA in packed rows.
  final Uint8List pixels;
}

/// The texture copy both engines run, on the isolate that calls the C entry
/// points.
abstract final class VideoTextureWork {
  /// Writes one frame of [width] x [height] pixels into [texture].
  static TextureFrameOutcome write(
    TextureCalls calls,
    FrameTextureFormat format,
    AssetTexture texture,
    int width,
    int height,
    Uint8List pixels,
  ) {
    final lock = calls.lock(texture, width, height);
    if (lock == null) return TextureFrameOutcome.notLocked;
    try {
      lock.region.copyInto(
        lock.view,
        pixels,
        swapRedBlue: format != FrameTextureFormat.bgra8888,
      );
    } finally {
      calls.post(texture);
    }
    return TextureFrameOutcome.posted;
  }
}

/// The [TextureFrameWriter] of a [VideoTextureEngine] and a host: hands each
/// job's decoded frame to the engine, which copies it into the texture on the
/// worker that decoded it.
///
/// A job's `source` is the scheduler's [VideoFrameSource]; a job whose frame
/// is gone (its clip was released while the batch waited) fails.
final class VideoFrameTextureWriter implements TextureFrameWriter {
  /// Creates a writer of [engine] into [host]'s textures. Throws an
  /// [ArgumentError] for a host that gives no C entry points.
  VideoFrameTextureWriter({
    required VideoTextureEngine engine,
    required FrameTextureHost host,
  }) : _engine = engine,
       _host = host,
       _points =
           host.entryPoints ??
           (throw ArgumentError.value(
             host,
             'host',
             'gives no entry points a decode worker can call',
           ));

  final VideoTextureEngine _engine;
  final FrameTextureHost _host;
  final FrameTextureEntryPoints _points;

  @override
  Future<List<TextureFrameOutcome>> write(List<TextureFrameJob> jobs) async {
    if (jobs.isEmpty) return const [];
    final outcomes = List.filled(jobs.length, TextureFrameOutcome.failed);
    final sent = <int>[];
    final work = <VideoTextureJob>[];
    for (var i = 0; i < jobs.length; i++) {
      final source = switch (jobs[i].source) {
        final VideoFrameSource source => source,
        final other => throw ArgumentError.value(
          other,
          'job.source',
          'must be a VideoFrameSource',
        ),
      };
      final pixels = source.pixelsOf(jobs[i].frame);
      if (pixels == null) continue;
      sent.add(i);
      work.add(
        VideoTextureJob(
          clip: source.clip,
          texture: jobs[i].texture,
          pixels: pixels,
        ),
      );
    }
    if (work.isEmpty) return outcomes;
    final written = await _engine.writeTextures(_points, _host.format, work);
    for (var k = 0; k < sent.length; k++) {
      outcomes[sent[k]] = written[k];
    }
    return outcomes;
  }
}
