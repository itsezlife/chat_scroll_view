/// Which messages the host lets the user edit: by what the message is, not by
/// who sent it. A sticker or a GIF has no text to edit (the reference client
/// offers no edit action on one); text, a custom emoji and unknown content do.
///
/// **Seam:** [MessageEditability], over a body and over a message.
library;

import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_editability.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_message_body.dart';
import 'package:flutter_test/flutter_test.dart';

UserChatMessage _message(String content) => UserChatMessage(
  id: 1,
  sender: 'me',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: content,
);

void main() {
  group('MessageEditability.canEditBody', () {
    test('lets text be edited', () {
      expect(MessageEditability.canEditBody('hello **world**'), isTrue);
    });

    test('lets a custom emoji alone be edited: it is text with an emoji', () {
      final emoji = AnimatedEmojiPack.emoji.first;
      expect(
        MessageEditability.canEditBody(
          '![${emoji.sequence}](${emoji.key.encoded})',
        ),
        isTrue,
      );
    });

    test('forbids editing a sticker of each bundled pack', () {
      for (final sticker in [
        ...LottieStickerPack.stickers,
        ...StaticStickerPack.stickers,
        ...VideoStickerPack.stickers,
      ]) {
        expect(
          MessageEditability.canEditBody(StickerMessageBody.of(sticker)),
          isFalse,
          reason: sticker.key.encoded,
        );
      }
    });

    test('forbids editing an MP4 clip or a GIF sent as a message', () {
      for (final gif in [...VideoStickerPack.clips, ...VideoStickerPack.gifs]) {
        expect(
          MessageEditability.canEditBody(StickerMessageBody.of(gif)),
          isFalse,
          reason: gif.key.encoded,
        );
      }
    });

    test('lets a document nobody described be edited', () {
      expect(
        MessageEditability.canEditBody('![?](document:missing-1)'),
        isTrue,
      );
    });

    test('lets a sticker with words around it be edited as text', () {
      final sticker = LottieStickerPack.stickers.first;
      expect(
        MessageEditability.canEditBody(
          'look ${StickerMessageBody.of(sticker)}',
        ),
        isTrue,
      );
    });
  });

  group('MessageEditability.canEdit', () {
    test('follows the body of a user message', () {
      expect(MessageEditability.canEdit(_message('hi')), isTrue);
      expect(
        MessageEditability.canEdit(
          _message(StickerMessageBody.of(VideoStickerPack.gifs.first)),
        ),
        isFalse,
      );
    });

    test('leaves the rest to the chat: a system message is text', () {
      expect(
        MessageEditability.canEdit(
          SystemChatMessage(
            id: 2,
            sender: 'system',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            content: 'joined',
          ),
        ),
        isTrue,
      );
    });
  });
}
