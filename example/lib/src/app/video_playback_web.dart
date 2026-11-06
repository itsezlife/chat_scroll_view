import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:chat_scroll_view_example/src/app/video_playback_pixel.dart';
import 'package:flutter/foundation.dart';
import 'package:video_decoder/web.dart';

/// Plays video with the browser's own decoder: a hidden `<video>` element per
/// clip. There is nothing to probe, a browser that cannot play a file refuses
/// it at open and that clip keeps its placeholder.
Future<VideoPlayback?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
}) => startPixelVideoPlayback(
  clock: clock,
  memoryPressure: memoryPressure,
  engineFactory: () async =>
      WebVideoEngine(createPort: JsVideoElementPort.create),
);
