import 'package:chat_scroll_view_example/src/features/chat/widgets/unread_separator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _label = 'Непрочитанные сообщения';
const _width = 400.0;

Widget _harness({
  UnreadSeparatorColors? colors,
  Brightness brightness = Brightness.light,
  double width = _width,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness, extensions: [?colors]),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: const UnreadSeparator()),
        ),
      ),
    ),
  ),
);

final Finder _arrow = find.byIcon(Icons.keyboard_arrow_down);

Finder _coloredBox(Color color) => find.byWidgetPredicate(
  (widget) => widget is ColoredBox && widget.color == color,
);

void main() {
  group('UnreadSeparator geometry', () {
    testWidgets('fixed 40 cell, full width', (tester) async {
      await tester.pumpWidget(_harness());

      final cell = tester.getRect(find.byType(UnreadSeparator));
      expect(cell.size, const Size(_width, 40));
    });

    testWidgets('strip: 26 fill + 1 shade line at top 7', (tester) async {
      await tester.pumpWidget(_harness());

      final cell = tester.getRect(find.byType(UnreadSeparator));
      final fill = tester.getRect(_coloredBox(const Color(0xF5FFFFFF)));
      final shade = tester.getRect(_coloredBox(const Color(0x140C202C)));

      expect(fill.top - cell.top, 7);
      expect(fill.height, 26);
      expect(fill.width, _width);
      expect(shade.top, fill.bottom);
      expect(shade.height, 1);
      expect(shade.width, _width);
    });

    testWidgets('arrow: 24 Material chevron, glyph 10 from the right', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());

      final cell = tester.getRect(find.byType(UnreadSeparator));
      final arrow = tester.getRect(_arrow);

      expect(arrow.size, const Size.square(24));
      // The chevron glyph ends 6 inside its 24 box.
      expect(cell.right - (arrow.right - 6), 10);
      // Strip top 7 + (27 − (24 + 2 top pad)) / 2 + 2 top pad.
      expect(arrow.top - cell.top, 9.5);
    });

    testWidgets('label: centered above a 1px bottom pad', (tester) async {
      await tester.pumpWidget(_harness());

      final cell = tester.getRect(find.byType(UnreadSeparator));
      final label = tester.getRect(find.text(_label));

      expect(label.center.dx, closeTo(cell.center.dx, 0.01));
      expect(label.center.dy - cell.top, closeTo(19.5, 0.01));
    });

    testWidgets('large text scale does not grow the row or the label', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      final unscaled = tester.getSize(find.text(_label));

      await tester.pumpWidget(_harness(textScaler: const TextScaler.linear(3)));

      expect(tester.getSize(find.byType(UnreadSeparator)).height, 40);
      expect(tester.getSize(find.text(_label)), unscaled);
    });

    testWidgets('narrow width keeps one line and the 40 cell', (tester) async {
      await tester.pumpWidget(_harness());
      final lineHeight = tester.getSize(find.text(_label)).height;

      await tester.pumpWidget(_harness(width: 120));

      expect(tester.getSize(find.byType(UnreadSeparator)).height, 40);
      expect(tester.getSize(find.text(_label)).height, lineHeight);
      expect(tester.takeException(), isNull);
    });
  });

  group('UnreadSeparator label style', () {
    testWidgets('14, medium, no ambient spacing or line height', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());

      final style = tester.widget<Text>(find.text(_label)).style!;
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.letterSpacing, isNull);
      expect(style.height, isNull);
      expect(style.inherit, isFalse);
    });
  });

  group('UnreadSeparator colors', () {
    testWidgets('light theme, no extension: light palette', (tester) async {
      await tester.pumpWidget(_harness());

      final text = tester.widget<Text>(find.text(_label));
      final arrow = tester.widget<Icon>(_arrow);
      expect(text.style!.color, const Color(0xFF5695CC));
      expect(arrow.color, const Color(0xFFA2B5C7));
      expect(_coloredBox(const Color(0xF5FFFFFF)), findsOneWidget);
      expect(_coloredBox(const Color(0x140C202C)), findsOneWidget);
    });

    testWidgets('dark theme, no extension: dark palette', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.dark));

      final text = tester.widget<Text>(find.text(_label));
      expect(text.style!.color, UnreadSeparatorColors.dark.text);
      expect(_coloredBox(const Color(0xF5212122)), findsOneWidget);
    });

    testWidgets('registered extension wins over brightness', (tester) async {
      await tester.pumpWidget(_harness(colors: UnreadSeparatorColors.dark));

      final text = tester.widget<Text>(find.text(_label));
      final arrow = tester.widget<Icon>(_arrow);
      expect(text.style!.color, const Color(0xDAFFFFFF));
      expect(arrow.color, const Color(0xFF6D6D6F));
      expect(_coloredBox(const Color(0xF5212122)), findsOneWidget);

      final shade = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(UnreadSeparator),
              matching: find.byType(ColoredBox),
            ),
          )
          .map((box) => box.color)
          .singleWhere((color) => color.a < 0.5);
      // Shade rgb(12, 32, 44) @ α20 multiplied by 0xFF212122.
      expect(shade.a, closeTo(20 / 255, 1e-6));
      expect(shade.r, closeTo(12 / 255 * 0x21 / 255, 1e-6));
      expect(shade.g, closeTo(32 / 255 * 0x21 / 255, 1e-6));
      expect(shade.b, closeTo(44 / 255 * 0x22 / 255, 1e-6));
    });

    test('lerp blends every role', () {
      const light = UnreadSeparatorColors.light;
      const dark = UnreadSeparatorColors.dark;
      final mid = light.lerp(dark, 0.5);
      expect(mid.background, Color.lerp(light.background, dark.background, .5));
      expect(mid.text, Color.lerp(light.text, dark.text, .5));
      expect(mid.arrow, Color.lerp(light.arrow, dark.arrow, .5));
    });
  });
}
