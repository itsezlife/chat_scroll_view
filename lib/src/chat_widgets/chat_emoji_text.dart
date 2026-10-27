import 'dart:ui' show TextRange;

import 'package:content_model/content_model.dart'
    show ContentKey$Document, ContentKey$Unicode, EmojiOnly;
import 'package:flutter_md/flutter_md.dart';
import 'package:meta/meta.dart';

/// The text of an emoji-only body as the viewport's text selection reads it:
/// one markdown paragraph, so the facade's range, select-all, copy and
/// structured copy (`ChatTextCopy.content`) are the markdown body's own
/// machinery and the body needs no selection engine of its own.
///
/// The body never paints this model; it gives the facade the same registry
/// entry a markdown body does, and answers geometry for it through the
/// selection surface contract (`MarkdownSelectionSurface`). Each item is one
/// atomic run of the rendered text:
///
/// - a unicode item is its sequence, so a ZWJ family is one run of eight
///   units and a selection never lands inside it, because the surface only
///   answers item edges;
/// - a custom emoji is an image span whose text is the item's `alt` and whose
///   `src` names the document, as a parsed `![alt](key)` is;
/// - a line break is a `\n` between two items, as in a markdown paragraph.
///
/// Spaces and tabs between emoji are not here, as they are not in
/// [EmojiOnly]: a copy of a selection holds the emoji and the breaks.
@internal
final class ChatEmojiText {
  const ChatEmojiText._(this.text, this.itemRanges, this.markdown);

  /// The model of [emojiOnly].
  factory ChatEmojiText.of(EmojiOnly emojiOnly) {
    final text = StringBuffer();
    final source = StringBuffer();
    final ranges = <TextRange>[];
    final spans = <MD$Span>[];
    void breaks(int count) {
      if (count == 0) return;
      final run = '\n' * count;
      text.write(run);
      source.write(run);
      spans.add(
        MD$Span(start: text.length - count, end: text.length, text: run),
      );
    }

    for (final item in emojiOnly.items) {
      breaks(item.lineBreaksBefore);
      final start = text.length;
      switch (item.key) {
        case ContentKey$Unicode(:final sequence):
          text.write(sequence);
          source.write(sequence);
          spans.add(MD$Span(start: start, end: text.length, text: sequence));
        case ContentKey$Document(:final encoded):
          // A custom emoji without text still needs a character to select.
          final alt = item.alt.isEmpty ? _objectReplacement : item.alt;
          text.write(alt);
          source.write('![$alt]($encoded)');
          spans.add(
            MD$Span(
              start: start,
              end: text.length,
              text: alt,
              style: MD$Style.image,
              extra: <String, Object?>{
                'type': 'image',
                'src': encoded,
                'url': encoded,
              },
            ),
          );
        case _:
          // No other key can be an item (`EmojiOnlyText` makes these two).
          break;
      }
      ranges.add(TextRange(start: start, end: text.length));
    }
    return ChatEmojiText._(
      text.toString(),
      List.unmodifiable(ranges),
      Markdown(
        markdown: source.toString(),
        blocks: <MD$Block>[MD$Paragraph(text: source.toString(), spans: spans)],
      ),
    );
  }

  /// What a custom emoji with no text of its own copies as: the character the
  /// standard keeps for an object in text.
  static const String _objectReplacement = '\u{FFFC}';

  /// The rendered text of the paragraph.
  final String text;

  /// The characters of each item, in the order of the message.
  final List<TextRange> itemRanges;

  /// The model the facade registers: one paragraph.
  final Markdown markdown;

  /// The index of the item that owns the character at [offset], or null on a
  /// line break or outside the text.
  int? itemAtOffset(int offset) {
    for (var i = 0; i < itemRanges.length; i++) {
      final range = itemRanges[i];
      if (offset >= range.start && offset < range.end) return i;
    }
    return null;
  }
}
