/// A message of one video item (a WebM sticker, an MP4 clip, a GIF), as the
/// showcase chat sends it: it is built as a sticker (art without a bubble),
/// asks the asset cache for the pack's document, and loops.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_emoji_message.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final sticker in [
    VideoStickerPack.stickers.first,
    VideoStickerPack.clips.first,
    VideoStickerPack.gifs.first,
  ])
    testWidgets('a lone ${sticker.extension} builds as a sticker and asks the '
        'cache for its document', (tester) async {
      final producer = FakeAssetProducer();
      final scope = AssetCacheScope(producer: producer);
      final policy = ValueNotifier(const LargeEmojiPolicy(enabled: true));
      final selection = ChatSelectionController();
      final host = ChatBodyHost(assets: scope, policy: policy);
      addTearDown(() {
        selection.dispose();
        policy.dispose();
        scope.dispose();
      });
      final emojiOnly = EmojiOnly([EmojiOnlyItem(sticker.key)]);
      expect(host.stickerOf(emojiOnly), sticker.key);
      expect(host.playbackFor(sticker.key).loops, isTrue);

      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DemoEmojiMessage(
              messageId: 1,
              emojiOnly: emojiOnly,
              selection: selection,
              host: host,
              createdAt: DateTime(2026, 1, 1, 9, 5),
              isOutgoing: false,
              policy: const ChatEmojiPolicy.android(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ChatEmojiBody), findsOneWidget);
      expect(
        producer.attempts.map((attempt) => attempt.request.key),
        contains(sticker.key),
      );
    });
}
