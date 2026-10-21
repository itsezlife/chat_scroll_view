import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_flow.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatEmojiFlow flow(
    List<int> breaks, {
    double box = 10,
    double maxWidth = 1000,
    TextDirection direction = TextDirection.ltr,
    double inset = 0,
    double skip = 0,
  }) => ChatEmojiFlow.of(
    lineBreaksBefore: breaks,
    box: box,
    maxWidth: maxWidth,
    direction: direction,
    inset: inset,
    skip: skip,
  );

  test('items sit side by side and the box shrinks to them', () {
    final result = flow([0, 0, 0]);

    expect(result.size, const Size(30, 10));
    expect(result.rects, [
      const Rect.fromLTWH(0, 0, 10, 10),
      const Rect.fromLTWH(10, 0, 10, 10),
      const Rect.fromLTWH(20, 0, 10, 10),
    ]);
  });

  test('a run wraps at the maximum width, at least one item to a line', () {
    final result = flow([0, 0, 0, 0, 0], maxWidth: 25);

    expect(result.size, const Size(20, 30));
    expect(result.rects[2], const Rect.fromLTWH(0, 10, 10, 10));
    expect(result.rects[4], const Rect.fromLTWH(0, 20, 10, 10));
    expect(flow([0, 0], maxWidth: 3).size, const Size(10, 20));
  });

  test('an item that exactly fills the width stays on the line', () {
    expect(flow([0, 0, 0], maxWidth: 30).size, const Size(30, 10));
  });

  test('a line break starts a line, two leave a blank one', () {
    final result = flow([0, 1, 2]);

    expect(result.rects[1], const Rect.fromLTWH(0, 10, 10, 10));
    expect(result.rects[2], const Rect.fromLTWH(0, 30, 10, 10));
    expect(result.size, const Size(10, 40));
  });

  test('right to left starts at the right edge of the widest line', () {
    final result = flow([0, 0, 0, 1], direction: TextDirection.rtl);

    expect(result.size, const Size(30, 20));
    expect(result.rects[0], const Rect.fromLTWH(20, 0, 10, 10));
    expect(result.rects[2], const Rect.fromLTWH(0, 0, 10, 10));
    expect(result.rects[3], const Rect.fromLTWH(20, 10, 10, 10));
  });

  test('an inset surrounds the items', () {
    final result = flow([0], box: 100, inset: 10);

    expect(result.size, const Size(120, 120));
    expect(result.rects.single, const Rect.fromLTWH(10, 10, 100, 100));
  });

  test('an unbounded width never wraps', () {
    final result = flow([0, 0, 0, 0], maxWidth: double.infinity);

    expect(result.size, const Size(40, 10));
  });

  test('which item lies under a point', () {
    final result = flow([0, 0, 1]);

    expect(result.itemAt(const Offset(15, 5)), 1);
    expect(result.itemAt(const Offset(5, 15)), 2);
    expect(result.itemAt(const Offset(25, 15)), isNull);
  });

  group('the gap between items', () {
    test('a skip sits between the items of a line, not at its ends', () {
      final result = flow([0, 0, 0], skip: 2);

      expect(result.size, const Size(34, 10));
      expect(result.rects[1], const Rect.fromLTWH(12, 0, 10, 10));
      expect(result.rects[2], const Rect.fromLTWH(24, 0, 10, 10));
    });

    test('it counts toward the wrap', () {
      // 10 + 2 + 10 = 22 fits in 22; a third item would need 34.
      final result = flow([0, 0, 0], skip: 2, maxWidth: 22);

      expect(result.size, const Size(22, 20));
    });

    test('right to left keeps the gap between items', () {
      final result = flow([0, 0], skip: 2, direction: TextDirection.rtl);

      expect(result.rects[0], const Rect.fromLTWH(12, 0, 10, 10));
      expect(result.rects[1], const Rect.fromLTWH(0, 0, 10, 10));
    });
  });

  group('where the items are, for a host that places chrome', () {
    test('content is the items without the inset', () {
      final result = flow([0, 0, 1], inset: 10);

      expect(result.content, const Rect.fromLTWH(10, 10, 20, 20));
    });

    test('the last line is the items of the last line', () {
      final result = flow([0, 0, 1]);

      expect(result.lastLine, const Rect.fromLTWH(0, 10, 10, 10));
    });

    test('the last line of one line is the line', () {
      expect(flow([0, 0, 0]).lastLine, const Rect.fromLTWH(0, 0, 30, 10));
    });

    test('right to left, the last line hangs at the right edge', () {
      final result = flow([0, 0, 0, 1], direction: TextDirection.rtl);

      expect(result.lastLine, const Rect.fromLTWH(20, 10, 10, 10));
    });

    test('a blank last line is not a thing: breaks precede an item', () {
      final result = flow([0, 2]);

      expect(result.lastLine, const Rect.fromLTWH(0, 20, 10, 10));
    });
  });
}
