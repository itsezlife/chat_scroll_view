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
      _body(item.descriptor.spokenName, item.key);

  /// The body that sends the content [key], or null when [key] is not a
  /// bundled sticker or GIF: a unicode or custom emoji is inserted into the
  /// composer as text, not sent as a message of its own.
  ///
  /// [describe] says what the host knows of a key: the bundled packs unless
  /// the host passes its own, which also knows content from elsewhere.
  static String? ofKey(
    ContentKey key, {
    DescribeContent describe = BundledPacks.describe,
  }) {
    final descriptor = describe(key);
    if (descriptor == null) return null;
    return switch (descriptor.semanticKind) {
      SemanticKind.sticker ||
      SemanticKind.gif => _body(descriptor.spokenName, key),
      _ => null,
    };
  }

  /// The content key a message body of [of] or [ofKey] sends, or null for
  /// any other body: the reverse of the two.
  static ContentKey? keyOf(String body) =>
      switch (_lone.firstMatch(body.trim())?.group(1)) {
        final target? => ContentKey.tryParse(target),
        null => null,
      };

  static final RegExp _lone = RegExp(r'^!\[[^\]]*\]\(([^)\s]+)\)$');

  // A name from outside may hold what ends the alt text of an image or the
  // line; it is read aloud, so dropping those characters costs nothing.
  static String _body(String? name, ContentKey key) =>
      '![${(name ?? '').replaceAll(RegExp(r'[\[\]\\\r\n]+'), ' ').trim().replaceAll(RegExp(' {2,}'), ' ')}](${key.encoded})';
}
