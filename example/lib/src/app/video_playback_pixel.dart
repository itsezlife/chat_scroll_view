import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:chat_scroll_view_example/src/common/scroll_lab.dart';
import 'package:flutter/foundation.dart';
import 'package:video_decoder/video_decoder.dart';

/// Starts the video decoder over an engine from [engineFactory], or answers
/// null.
///
/// [textures] and [textureWriter] (which makes the writer of the engine, or
/// null for one that cannot write textures) let playing clips take platform
/// textures (ADR 043).
///
/// [engineFactory] is the probe: any failure to produce an engine (the native
/// library missing, a browser that refuses) logs once, with the error's type,
/// and gives no playback, so nothing is registered and video keeps its
/// placeholder. Neutral Dart on purpose, with no `dart:js_interop` and no
/// `dart:ffi`, so the composition runs on the VM in tests over an engine on a
/// fake; the platform files supply only the factory.
Future<VideoPlayback?> startPixelVideoPlayback({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  required Future<VideoEngine> Function() engineFactory,
  FrameTexturePool? textures,
  TextureFrameWriter? Function(VideoEngine engine)? textureWriter,
}) async {
  final VideoEngine engine;
  try {
    engine = await engineFactory();
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
    maxAdvancing: ScrollLab.videoCap.value,
    textures: textures,
    textureWriter: textureWriter?.call(engine),
  )..texturesEnabled = ScrollLab.textures.value;
  // The scroll lab's `video_cap` and `textures` switches change the live
  // scheduler.
  void applyCap() => scheduler.maxAdvancing = ScrollLab.videoCap.value;
  void applyTextures() => scheduler.texturesEnabled = ScrollLab.textures.value;
  ScrollLab.videoCap.addListener(applyCap);
  ScrollLab.textures.addListener(applyTextures);
  // The scheduler goes first: it may still be asking the engine for frames.
  // The engine is disposed last and frees every clip still open.
  return VideoPlayback(
    decoder: VideoDecoder(engine: engine, scheduler: scheduler),
    shutdown: [
      () => ScrollLab.videoCap.removeListener(applyCap),
      () => ScrollLab.textures.removeListener(applyTextures),
      scheduler.dispose,
      engine.dispose,
    ],
  );
}
