import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:content_model/content_model.dart';

/// The body of the message a picked sticker or GIF is sent as: the item as a
/// lone document, `![alt](document:id)`, which the chat reads as an emoji-only
/// body of one document and shows as the sticker it is (`ChatBodyHost`).
///
/// The same body the showcase conversation carries for the items of the demo
/// packs, so a sent sticker looks like a seeded one.
abstract final class StickerMessageBody {
  /// The body that sends [item].
  static String of(BundledItem item) =>
      '![${item.descriptor.spokenName}](${item.key.encoded})';

  /// The body that sends the content [key], or null when [key] is not a
  /// bundled sticker or GIF: a unicode or custom emoji is inserted into the
  /// composer as text, not sent as a message of its own.
  static String? ofKey(ContentKey key) {
    final item = BundledPacks.of(key);
    if (item == null) return null;
    return switch (item.descriptor.semanticKind) {
      SemanticKind.sticker || SemanticKind.gif => of(item),
      _ => null,
    };
  }
}
