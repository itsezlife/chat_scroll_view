import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';

/// A build without `dart:ffi` (the web) has no native Lottie library.
Future<LottiePlayback?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
}) async {
  l.i('Lottie stickers are off: this platform has no native Lottie library');
  return null;
}
