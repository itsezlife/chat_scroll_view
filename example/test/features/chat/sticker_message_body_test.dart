/// The body of the message a picked sticker or GIF is sent as.
///
/// **Seam:** [StickerMessageBody], read back through the same rules the chat
/// uses to show it (`EmojiOnlyText`).
library;

import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_message_body.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('is the lone document the showcase sends: alt text and the key', () {
    final sticker = LottieStickerPack.stickers.first;

    expect(
      StickerMessageBody.of(sticker),
      '![${sticker.spokenName}](${sticker.key.encoded})',
    );
  });

  test(
    'reads back as emoji-only with the one document, so it is a sticker',
    () {
      for (final item in VideoStickerPack.items) {
        final emojiOnly = EmojiOnlyText.of(
          RichTextMarkdown.decode(StickerMessageBody.of(item)),
        );

        expect(emojiOnly?.items.single.key, item.key, reason: item.name);
      }
    },
  );

  test('is made for the key of a bundled sticker or gif, and for no other', () {
    final item = VideoStickerPack.clips.first;

    expect(StickerMessageBody.ofKey(item.key), StickerMessageBody.of(item));
    expect(StickerMessageBody.ofKey(const ContentKey.document('nope')), isNull);
    expect(
      StickerMessageBody.ofKey(const ContentKey.unicode('\u{1F44D}')),
      isNull,
    );
  });

  test('is not made for a custom emoji: that is inserted as text', () {
    final emoji = BundledPacks.descriptors.firstWhere(
      (d) => d.semanticKind == SemanticKind.customEmoji,
    );

    expect(StickerMessageBody.ofKey(emoji.key), isNull);
  });
}
