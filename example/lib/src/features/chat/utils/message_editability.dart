import 'package:chat_scroll_view/chat_scroll_view.dart' show IChatMessage;
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/corpus_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_content.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart' show RichTextMarkdown;

/// Which messages the user may edit, decided by what the message is.
///
/// A sticker or a GIF sent as a message has no text to change, so no edit
/// action is offered on one: not in the message menu,
/// not from the selection bar, not by any shortcut. A message is one of them
/// when its body is a lone document that the bundled packs describe as a
/// sticker or a GIF. A custom emoji alone is text with an emoji in it and is
/// editable; so is a lone document nobody describes, since nothing says it is
/// not text.
///
/// Every door to edit mode asks here, so the rule lives in one place and a new
/// door cannot forget it.
abstract final class MessageEditability {
  /// Whether [message] may be edited: unless its body is a sticker or a GIF.
  ///
  /// Who may edit what (a user's own messages) is the chat's policy and is not
  /// decided here; this is only the rule by what the message is.
  static bool canEdit(IChatMessage message) => switch (message) {
    UserChatMessage(:final emojiOnly) => !_isStickerOrGif(emojiOnly),
    _ => true,
  };

  /// Whether a message with the markdown [body] may be edited.
  static bool canEditBody(String body) =>
      !_isStickerOrGif(EmojiOnlyText.of(RichTextMarkdown.decode(body)));

  static bool _isStickerOrGif(EmojiOnly? emojiOnly) {
    if (emojiOnly == null || emojiOnly.items.length != 1) return false;
    final key = emojiOnly.items.single.key;
    if (key is! ContentKey$Document) return false;
    // Content the host lists but does not bundle is a sticker or a GIF by its
    // key alone: a restart has not described it yet.
    if (GiphyContent.isKey(key) || CorpusStickerPack.isKey(key)) return true;
    return switch (BundledPacks.of(key)?.descriptor.semanticKind) {
      SemanticKind.sticker || SemanticKind.gif => true,
      _ => false,
    };
  }
}
