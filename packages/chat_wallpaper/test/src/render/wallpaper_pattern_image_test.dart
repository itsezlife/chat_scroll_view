import 'dart:async';
import 'dart:ui' as ui;

import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Portrait artwork, twice as tall as wide, opaque on its left half only.
const _leftHalf = SvgStringLoader('''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="200" viewBox="0 0 100 200">
  <rect x="0" y="0" width="50" height="200" fill="#123456"/>
</svg>''');

Future<ui.Image> _resolve(WidgetTester tester, ImageProvider provider) async {
  final image = await tester.runAsync(() {
    final stream = provider.resolve(ImageConfiguration.empty);
    final landed = Completer<ui.Image>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      landed.complete(info.image);
    });
    stream.addListener(listener);
    return landed.future;
  });
  return image!;
}

void main() {
  group('WallpaperPatternImage', () {
    tearDown(() {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    });

    testWidgets(
      'rasterizes the artwork at its width, keeping the aspect ratio',
      (tester) async {
        final image = await _resolve(
          tester,
          const WallpaperPatternImage(
            slug: 'half',
            artwork: _leftHalf,
            width: 30,
          ),
        );
        addTearDown(image.dispose);

        expect((image.width, image.height), (30, 60));
      },
    );

    testWidgets('carries the pattern in its alpha', (tester) async {
      final image = await _resolve(
        tester,
        const WallpaperPatternImage(
          slug: 'half',
          artwork: _leftHalf,
          width: 30,
        ),
      );
      addTearDown(image.dispose);
      final bytes = (await tester.runAsync(image.toByteData))!;

      int alphaAt(int x, int y) =>
          bytes.getUint8((y * image.width + x) * 4 + 3);
      expect(alphaAt(5, 30), 0xFF);
      expect(alphaAt(25, 30), 0);
    });

    testWidgets('shares one raster per slug and width', (tester) async {
      const provider = WallpaperPatternImage(
        slug: 'half',
        artwork: _leftHalf,
        width: 30,
      );
      const sameSlugAndWidth = WallpaperPatternImage(
        slug: 'half',
        artwork: _leftHalf,
        width: 30,
      );
      const otherWidth = WallpaperPatternImage(
        slug: 'half',
        artwork: _leftHalf,
        width: 40,
      );
      const otherSlug = WallpaperPatternImage(
        slug: 'other',
        artwork: _leftHalf,
        width: 30,
      );

      ImageStreamCompleter? completerOf(ImageProvider provider) =>
          provider.resolve(ImageConfiguration.empty).completer;

      expect(sameSlugAndWidth, provider);
      expect(completerOf(sameSlugAndWidth), same(completerOf(provider)));
      expect(completerOf(otherWidth), isNot(same(completerOf(provider))));
      expect(completerOf(otherSlug), isNot(same(completerOf(provider))));

      // Let the rasterizations started above finish before the cache clears.
      for (final provider in [provider, otherWidth, otherSlug]) {
        (await _resolve(tester, provider)).dispose();
      }
    });
  });
}
