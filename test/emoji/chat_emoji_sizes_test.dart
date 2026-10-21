import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Android's tables, written out as literals: the expected values come from
// `Theme.java:8602-8606` (steps) and `MessageObject.java:2114-2148` (by count),
// not from the code under test.
const _allCustom = <int, double>{
  1: 81.6,
  2: 81.6,
  3: 55.2,
  4: 40.8,
  5: 33.6,
  6: 26.4,
  7: 22.8,
  8: 22.8,
  9: 22.8,
  10: 22.8,
};
const _mixed = <int, double>{
  1: 40.8,
  2: 40.8,
  3: 33.6,
  4: 26.4,
  5: 22.8,
  6: 22.8,
  7: 22.8,
  8: 22.8,
  9: 22.8,
  10: 22.8,
};

void main() {
  const sizes = ChatEmojiSizes();

  group('font step by count', () {
    for (var count = 1; count <= 10; count++) {
      test('$count items: all custom ${_allCustom[count]}, otherwise '
          '${_mixed[count]}', () {
        expect(
          sizes.fontSizeFor(count, allCustom: true),
          closeTo(_allCustom[count]!, 1e-9),
        );
        expect(
          sizes.fontSizeFor(count, allCustom: false),
          closeTo(_mixed[count]!, 1e-9),
        );
      });
    }

    test('a count of 200 takes the smallest step', () {
      expect(sizes.fontSizeFor(200, allCustom: true), 22.8);
      expect(sizes.fontSizeFor(200, allCustom: false), 22.8);
    });
  });

  test('an item box is its font plus 4 dp', () {
    expect(sizes.itemBoxFor(1, allCustom: true), closeTo(85.6, 1e-9));
    expect(sizes.itemBoxFor(3, allCustom: false), closeTo(37.6, 1e-9));
    expect(sizes.itemBoxFor(10, allCustom: false), closeTo(26.8, 1e-9));
  });

  group('sticker', () {
    test('a 360 x 640 viewport gives 112.5 dp', () {
      expect(sizes.stickerExtentFor(const Size(360, 640)), 112.5);
    });

    test('a landscape viewport is measured by its short side', () {
      expect(sizes.stickerExtentFor(const Size(640, 360)), 112.5);
    });

    test('a zoom of 0.5 shrinks it to 90 dp', () {
      expect(
        const ChatEmojiSizes(
          stickerZoom: 0.5,
        ).stickerExtentFor(const Size(360, 640)),
        90,
      );
    });
  });

  test('a host overrides the tables', () {
    const custom = ChatEmojiSizes(
      fontSteps: [60, 30],
      allCustomSteps: [0, 0, 0, 1, 1, 1, 1],
      mixedSteps: [1, 1, 1, 1, 1, 1, 1],
    );

    expect(custom.fontSizeFor(2, allCustom: true), 60);
    expect(custom.fontSizeFor(4, allCustom: true), 30);
    expect(custom.fontSizeFor(1, allCustom: false), 30);
  });

  test('equal tables are equal values', () {
    expect(const ChatEmojiSizes(), const ChatEmojiSizes());
    expect(const ChatEmojiSizes().hashCode, const ChatEmojiSizes().hashCode);
    expect(
      const ChatEmojiSizes(stickerZoom: 0.5),
      isNot(const ChatEmojiSizes()),
    );
  });
}
