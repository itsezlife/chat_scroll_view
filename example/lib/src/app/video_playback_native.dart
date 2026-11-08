import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:chat_scroll_view_example/src/app/video_playback_pixel.dart';
import 'package:flutter/foundation.dart';
import 'package:video_decoder/video_decoder.dart';

/// Starts the decode isolates, which is the probe: it throws a
/// `VideoUnavailable` naming why when the library is missing or speaks
/// another version.
///
/// [spawn] is `IsolateVideoEngine.spawn` unless a test passes an engine of
/// its own. The composition is the one the web shares.
Future<VideoPlayback?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  FrameTexturePool? textures,
  Future<VideoEngine> Function() spawn = IsolateVideoEngine.spawn,
}) => startPixelVideoPlayback(
  clock: clock,
  memoryPressure: memoryPressure,
  engineFactory: spawn,
  textureWriter: textures == null
      ? null
      : (engine) => engine is VideoTextureEngine
            ? VideoFrameTextureWriter(engine: engine, host: textures.host)
            : null,
  textures: textures,
);
