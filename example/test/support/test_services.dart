import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/services.dart';

/// The app's services over in-memory storage and the bundled emoji catalogue,
/// for host-integration tests.
///
/// [storage] is the key-value store a test may pre-fill and read back;
/// [loader] replaces the bundle read (to observe it).
Future<AppServices> createTestServices({
  FakeKeyValueStore? storage,
  EmojiAssetLoader? loader,
}) => AppServices.create(
  keyValueStore: storage ?? FakeKeyValueStore(),
  assetLoader: loader ?? rootBundle.loadString,
);
