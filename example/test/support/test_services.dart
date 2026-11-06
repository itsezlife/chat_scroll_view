import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/lottie_playback.dart';
import 'package:chat_scroll_view_example/src/app/video_playback.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/corpus_sticker_pack.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// The app's services over in-memory storage and the bundled emoji catalogue,
/// for host-integration tests.
///
/// [storage] is the key-value store a test may pre-fill and read back;
/// [loader] replaces the bundle read (to observe it). The clipboard is a
/// `FakeRichClipboard`, which a test reads back.
///
/// Neither Giphy nor a local sticker corpus is on unless [giphyApiKey] (with a
/// fake [giphyHttpClient]) or [corpus] says so: a test never sends a request,
/// and never lists files a maintainer keeps on their machine.
///
/// Lottie playback is off unless [startLottie] says otherwise: the platform
/// without the library, which every host must handle, and no render isolate in
/// the many tests that do not draw stickers.
Future<AppServices> createTestServices({
  FakeKeyValueStore? storage,
  EmojiAssetLoader? loader,
  LottiePlaybackStarter startLottie = _noLottie,
  VideoPlaybackStarter startVideo = _noVideo,
  String giphyApiKey = '',
  http.Client? giphyHttpClient,
  CorpusStickerPack corpus = CorpusStickerPack.none,
}) => AppServices.create(
  startLottie: startLottie,
  startVideo: startVideo,
  giphyApiKey: giphyApiKey,
  giphyHttpClient: giphyHttpClient,
  corpus: corpus,
  keyValueStore: storage ?? FakeKeyValueStore(),
  assetLoader: loader ?? rootBundle.loadString,
  clipboard: FakeRichClipboard(),
);

Future<LottiePlayback?> _noLottie({
  required PlaybackClock clock,
  required Listenable memoryPressure,
  String? cacheDirectory,
}) async => null;

Future<VideoPlayback?> _noVideo({
  required PlaybackClock clock,
  required Listenable memoryPressure,
}) async => null;
