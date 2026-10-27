import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_text.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart' show TextRange;
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

const _thumbs = ContentKey.unicode('\u{1F44D}');
const _family = ContentKey.unicode('\u{1F468}‍\u{1F469}‍\u{1F467}');
const _custom = ContentKey.document('5368');

/// The text model an emoji-only body registers with the facade: what the
/// viewport's text selection reads for copy, select-all and word ranges.
///
/// **Seam:** `ChatEmojiText.of` and the markdown model and offsets it holds,
/// read through the markdown library's own selection controller.
void main() {
  ChatEmojiText model(List<EmojiOnlyItem> items) => ChatEmojiText.of(EmojiOnly(items));

  test('the rendered text is the items in order, the breaks as newlines', () {
    final text = model([
      const EmojiOnlyItem(_thumbs),
      const EmojiOnlyItem(_family),
      const EmojiOnlyItem(_custom, lineBreaksBefore: 2, alt: '\u{1F389}'),
    ]);

    expect(text.text, '\u{1F44D}\u{1F468}‍\u{1F469}‍\u{1F467}\n\n\u{1F389}');
    expect(text.markdown.blocks.single.type, 'paragraph');
    expect(markdownBlockRenderedText(text.markdown.blocks.single), text.text);
  });

  test('each item owns the range of its characters', () {
    final text = model([
      const EmojiOnlyItem(_thumbs),
      const EmojiOnlyItem(_family),
      const EmojiOnlyItem(_custom, lineBreaksBefore: 1, alt: '\u{1F389}'),
    ]);

    expect(text.itemRanges, const [
      TextRange(start: 0, end: 2),
      TextRange(start: 2, end: 10),
      TextRange(start: 11, end: 13),
    ]);
  });

  test('a custom emoji without text still has a character to select', () {
    final text = model([const EmojiOnlyItem(_custom)]);

    expect(text.itemRanges.single.isCollapsed, isFalse);
  });

  test('a custom emoji is an image span that names its document', () {
    final text = model([const EmojiOnlyItem(_thumbs), const EmojiOnlyItem(_custom, alt: '\u{1F389}')]);

    final spans = (text.markdown.blocks.single as MD$Paragraph).spans;
    final image = spans.singleWhere((s) => s.style.contains(MD$Style.image));
    expect(image.text, '\u{1F389}');
    expect(image.extra?['src'], _custom.encoded);
  });

  test('copy reads the selected items through the controller', () {
    final text = model([
      const EmojiOnlyItem(_thumbs),
      const EmojiOnlyItem(_family),
      const EmojiOnlyItem(_custom, lineBreaksBefore: 1, alt: '\u{1F389}'),
    ]);
    final controller = MarkdownSelectionController(formatter: MarkdownSelectionFormatter.plain)
      ..putDocument(7, text.markdown);
    addTearDown(controller.dispose);

    controller.selection = const MarkdownSelection(
      base: MarkdownPosition(documentId: 7, blockIndex: 0, offset: 2),
      extent: MarkdownPosition(documentId: 7, blockIndex: 0, offset: 13),
    );

    expect(controller.getText(), '\u{1F468}‍\u{1F469}‍\u{1F467}\n\u{1F389}');
    final blocks = controller.selectedContent().documents.single.blocks;
    expect(blocks.single.renderedRange, const TextRange(start: 2, end: 13));
  });

  test('the item at an offset, and none on a break', () {
    final text = model([const EmojiOnlyItem(_thumbs), const EmojiOnlyItem(_thumbs, lineBreaksBefore: 1)]);

    expect(text.itemAtOffset(0), 0);
    expect(text.itemAtOffset(1), 0);
    expect(text.itemAtOffset(2), isNull);
    expect(text.itemAtOffset(3), 1);
    expect(text.itemAtOffset(5), isNull);
  });
}
