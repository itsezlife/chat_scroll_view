/// The Russian plural category a counted noun takes, shared by the demo's
/// chrome strings and its bulletins.
///
/// **Seam:** [RussianPlural] directly; pure.
library;

import 'package:chat_scroll_view_example/src/common/utils/russian_plural.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one for 1, 21, 101, not for 11 or 111', () {
    for (final n in [1, 21, 31, 101, 1001]) {
      expect(RussianPlural.of(n), RussianPlural.one, reason: '$n');
    }
    expect(RussianPlural.of(11), RussianPlural.many);
    expect(RussianPlural.of(111), RussianPlural.many);
  });

  test('few for 2 to 4 and 22 to 24, not for 12 to 14', () {
    for (final n in [2, 3, 4, 22, 23, 24, 102]) {
      expect(RussianPlural.of(n), RussianPlural.few, reason: '$n');
    }
    for (final n in [12, 13, 14, 112]) {
      expect(RussianPlural.of(n), RussianPlural.many, reason: '$n');
    }
  });

  test('many for zero and 5 to 20', () {
    for (final n in [0, 5, 10, 15, 20, 25, 100]) {
      expect(RussianPlural.of(n), RussianPlural.many, reason: '$n');
    }
  });

  test('picks the word of its category', () {
    String stickers(int n) =>
        RussianPlural.wordOf(n, 'стикер', 'стикера', 'стикеров');
    expect(stickers(1), 'стикер');
    expect(stickers(3), 'стикера');
    expect(stickers(5), 'стикеров');
    expect(stickers(21), 'стикер');
  });
}
