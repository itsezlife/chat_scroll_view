import 'dart:typed_data';

import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:chat_wallpaper/chat_wallpaper_diagnostics.dart';
import 'package:chat_wallpaper/src/widget/patterned_fill.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pattern_harness.dart';

const _inside = Offset(200, 300);
const _outside = Offset(600, 300);

/// Square artwork with an opaque centre square a fifth of its side, so a
/// cropped box keeps transparent pattern along all four edges.
const _centre = SvgStringLoader('''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <rect x="40" y="40" width="20" height="20" fill="#FF0000"/>
</svg>''');

Widget _host(
  ChatWallpaper wallpaper, {
  Map<String, BytesLoader> artwork = const {patternSlug: leftHalf},
  double devicePixelRatio = 1,
}) => patternsHost(
  ChatWallpaperView(wallpaper: wallpaper),
  artwork: artwork,
  devicePixelRatio: devicePixelRatio,
);

ChatWallpaper _patterned(
  ChatWallpaper$ColorFill fill,
  int intensity,
  WallpaperPatternBlend blend,
) => ChatWallpaper.patterned(
  fill,
  WallpaperPattern(patternSlug, intensity: intensity, blend: blend),
);

/// Reads the pixels of the view's boundary, or of the [boundary] a finder
/// names, at [points] (logical coordinates, one pixel each).
Future<List<Color>> _pixels(
  WidgetTester tester,
  List<Offset> points, {
  Finder? boundary,
}) async {
  final layer = tester.renderObject<RenderRepaintBoundary>(
    boundary ??
        find
            .descendant(
              of: find.byType(ChatWallpaperView),
              matching: find.byType(RepaintBoundary),
            )
            .first,
  );
  final bytes = await tester.runAsync(() async {
    final image = await layer.toImage();
    try {
      return (await image.toByteData())!;
    } finally {
      image.dispose();
    }
  });
  Color at(Offset point) {
    final offset =
        (point.dy.toInt() * layer.size.width.toInt() + point.dx.toInt()) * 4;
    final ByteData(:getUint8) = bytes!;
    return Color.fromARGB(
      getUint8(offset + 3),
      getUint8(offset),
      getUint8(offset + 1),
      getUint8(offset + 2),
    );
  }

  return [for (final point in points) at(point)];
}

/// Delivers the raster, then runs the late-pattern fade to its end.
Future<void> _shown(WidgetTester tester) async {
  await settle(tester, () => composited(tester));
  await tester.pump(ChatWallpaperView.patternFadeDuration);
}

/// Matches an opaque grey whose channels are within 2 of [value].
Matcher _grey(int value) => _rgb(value, value, value);

/// Matches an opaque colour whose channels are within 2 of the given ones.
Matcher _rgb(int red, int green, int blue) => isA<Color>()
    .having((c) => (c.a * 255).round(), 'alpha', 0xFF)
    .having((c) => (c.r * 255).round(), 'red', closeTo(red, 2))
    .having((c) => (c.g * 255).round(), 'green', closeTo(green, 2))
    .having((c) => (c.b * 255).round(), 'blue', closeTo(blue, 2));

