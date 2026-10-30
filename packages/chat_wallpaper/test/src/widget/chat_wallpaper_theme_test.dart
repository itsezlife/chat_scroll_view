import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _sage = ChatWallpaper.freeform(
  Color(0xFFDBDDBB),
  Color(0xFF6BA587),
  Color(0xFFD5D88D),
  Color(0xFF88B884),
);
const _deepGreen = ChatWallpaper.freeform(
  Color(0xFF2D4836),
  Color(0xFF172B19),
  Color(0xFF364331),
  Color(0xFF103231),
);

void main() {
  group('ChatWallpaperTheme', () {
    testWidgets('of and maybeOf return the scoped wallpaper', (tester) async {
      late ChatWallpaper found;
      ChatWallpaper? maybeFound;

      await tester.pumpWidget(
        ChatWallpaperTheme(
          wallpaper: _sage,
          child: Builder(
            builder: (context) {
              found = ChatWallpaperTheme.of(context);
              maybeFound = ChatWallpaperTheme.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(found, _sage);
      expect(maybeFound, _sage);
    });

    testWidgets('maybeOf returns null without a scope', (tester) async {
      ChatWallpaper? found = _sage;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            found = ChatWallpaperTheme.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(found, isNull);
    });

    testWidgets('of throws without a scope', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            ChatWallpaperTheme.of(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(tester.takeException(), isFlutterError);
    });

    testWidgets('notifies dependents only when the value changes', (
      tester,
    ) async {
      var builds = 0;
      final dependent = Builder(
        builder: (context) {
          ChatWallpaperTheme.of(context);
          builds++;
          return const SizedBox.shrink();
        },
      );

      await tester.pumpWidget(
        ChatWallpaperTheme(wallpaper: _sage, child: dependent),
      );
      expect(builds, 1);

      await tester.pumpWidget(
        ChatWallpaperTheme(
          // Non-const: equal by value, not identical.
          wallpaper: ChatWallpaper.freeform(
            const Color(0xFFDBDDBB),
            const Color(0xFF6BA587),
            const Color(0xFFD5D88D),
            Color(int.parse('FF88B884', radix: 16)),
          ),
          child: dependent,
        ),
      );
      expect(builds, 1);

      await tester.pumpWidget(
        ChatWallpaperTheme(wallpaper: _deepGreen, child: dependent),
      );
      expect(builds, 2);
    });
  });
}
