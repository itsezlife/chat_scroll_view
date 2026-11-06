import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:video_decoder/video_decoder.dart';

/// Starts the decode isolates, which is the probe: it throws a
/// `VideoUnavailable` naming why when the library is missing or speaks
/// another version.
///
/// [spawn] is `IsolateVideoEngine.spawn` unless a test passes an engine of
/// its own. The probe means "the engine could not start, for any reason": on
/// any failure it logs once, with the error's type, and answers null, so
/// nothing is registered and video keeps its placeholder.
Future<VideoPlayback?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  Future<VideoEngine> Function() spawn = IsolateVideoEngine.spawn,
}) async {
  final VideoEngine engine;
  try {
    engine = await spawn();
  } on Object catch (reason, stackTrace) {
    // The probe's answer, not a bug to propagate: whatever stopped the
    // engine starting, the app boots without video.
    VideoPlayback.reportUnavailable(reason, stackTrace);
    return null;
  }
  final scheduler = VideoFrameScheduler(
    engine: engine,
    atlas: VideoFrameAtlas.create(memoryPressure: memoryPressure),
    clock: clock,
  );
  // The scheduler goes first: it may still be asking the engine for frames.
  // The engine is disposed last and frees every clip still open.
  return VideoPlayback(
    decoder: VideoDecoder(engine: engine, scheduler: scheduler),
    shutdown: [scheduler.dispose, engine.dispose],
  );
}
