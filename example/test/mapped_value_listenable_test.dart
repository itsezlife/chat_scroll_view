import 'package:chat_scroll_view_example/src/common/utils/mapped_value_listenable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MappedValueListenable.map()', () {
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
}
