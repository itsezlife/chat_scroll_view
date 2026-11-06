import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';

/// A build without `dart:ffi` (the web) has no native Lottie library.
Future<({Decoder decoder, Future<void> Function() close})?> start({
  required PlaybackClock clock,
  required Listenable memoryPressure,
}) async {
  l.i('Lottie stickers are off: this platform has no native Lottie library');
  return null;
}
