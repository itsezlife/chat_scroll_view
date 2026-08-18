import 'package:chat_scroll_view_example/src/widgets/merged_value_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MappedValueNotifier', () {
    test('recomputes when source changes', () {
      final source = ValueNotifier(2);
      final derived = source.map((v) => v + 3);

      expect(derived.value, 5);

      source.value = 4;
      expect(derived.value, 7);

      derived.dispose();
      source.dispose();
    });
  });

  group('MergedValueNotifier.combine', () {
    test('recomputes when either source changes', () {
      final first = ValueNotifier(10);
      final second = ValueNotifier(1);
      final derived = first.combine(second, (a, b) => a + b);

      expect(derived.value, 11);

      first.value = 20;
      expect(derived.value, 21);

      second.value = 5;
      expect(derived.value, 25);

      derived.dispose();
      first.dispose();
      second.dispose();
    });
  });
}
