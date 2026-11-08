import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';

/// A build without `dart:ffi` (the web) has no native video library.
Future<VideoPlayback?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  FrameTexturePool? textures,
}) async {
  l.i('Video stickers are off: this platform has no native video library');
  return null;
}
