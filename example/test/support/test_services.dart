import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's services over in-memory storage and the bundled emoji catalogue,
/// for host-integration tests.
///
/// [storage] is the key-value store a test may pre-fill and read back;
/// [loader] replaces the bundle read (to observe it). The clipboard is a
/// `FakeRichClipboard`, which a test reads back.
///
/// Lottie playback is off unless [startLottie] says otherwise: the platform
/// without the library, which every host must handle, and no render isolate in
/// the many tests that do not draw stickers.
Future<AppServices> createTestServices({
  FakeKeyValueStore? storage,
  EmojiAssetLoader? loader,
  LottiePlaybackStarter startLottie = _noLottie,
}) => AppServices.create(
  startLottie: startLottie,
  keyValueStore: storage ?? FakeKeyValueStore(),
  assetLoader: loader ?? rootBundle.loadString,
  clipboard: FakeRichClipboard(),
);

Future<LottiePlayback?> _noLottie({
  required PlaybackClock clock,
  required Listenable memoryPressure,
}) async => null;
