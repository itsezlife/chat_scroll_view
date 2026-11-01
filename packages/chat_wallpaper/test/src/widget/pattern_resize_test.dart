import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:chat_wallpaper/chat_wallpaper_diagnostics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pattern_harness.dart';

const _wallpaper = ChatWallpaper.patterned(
  ChatWallpaper$Solid(Color(0xFF40A060)),
  WallpaperPattern(
    patternSlug,
    intensity: 100,
    blend: WallpaperPatternBlend.mask,
  ),
);

/// A portrait phone display, 1200 × 2000 physical pixels.
const _display = Size(1200, 2000);

Widget _window(Size size, {double devicePixelRatio = 1}) => patternsHost(
  const ChatWallpaperView(wallpaper: _wallpaper),
  size: size,
  devicePixelRatio: devicePixelRatio,
);

void main() {
  setUp(ChatWallpaperDiagnostics.reset);
  tearDown(clearImageCache);

  testWidgets('rasterizes the artwork at the shorter side of the display', (
    tester,
  ) async {
    tester.view.display.size = _display;
    addTearDown(tester.view.display.reset);

    await tester.pumpWidget(_window(const Size(800, 600)));
    await settle(tester, () => composited(tester));

    expect(
      PaintingBinding.instance.imageCache.containsKey(
        const WallpaperPatternImage(
          slug: patternSlug,
          artwork: leftHalf,
          width: 1200,
        ),
      ),
      isTrue,
    );
    expect(ChatWallpaperDiagnostics.patternRasterizations, 1);
  });

  testWidgets(
    'keeps the pattern through a window resize without rasterizing it again',
    (tester) async {
      tester.view.display.size = _display;
      addTearDown(tester.view.display.reset);

      await tester.pumpWidget(_window(const Size(800, 600)));
      await settle(tester, () => composited(tester));
      ChatWallpaperDiagnostics.reset();

      // A desktop window dragged narrower and shorter, a step per frame,
      // then a phone turned to landscape and back.
      for (final size in const [
        Size(780, 590),
        Size(700, 520),
        Size(520, 400),
        Size(400, 800),
        Size(800, 400),
      ]) {
        await tester.pumpWidget(_window(size));
        expect(composited(tester), isTrue, reason: 'pattern dropped at $size');
      }
      await deliver(tester, steps: 10);

      expect(composited(tester), isTrue);
      expect(ChatWallpaperDiagnostics.patternRasterizations, 0);
    },
  );
}
