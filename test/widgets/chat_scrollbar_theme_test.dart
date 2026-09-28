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
