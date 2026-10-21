import 'dart:ui';

import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_flow.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_text.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_text_layout.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = ContentKey.unicode('\u{1F44D}');

/// What the selection surface of an emoji-only body answers from the item
/// squares: which edge a point is nearest, where a caret is, what a range
/// covers.
///
/// **Seam:** `ChatEmojiTextLayout`, pure geometry over `ChatEmojiText` and
/// the squares of `ChatEmojiFlow`.
void main() {
  // Boxes of 10 with a gap of 2, two items to a line (maxWidth 22), five
  // items: lines [0 1] [2 3] [4]. Item i is `2 * i` characters in.
  ChatEmojiTextLayout layout({
    List<int> breaks = const [0, 0, 0, 0, 0],
    double maxWidth = 22,
    TextDirection direction = TextDirection.ltr,
    List<ContentKey> keys = const [_a, _a, _a, _a, _a],
  }) {
    final flow = ChatEmojiFlow.of(
      lineBreaksBefore: breaks,
      box: 10,
      maxWidth: maxWidth,
      direction: direction,
      skip: 2,
    );
    return ChatEmojiTextLayout(
      text: ChatEmojiText.of(
        EmojiOnly([
          for (final (i, key) in keys.indexed)
            EmojiOnlyItem(key, lineBreaksBefore: breaks[i]),
        ]),
      ),
      items: flow.rects,
      direction: direction,
    );
  }

  group('a point resolves to the nearest item edge', () {
    test('the leading half of an item is its start, downstream', () {
      final hit = layout().hitAt(const Offset(14, 5));

      expect(hit, (offset: 2, affinity: TextAffinity.downstream));
    });

    test('the trailing half is its end, upstream', () {
      final hit = layout().hitAt(const Offset(20, 5));

      expect(hit, (offset: 4, affinity: TextAffinity.upstream));
    });

    test('past the end of a line is the end of its last item', () {
      final hit = layout().hitAt(const Offset(80, 5));

      expect(hit, (offset: 4, affinity: TextAffinity.upstream));
    });

    test('before the start of a line is the start of its first item', () {
      final hit = layout().hitAt(const Offset(-30, 15));

      expect(hit, (offset: 4, affinity: TextAffinity.downstream));
    });

    test('above and below the lines are the first and the last line', () {
      expect(layout().hitAt(const Offset(1, -40))?.offset, 0);
      expect(layout().hitAt(const Offset(80, 400))?.offset, 10);
    });

    test('right to left, the leading half is the right one', () {
      // Width 22: item 0 at 12..22, item 1 at 0..10.
      final l = layout(direction: TextDirection.rtl);

      expect(l.hitAt(const Offset(20, 5))?.offset, 0);
      expect(l.hitAt(const Offset(14, 5))?.offset, 2);
      expect(l.hitAt(const Offset(1, 5))?.offset, 4);
    });
  });

  group('words', () {
    test('an emoji is a word of its own: the item under a point', () {
      expect(layout().itemAt(const Offset(14, 5)), 1);
    });

    test('a point between two items takes the nearer one', () {
      expect(layout().itemAt(const Offset(10.5, 5)), 0);
      expect(layout().itemAt(const Offset(11.5, 5)), 1);
    });

    test('a point past the end of a line takes its last item', () {
      expect(layout().itemAt(const Offset(90, 5)), 1);
    });

    test('glyph ink is the squares, not the gap or the empty line end', () {
      final l = layout();

      expect(l.hitsItem(const Offset(5, 5)), isTrue);
      expect(l.hitsItem(const Offset(11, 5)), isFalse);
      expect(l.hitsItem(const Offset(50, 5)), isFalse);
    });
  });

  group('carets', () {
    test('an item edge is the leading or trailing side of its square', () {
      final l = layout();

      expect(
        l.caretRect(2, TextAffinity.downstream),
        const Rect.fromLTWH(12, 0, 0, 10),
      );
      expect(
        l.caretRect(4, TextAffinity.upstream),
        const Rect.fromLTWH(22, 0, 0, 10),
      );
    });

    test('at a wrap the affinity picks the end of one line or the next', () {
      // The line [0 1] ends where [2 3] starts, at offset 4.
      final l = layout();

      expect(l.caretRect(4, TextAffinity.downstream)?.top, 10);
      expect(l.caretRect(4, TextAffinity.upstream)?.top, 0);
    });

    test('inside a break the caret is the start of the next line', () {
      final l = layout(breaks: const [0, 0, 2, 0, 0]);

      // Text: [0 1] \n\n [2 3] [4]: offset 5 is between the two breaks, and
      // the blank line leaves item 2 on the third line.
      expect(l.caretRect(5, TextAffinity.downstream)?.top, 20);
    });

    test('right to left the leading edge is the right one', () {
      final l = layout(direction: TextDirection.rtl);

      expect(l.caretRect(0, TextAffinity.downstream)?.left, 22);
    });
  });

  group('ranges', () {
    test('the items a range covers are boxes of their own', () {
      final boxes = layout().boxesForRange(2, 6);

      expect(boxes, [
        const Rect.fromLTWH(12, 0, 10, 10),
        const Rect.fromLTWH(0, 10, 10, 10),
      ]);
    });

    test('a collapsed range covers nothing', () {
      expect(layout().boxesForRange(4, 4), isEmpty);
    });

    test('an item is in a range only by being reached', () {
      // [3, 5) reaches into items 1 and 2.
      expect(layout().boxesForRange(3, 5), hasLength(2));
    });

    test('a line is one joined box of the selected items', () {
      final lines = layout().lineBoxesForRange(1, 10);

      expect(lines, [
        const Rect.fromLTWH(0, 0, 22, 10),
        const Rect.fromLTWH(0, 10, 22, 10),
        const Rect.fromLTWH(0, 20, 10, 10),
      ]);
    });

    test('a partial first line joins from the first selected item', () {
      final lines = layout().lineBoxesForRange(2, 6);

      expect(lines, [
        const Rect.fromLTWH(12, 0, 10, 10),
        const Rect.fromLTWH(0, 10, 10, 10),
      ]);
    });
  });
}
