import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:video_decoder/web.dart';

/// The web hook behind [VideoPlayback.start]: plays video with the browser's
/// own decoder, a hidden `<video>` element per clip. There is nothing to
/// probe, a browser that cannot play a file refuses it at open and that clip
/// keeps its placeholder.
Future<VideoPlayback?> $startVideoPlayback({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  FrameTexturePool? textures,
}) => VideoPlayback.startPixel(
  clock: clock,
  memoryPressure: memoryPressure,
  engineFactory: () async =>
      WebVideoEngine(createPort: JsVideoElementPort.create),
);
