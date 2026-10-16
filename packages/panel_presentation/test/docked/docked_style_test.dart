import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

void main() {
  group('DockedStyle', () {
    test('is equal by width and separator', () {
      const a = DockedStyle(width: 320, separator: Color(0xFF000000));

      expect(a, const DockedStyle(width: 320, separator: Color(0xFF000000)));
      expect(a.hashCode, a.hashCode);
      expect(a, isNot(const DockedStyle(width: 321)));
      expect(a, isNot(const DockedStyle(width: 320)));
    });

    test('draws no separator by default', () {
      expect(const DockedStyle(width: 320).separator, isNull);
    });

    test('has no width of its own unless the host gives one: the policy\'s '
        'narrowest applies', () {
      expect(const DockedStyle().width, isNull);
      expect(const DockedStyle(), const DockedStyle());
      expect(const DockedStyle(), isNot(const DockedStyle(width: 320)));
    });
  });
}
