/// The demo's bundled clips as player sources: a clip of the video pack
/// plays from a file of its bundled bytes; other content has no source.
library;

import 'dart:io';

import 'package:chat_scroll_view_example/src/features/chat/data/demo_video_sources.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_player/mpx_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a bundled clip plays from a local file of its bytes, once copied',
    () async {
      final folder = await Directory.systemTemp.createTemp('demo-video-');
      addTearDown(() => folder.delete(recursive: true));
      final sources = DemoVideoSources(folder: folder);
      final clip = VideoStickerPack.clips.first;

      final first = await sources.of(clip.key.mediaKey);
      expect(first, hasLength(1));
      final source = first.single;
      expect(source.kind, PlayerSourceKind.local);
      final file = File.fromUri(source.request.url);
      final bundled = await rootBundle.load(clip.assetPath);
      expect(await file.readAsBytes(), bundled.buffer.asUint8List());

      final again = await sources.of(clip.key.mediaKey);
      expect(again.single.request.url, source.request.url);
    },
  );

  test('content that is not a bundled clip has no source', () async {
    final folder = await Directory.systemTemp.createTemp('demo-video-');
    addTearDown(() => folder.delete(recursive: true));
    final sources = DemoVideoSources(folder: folder);

    expect(
      await sources.of(const ContentKey.document('elsewhere').mediaKey),
      isEmpty,
    );
  });
}
