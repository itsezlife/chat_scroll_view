import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart' show RichTextMarkdown;

/// Which pack a tap in the chat opens, and which packs a message's custom
/// emoji come from: the pack reference of the content's descriptor
/// (ADR 044, "Chat to sheet").
///
/// The viewport reports only content keys and embed targets; what a key is,
/// and so its pack, is the host's ([DescribeContent]). No pack, nothing
/// opens: a GIF, a unicode emoji, a sticker sent without a pack.
abstract final class ChatPackTargets {
  /// The pack of the lone document [key] (a sticker or a custom emoji of an
  /// emoji-only body), or null.
  static PackId? ofContent(ContentKey key, DescribeContent describe) =>
      switch (key) {
        ContentKey$Document() => describe(key)?.pack,
        ContentKey$Unicode() || ContentKey$External() => null,
      };

  /// The pack of the inline embed whose markup target is [target]
  /// (`scheme:id`), or null when the target is no content key.
  static PackId? ofEmbed(String target, DescribeContent describe) =>
      switch (ContentKey.tryParse(target)) {
        final key? => ofContent(key, describe),
        null => null,
      };

  /// The packs of the custom emoji in the markdown [body], each once, in the
  /// order the text first names them: what the message menu's "contains
  /// emoji from N packs" lists. A sticker of a pack is not an emoji: a lone
  /// sticker's body names no emoji pack.
  static List<PackId> emojiPacksOf(String body, DescribeContent describe) {
    final packs = <PackId>{};
    for (final entity in RichTextMarkdown.decode(body).entities) {
      if (entity.kind case EntityKind$InlineContent(:final key)) {
        if (describe(key) case ContentDescriptor(
          semanticKind: SemanticKind.customEmoji,
          :final pack?,
        )) {
          packs.add(pack);
        }
      }
    }
    return List.unmodifiable(packs);
  }
}