void main() {
  group('ChatWallpaperView patterns', () {
    setUp(pinDisplay);
    tearDown(clearImageCache);
    tearDown(resetDisplay);

    group('soft light', () {
      // W3C soft light of a black source over grey 0x80 gives 0x40; of a
      // white source over grey 0x30, 0x6F. Intensity mixes towards the fill.
      testWidgets('darkens a light fill with black inside the pattern only', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            _patterned(
              const ChatWallpaper$Solid(Color(0xFF808080)),
              100,
              WallpaperPatternBlend.softLight,
            ),
          ),
        );
        await _shown(tester);

        expect(await _pixels(tester, [_inside, _outside]), [
          _grey(0x40),
          _grey(0x80),
        ]);
      });

      testWidgets('lightens a dark fill with white', (tester) async {
        await tester.pumpWidget(
          _host(
            _patterned(
              const ChatWallpaper$Solid(Color(0xFF303030)),
              100,
              WallpaperPatternBlend.softLight,
            ),
          ),
        );
        await _shown(tester);

        expect(await _pixels(tester, [_inside, _outside]), [
          _grey(0x6F),
          _grey(0x30),
        ]);
      });

      testWidgets('draws at the pattern intensity', (tester) async {
        await tester.pumpWidget(
          _host(
            _patterned(
              const ChatWallpaper$Solid(Color(0xFF808080)),
              50,
              WallpaperPatternBlend.softLight,
            ),
          ),
        );
        await _shown(tester);

        expect(await _pixels(tester, [_inside]), [_grey(0x60)]);
      });
    });

    group('mask', () {
      testWidgets('shows the fill through the pattern on black', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            _patterned(
              const ChatWallpaper$Solid(Color(0xFF40A060)),
              100,
              WallpaperPatternBlend.mask,
            ),
          ),
        );
        await _shown(tester);

        expect(await _pixels(tester, [_inside, _outside]), [
          _rgb(0x40, 0xA0, 0x60),
          _grey(0),
        ]);
      });

      testWidgets('draws at the pattern intensity', (tester) async {
        await tester.pumpWidget(
          _host(
            _patterned(
              const ChatWallpaper$Solid(Color(0xFF40A060)),
              50,
              WallpaperPatternBlend.mask,
            ),
          ),
        );
        await _shown(tester);

        expect(await _pixels(tester, [_inside, _outside]), [
          _rgb(0x20, 0x50, 0x30),
          _grey(0),
        ]);
      });

      testWidgets('covers exactly the fill on edges between pixels', (
        tester,
      ) async {
        // The 300 × 200 box spans x and y from 4.5, so its outermost pixels
        // are half covered. Transparent pattern along every edge must black
        // out the fill there too, and nothing past the box.
        const magenta = Color(0xFFFF00FF);
        const host = ValueKey('host');
        await tester.pumpWidget(
          patternsHost(
            RepaintBoundary(
              key: host,
              child: ColoredBox(
                color: magenta,
                child: Stack(
                  children: [
                    Positioned(
                      left: 4.5,
                      top: 4.5,
                      width: 300,
                      height: 200,
                      child: ChatWallpaperView(
                        wallpaper: _patterned(
                          const ChatWallpaper$Solid(Color(0xFF40A060)),
                          100,
                          WallpaperPatternBlend.mask,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            artwork: const {patternSlug: _centre},
          ),
        );
        await _shown(tester);

        final halfBlack = _rgb(0x80, 0, 0x80);
        expect(
          await _pixels(tester, boundary: find.byKey(host), [
            for (final y in const [3.0, 4.0, 204.0, 205.0]) Offset(20, y),
            for (final x in const [3.0, 4.0, 304.0, 305.0]) Offset(x, 20),
          ]),
          [
            ...[_rgb(0xFF, 0, 0xFF), halfBlack, halfBlack, _rgb(0xFF, 0, 0xFF)],
            ...[_rgb(0xFF, 0, 0xFF), halfBlack, halfBlack, _rgb(0xFF, 0, 0xFF)],
          ],
        );
      });
    });

    testWidgets(
      'paints the fill alone when no artwork is registered for the slug',
      (tester) async {
        await tester.pumpWidget(
          _host(
            _patterned(
              const ChatWallpaper$Solid(Color(0xFF40A060)),
              100,
              WallpaperPatternBlend.mask,
            ),
            artwork: const {},
          ),
        );
        await deliver(tester, steps: 5);

        expect(composited(tester), isFalse);
        expect(await _pixels(tester, [_inside, _outside]), [
          _rgb(0x40, 0xA0, 0x60),
          _rgb(0x40, 0xA0, 0x60),
        ]);
      },
    );

    testWidgets(
      'crops rather than shrinks the pattern in a box smaller than the window',
      (tester) async {
        // In the 200 × 100 box the raster of [_centre] keeps the 800-px width
        // it covers the 800 × 600 window at, so its square spans x 20…180;
        // cover-fit into the box would shrink it to x 80…120.
        await tester.pumpWidget(
          patternsHost(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                height: 100,
                child: ChatWallpaperView(
                  wallpaper: _patterned(
                    const ChatWallpaper$Solid(Color(0xFF40A060)),
                    100,
                    WallpaperPatternBlend.mask,
                  ),
                ),
              ),
            ),
            artwork: const {patternSlug: _centre},
          ),
        );
        await _shown(tester);

        expect(
          await _pixels(tester, [const Offset(50, 50), const Offset(195, 50)]),
          [_rgb(0x40, 0xA0, 0x60), _grey(0)],
        );
      },
    );

    testWidgets('resolves the new artwork when the slug changes in place', (
      tester,
    ) async {
      const artwork = {patternSlug: leftHalf, 'other': leftHalf};
      Widget fill(String slug) => patternsHost(
        PatternedFill(
          pattern: WallpaperPattern(slug),
          darkFill: false,
          fadeDuration: ChatWallpaperView.patternFadeDuration,
          fill: const ChatWallpaper$Solid(Color(0xFF808080)),
          child: const ColoredBox(color: Color(0xFF808080)),
        ),
        artwork: artwork,
      );
      await tester.pumpWidget(fill(patternSlug));
      await settle(tester, () => composited(tester));

      await tester.pumpWidget(fill('other'));
      await settle(tester, () => composited(tester));

      expect(
        PaintingBinding.instance.imageCache.containsKey(
          const WallpaperPatternImage(
            slug: 'other',
            artwork: leftHalf,
            width: 600,
          ),
        ),
        isTrue,
      );
    });

    group('over a freeform fill', () {
      const sage = ChatWallpaper$Freeform(
        Color(0xFFDBDDBB),
        Color(0xFF6BA587),
        Color(0xFFD5D88D),
        Color(0xFF88B884),
      );

      testWidgets('rasterizes the fill no more when the pattern lands', (
        tester,
      ) async {
        final wallpaper = _patterned(sage, 50, WallpaperPatternBlend.softLight);
        await tester.pumpWidget(_host(wallpaper, artwork: const {}));
        await settle(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
        await deliver(tester, steps: 3);
        final rasters = ChatWallpaperDiagnostics.gradientRasters;

        await tester.pumpWidget(_host(wallpaper));
        await settle(tester, () => composited(tester));

        expect(ChatWallpaperDiagnostics.gradientRasters, rasters);
      });

      testWidgets('repaints a new intensity in place, without a crossfade', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(_patterned(sage, 50, WallpaperPatternBlend.softLight)),
        );
        await settle(tester, () => composited(tester));
        await deliver(tester, steps: 3);
        await tester.pump(ChatWallpaperView.patternFadeDuration);
        final rasters = ChatWallpaperDiagnostics.gradientRasters;
        final [before] = await _pixels(tester, [_inside]);

        await tester.pumpWidget(
          _host(_patterned(sage, 100, WallpaperPatternBlend.softLight)),
        );

        expect(
          find.byType(PatternedFill),
          findsOneWidget,
          reason: 'a crossfade would hold two fills',
        );
        expect(ChatWallpaperDiagnostics.gradientRasters, rasters);
        final [after] = await _pixels(tester, [_inside]);
        expect(after.computeLuminance(), lessThan(before.computeLuminance()));
      });
    });

    group('fade', () {
      const grey = ChatWallpaper$Solid(Color(0xFF808080));
      const green = ChatWallpaper$Solid(Color(0xFF40A060));
      final halfFade = ChatWallpaperView.patternFadeDuration ~/ 2;

      testWidgets('fades in a soft-light raster that lands late', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(_patterned(grey, 100, WallpaperPatternBlend.softLight)),
        );
        await settle(tester, () => composited(tester));
        expect(await _pixels(tester, [_inside]), [
          _grey(0x80),
        ], reason: 'starts transparent');

        await tester.pump(halfFade);
        final [halfway] = await _pixels(tester, [_inside]);
        expect((halfway.r * 255).round(), inExclusiveRange(0x42, 0x7E));

        await tester.pump(halfFade);
        expect(await _pixels(tester, [_inside]), [_grey(0x40)]);
      });

      testWidgets('fades in a mask that lands late from the bare fill', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(_patterned(green, 100, WallpaperPatternBlend.mask)),
        );
        await settle(tester, () => composited(tester));
        expect(await _pixels(tester, [_inside, _outside]), [
          _rgb(0x40, 0xA0, 0x60),
          _rgb(0x40, 0xA0, 0x60),
        ]);

        await tester.pump(halfFade);
        final [_, halfway] = await _pixels(tester, [_inside, _outside]);
        expect((halfway.g * 255).round(), inExclusiveRange(0x02, 0x9E));

        await tester.pump(halfFade);
        expect(await _pixels(tester, [_inside, _outside]), [
          _rgb(0x40, 0xA0, 0x60),
          _grey(0),
        ]);
      });

      testWidgets(
        'paints a cached raster at full strength on its first frame',
        (tester) async {
          final wallpaper = _patterned(
            grey,
            100,
            WallpaperPatternBlend.softLight,
          );
          await tester.pumpWidget(_host(wallpaper));
          await settle(tester, () => composited(tester));

          await tester.pumpWidget(
            patternsHost(
              ChatWallpaperView(
                key: const ValueKey('fresh'),
                wallpaper: wallpaper,
              ),
            ),
          );

          expect(await _pixels(tester, [_inside, _outside]), [
            _grey(0x40),
            _grey(0x80),
          ]);
        },
      );

      testWidgets(
        'shows a late raster at full strength when animations are disabled',
        (tester) async {
          await tester.pumpWidget(
            patternsHost(
              ChatWallpaperView(
                wallpaper: _patterned(green, 100, WallpaperPatternBlend.mask),
              ),
              disableAnimations: true,
            ),
          );
          await settle(tester, () => composited(tester));

          expect(await _pixels(tester, [_inside, _outside]), [
            _rgb(0x40, 0xA0, 0x60),
            _grey(0),
          ]);
        },
      );

      testWidgets(
        'applies an intensity change mid-fade without restarting it',
        (tester) async {
          await tester.pumpWidget(
            _host(_patterned(grey, 100, WallpaperPatternBlend.softLight)),
          );
          await settle(tester, () => composited(tester));
          await tester.pump(halfFade);

          await tester.pumpWidget(
            _host(_patterned(grey, 50, WallpaperPatternBlend.softLight)),
          );
          await tester.pump(halfFade);

          expect(await _pixels(tester, [_inside]), [_grey(0x60)]);
        },
      );
    });
  });
}
