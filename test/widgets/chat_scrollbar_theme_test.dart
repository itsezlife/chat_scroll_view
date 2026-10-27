import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatScrollbarThemeData', () {
    test('mergeTheme picks dark preset for dark brightness', () {
      final theme = ChatScrollbarThemeData.mergeTheme(
        ThemeData(brightness: Brightness.dark),
      );
      expect(theme.thumbColor, ChatScrollbarThemeData.dark.thumbColor);
      expect(theme.trackColor, ChatScrollbarThemeData.dark.trackColor);
      expect(
        theme.thumbHoverColor,
        ChatScrollbarThemeData.dark.thumbHoverColor,
      );
      expect(
        theme.trackHoverColor,
        ChatScrollbarThemeData.dark.trackHoverColor,
      );
    });

    test('mergeTheme overrides hover colours over the brightness base', () {
      final theme = ChatScrollbarThemeData.mergeTheme(
        ThemeData(),
        thumbHoverColor: const Color(0xFF0000FF),
        trackHoverColor: const Color(0xFF00FF00),
      );
      expect(theme.thumbHoverColor, const Color(0xFF0000FF));
      expect(theme.trackHoverColor, const Color(0xFF00FF00));
      expect(theme.thumbColor, ChatScrollbarThemeData.light.thumbColor);
    });

    test('hover colours sit between idle and dragging on both bases', () {
      for (final base in const [
        ChatScrollbarThemeData.light,
        ChatScrollbarThemeData.dark,
      ]) {
        expect(base.thumbHoverColor.a, greaterThan(base.thumbColor.a));
        expect(base.thumbHoverColor.a, lessThan(base.thumbDraggingColor.a));
        expect(base.trackHoverColor.a, greaterThan(base.trackColor.a));
      }
    });

    test('copyWith replaces hover colours only when given', () {
      const base = ChatScrollbarThemeData.light;
      final copy = base.copyWith(thumbHoverColor: const Color(0xFF123456));
      expect(copy.thumbHoverColor, const Color(0xFF123456));
      expect(copy.trackHoverColor, base.trackHoverColor);
      expect(copy.thumbColor, base.thumbColor);
    });

    test('lerp interpolates hover colours', () {
      const a = ChatScrollbarThemeData(
        thumbHoverColor: Color(0xFF000000),
        trackHoverColor: Color(0xFF000000),
      );
      const b = ChatScrollbarThemeData(
        thumbHoverColor: Color(0xFFFFFFFF),
        trackHoverColor: Color(0xFFFFFFFF),
      );
      final mid = a.lerp(b, 0.5);
      expect(
        mid.thumbHoverColor,
        Color.lerp(a.thumbHoverColor, b.thumbHoverColor, 0.5),
      );
      expect(
        mid.trackHoverColor,
        Color.lerp(a.trackHoverColor, b.trackHoverColor, 0.5),
      );
    });

    test('lerp interpolates colours', () {
      const a = ChatScrollbarThemeData(
        thumbColor: Color(0xFF000000),
        trackColor: Color(0xFF111111),
      );
      const b = ChatScrollbarThemeData(
        thumbColor: Color(0xFFFFFFFF),
        trackColor: Color(0xFFEEEEEE),
      );
      final mid = a.lerp(b, 0.5);
      expect(mid.thumbColor, isNot(a.thumbColor));
      expect(mid.thumbColor, isNot(b.thumbColor));
      expect(
        mid.trackColor.computeLuminance(),
        greaterThan(a.trackColor.computeLuminance()),
      );
    });

    testWidgets('resolve prefers the ThemeData extension', (tester) async {
      const custom = ChatScrollbarThemeData(trackColor: Color(0xFFFF0000));
      late ChatScrollbarThemeData resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [custom]),
          home: Builder(
            builder: (context) {
              resolved = ChatScrollbarThemeData.resolve(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolved.trackColor, custom.trackColor);
    });
  });
}
