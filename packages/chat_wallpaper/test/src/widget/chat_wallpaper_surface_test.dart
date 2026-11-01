import 'dart:typed_data';

import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../motion/keyframes_harness.dart';

/// Square artwork, opaque on its left half only: cover-fit into the 800 × 600
/// test view, the view's left half lies inside the pattern.
const _leftHalf = SvgStringLoader('''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <rect x="0" y="0" width="50" height="100" fill="#FF0000"/>
</svg>''');

const _slug = 'half';
const _fill = ChatWallpaper$Freeform(
  Color(0xFFD7EDE6),
  Color(0xFF7FBFAE),
  Color(0xFFEAF2CC),
  Color(0xFF2D4836),
);
const _fallback = Color(0xFFFF00FF);
const _pillSize = Size(40, 20);

final _shot = GlobalKey();

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(800, 600)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: ChatWallpaperPatterns(
      artwork: const {_slug: _leftHalf},
      child: RepaintBoundary(key: _shot, child: child),
    ),
  ),
);

Widget _surface(
  ChatWallpaper wallpaper, {
  required List<Widget> pills,
  bool darkTheme = false,
  ChatWallpaperMotionController? motion,
}) => _host(
  ChatWallpaperSurface(
    wallpaper: wallpaper,
    darkTheme: darkTheme,
    motion: motion,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ChatWallpaperView(wallpaper: wallpaper, motion: motion),
        ...pills,
      ],
    ),
  ),
);

/// A pill centred on [centre] of the surface.
Widget _pill(
  Offset centre, {
  double fillOpacity = 1,
  WallpaperServiceShade? shade,
  Widget child = const SizedBox.expand(),
}) => Positioned(
  left: centre.dx - _pillSize.width / 2,
  top: centre.dy - _pillSize.height / 2,
  width: _pillSize.width,
  height: _pillSize.height,
  child: _Fill(fillOpacity: fillOpacity, shade: shade, child: child),
);

class _Fill extends StatelessWidget {
  const _Fill({
    required this.fillOpacity,
    required this.shade,
    required this.child,
  });

  final double fillOpacity;
  final WallpaperServiceShade? shade;
  final Widget child;

  @override
  Widget build(BuildContext context) => WallpaperServiceFill(
    borderRadius: BorderRadius.zero,
    fallback: const BoxDecoration(color: _fallback),
    fillOpacity: fillOpacity,
    shade: shade,
    child: child,
  );
}

/// Delivers async rasterizing until [done], for at most [steps] rounds.
Future<void> _deliver(
  WidgetTester tester, {
  bool Function()? done,
  int steps = 20,
}) async {
  for (var step = 0; step < steps && !(done?.call() ?? false); step++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

bool _rasterized() => find.byType(RawImage).evaluate().isNotEmpty;

/// Pixels of [boundary] at [points], one logical pixel each.
Future<List<Color>> _pixelsOf(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
  List<Offset> points,
) async {
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return (await image.toByteData())!;
    } finally {
      image.dispose();
    }
  });
  Color at(Offset point) {
    final offset =
        (point.dy.toInt() * boundary.size.width.toInt() + point.dx.toInt()) * 4;
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

/// Pixels of the whole surface, pills included.
Future<List<Color>> _screen(WidgetTester tester, List<Offset> points) =>
    _pixelsOf(
      tester,
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot)),
      points,
    );

/// Pixels of the wallpaper alone: the view paints in its own boundary.
Future<List<Color>> _wallpaper(WidgetTester tester, List<Offset> points) =>
    _pixelsOf(
      tester,
      tester.renderObject<RenderRepaintBoundary>(
        find
            .descendant(
              of: find.byType(ChatWallpaperView),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      ),
      points,
    );

/// Matches [expected] channel by channel within 2, opaque.
Matcher _near(Color expected) => isA<Color>()
    .having((c) => (c.a * 255).round(), 'alpha', 0xFF)
    .having(
      (c) => (c.r * 255).round(),
      'red',
      closeTo((expected.r * 255).round(), 2),
    )
    .having(
      (c) => (c.g * 255).round(),
      'green',
      closeTo((expected.g * 255).round(), 2),
    )
    .having(
      (c) => (c.b * 255).round(),
      'blue',
      closeTo((expected.b * 255).round(), 2),
    );

void main() {
  group('WallpaperServiceFill', () {
    tearDown(() {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    });

    const top = Offset(200, 100);
    const bottom = Offset(600, 500);

    /// The unpatterned fill's pixels at [points], as the shade's input.
    Future<List<Color>> gradientAt(
      WidgetTester tester,
      List<Offset> points,
    ) async {
      await tester.pumpWidget(_surface(_fill, pills: const []));
      await _deliver(tester, done: _rasterized);
      return _wallpaper(tester, points);
    }

    for (final (label, wallpaper, darkTheme) in [
      ('each of several fills', _fill as ChatWallpaper, false),
      (
        'never a soft-light pattern in a light theme',
        const ChatWallpaper.patterned(_fill, WallpaperPattern(_slug)),
        false,
      ),
      (
        'never a mask in a dark theme',
        const ChatWallpaper.patterned(
          _fill,
          WallpaperPattern(
            _slug,
            intensity: 100,
            blend: WallpaperPatternBlend.mask,
          ),
        ),
        true,
      ),
    ]) {
      testWidgets('fills with the shaded gradient behind it, $label', (
        tester,
      ) async {
        final gradient = await gradientAt(tester, [top, bottom]);
        final shade = WallpaperServiceShade.of(
          wallpaper,
          darkTheme: darkTheme,
        )!;

        await tester.pumpWidget(
          _surface(
            wallpaper,
            darkTheme: darkTheme,
            pills: [_pill(top), _pill(bottom)],
          ),
        );
        await _deliver(tester);

        expect(await _screen(tester, [top, bottom]), [
          _near(shade.apply(gradient[0])),
          _near(shade.apply(gradient[1])),
        ]);
      });
    }

    testWidgets('stays opaque against the edge the gradient is cover-fit to', (
      tester,
    ) async {
      // Cover-fit into 800 × 600, the gradient's left edge is the surface's.
      const points = [Offset(2, 300), Offset(6, 300), Offset(12, 300)];
      final gradient = await gradientAt(tester, points);
      final shade = WallpaperServiceShade.of(_fill, darkTheme: true)!;

      await tester.pumpWidget(
        _surface(_fill, darkTheme: true, pills: [_pill(const Offset(21, 300))]),
      );
      await _deliver(tester);

      expect(await _screen(tester, points), [
        for (final color in gradient) _near(shade.apply(color)),
      ]);
    });

    testWidgets('square fills meeting off the pixel grid leave no seam', (
      tester,
    ) async {
      // The boundary at y = 110.5 splits pixel row 110 between the two fills.
      const seam = Offset(200, 110);
      final [gradient] = await gradientAt(tester, [seam]);
      final shade = WallpaperServiceShade.of(_fill, darkTheme: false)!;
      Widget band(double top) => Positioned(
        left: 180,
        top: top,
        width: 40,
        height: 10.5,
        child: const _Fill(
          fillOpacity: 1,
          shade: null,
          child: SizedBox.expand(),
        ),
      );

      await tester.pumpWidget(_surface(_fill, pills: [band(100), band(110.5)]));
      await _deliver(tester);

      expect(await _screen(tester, [seam]), [_near(shade.apply(gradient))]);
    });

    testWidgets(
      'snaps a square fill to physical pixels, so abutting layers share their edge',
      (tester) async {
        await tester.pumpWidget(
          _surface(
            _fill,
            pills: [
              Positioned(
                left: 180,
                top: 100.3,
                width: 40,
                height: 10.1,
                child: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(devicePixelRatio: 2),
                    child: const _Fill(
                      fillOpacity: 1,
                      shade: null,
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        await _deliver(tester);

        // Physical edges 200.6 and 420.8 round to 201 and 421: 100.5 and 210.5
        // logical, 0.2 and 10.2 in the band's own coordinates.
        expect(
          tester.renderObject(find.byType(WallpaperServiceFill)),
          paints..something((method, arguments) {
            if (method != #drawRect) return false;
            expect(
              arguments.first,
              rectMoreOrLessEquals(const Rect.fromLTRB(0, 0.2, 40, 10.2)),
            );
            return true;
          }),
        );
      },
    );

    testWidgets('repaints where it moved when no ancestor repaints', (
      tester,
    ) async {
      final [from, to] = await gradientAt(tester, [top, bottom]);
      expect(
        from,
        isNot(_near(to)),
        reason: 'the two points must differ for the test to mean anything',
      );
      final shade = WallpaperServiceShade.of(_fill, darkTheme: false)!;

      Widget at(Offset shift) => _surface(
        _fill,
        pills: [
          Positioned.fill(
            child: Transform.translate(
              offset: shift,
              child: RepaintBoundary(child: Stack(children: [_pill(top)])),
            ),
          ),
        ],
      );
      await tester.pumpWidget(at(Offset.zero));
      await _deliver(tester);
      expect(await _screen(tester, [top]), [_near(shade.apply(from))]);

      await tester.pumpWidget(at(bottom - top));
      await tester.pump();

      expect(await _screen(tester, [bottom]), [_near(shade.apply(to))]);
    });

    testWidgets('follows the wallpaper motion', (tester) async {
      final motion = ChatWallpaperMotionController(vsync: const TestVSync());
      addTearDown(motion.dispose);
      final shade = WallpaperServiceShade.of(_fill, darkTheme: false)!;

      await tester.pumpWidget(
        _surface(_fill, motion: motion, pills: [_pill(top)]),
      );
      await _deliver(tester, done: _rasterized);
      // With the whole ring held nothing lands while the screen is read back.
      // The last landing may run after its round's frame, so one more pump
      // paints it before the readback.
      await _deliver(tester, done: () => holdsRing(motion, _fill), steps: 300);
      expect(
        holdsRing(motion, _fill),
        isTrue,
        reason: 'keyframes did not land',
      );
      await tester.pump();
      final [before] = await _screen(tester, [top]);
      expect(
        before,
        _near(shade.apply((await _wallpaper(tester, [top])).single)),
      );

      expect(motion.advance(), isTrue);
      await _deliver(tester, steps: 5);
      await tester.pumpAndSettle();
      await _deliver(tester, steps: 3);
      expect(motion.isAnimating, isFalse);

      final [after] = await _screen(tester, [top]);
      expect(after, isNot(_near(before)));
      expect(
        after,
        _near(shade.apply((await _wallpaper(tester, [top])).single)),
      );
    });

    testWidgets('fills through its own shade instead of the surface one', (
      tester,
    ) async {
      const own = WallpaperServiceShade(
        saturation: 3.5,
        scale: 0.75,
        offset: 0,
        luminance: WallpaperServiceShade.linearLuminance,
      );
      final gradient = await gradientAt(tester, [top, bottom]);

      await tester.pumpWidget(
        _surface(
          _fill,
          pills: [
            _pill(top, shade: own),
            _pill(bottom),
          ],
        ),
      );
      await _deliver(tester);

      final surfaceShade = WallpaperServiceShade.of(_fill, darkTheme: false)!;
      expect(await _screen(tester, [top, bottom]), [
        _near(own.apply(gradient[0])),
        _near(surfaceShade.apply(gradient[1])),
      ]);
    });

    testWidgets(
      'paints its fallback, not its own shade, over a wallpaper without a freeform fill',
      (tester) async {
        const own = WallpaperServiceShade(
          saturation: 3.5,
          scale: 0.75,
          offset: 0,
        );

        await tester.pumpWidget(
          _surface(
            const ChatWallpaper$Solid(Color(0xFF808080)),
            pills: [_pill(top, shade: own)],
          ),
        );

        expect(await _screen(tester, [top]), [_fallback]);
      },
    );

    testWidgets(
      'paints its fallback over a wallpaper without a freeform fill',
      (tester) async {
        await tester.pumpWidget(
          _surface(
            const ChatWallpaper$Solid(Color(0xFF808080)),
            pills: [_pill(top)],
          ),
        );

        expect(await _screen(tester, [top]), [_fallback]);
      },
    );

    testWidgets('paints its fallback outside a surface', (tester) async {
      await tester.pumpWidget(
        _host(Stack(fit: StackFit.expand, children: [_pill(top)])),
      );

      expect(await _screen(tester, [top]), [_fallback]);
    });

    testWidgets(
      'switches to its fallback when the wallpaper loses its freeform fill',
      (tester) async {
        await tester.pumpWidget(_surface(_fill, pills: [_pill(top)]));
        await _deliver(tester);
        expect(await _screen(tester, [top]), isNot([_fallback]));

        await tester.pumpWidget(
          _surface(
            const ChatWallpaper$Solid(Color(0xFF808080)),
            pills: [_pill(top)],
          ),
        );

        expect(await _screen(tester, [top]), [_fallback]);
      },
    );

    testWidgets(
      'reports whether it lends a gradient, rebuilding dependents when that changes',
      (tester) async {
        final reported = <bool>[];
        final probe = Builder(
          builder: (context) {
            reported.add(WallpaperServiceFill.lendsGradient(context));
            return const SizedBox.shrink();
          },
        );

        await tester.pumpWidget(_host(probe));
        await tester.pumpWidget(_surface(_fill, pills: [probe]));
        await tester.pumpWidget(
          _surface(
            const ChatWallpaper$Solid(Color(0xFF808080)),
            pills: [probe],
          ),
        );

        expect(reported, [false, true, false]);
      },
    );

    group('at a partial fill opacity', () {
      const opacity = 0.5;
      const grey = ChatWallpaper$Solid(Color(0xFF808080));

      /// [fill] drawn at [opacity] over [behind].
      Color over(Color behind, Color fill) =>
          Color.alphaBlend(fill.withValues(alpha: opacity), behind);

      // Impeller ignores a layer paint's alpha beside an image filter. The
      // Skia renderer CI runs passes either way, so CI won't catch a
      // regression: run it with --enable-impeller.
      testWidgets(
        'blends the shaded gradient over the wallpaper by that fraction',
        (tester) async {
          const wallpaper = ChatWallpaper.patterned(
            _fill,
            WallpaperPattern(_slug),
          );
          final gradient = await gradientAt(tester, [top, bottom]);
          final shade = WallpaperServiceShade.of(wallpaper, darkTheme: false)!;

          await tester.pumpWidget(
            _surface(
              wallpaper,
              pills: [
                _pill(top, fillOpacity: opacity),
                _pill(bottom, fillOpacity: opacity),
              ],
            ),
          );
          await _deliver(tester);
          await tester.pump(ChatWallpaperView.patternFadeDuration);
          final behind = await _wallpaper(tester, [top, bottom]);
          expect(
            behind.first,
            isNot(_near(gradient.first)),
            reason: 'the pattern must show behind the top pill',
          );

          expect(await _screen(tester, [top, bottom]), [
            _near(over(behind[0], shade.apply(gradient[0]))),
            _near(over(behind[1], shade.apply(gradient[1]))),
          ]);
        },
      );

      testWidgets(
        'blends its solid colour by that fraction before the first keyframe lands',
        (tester) async {
          final shade = WallpaperServiceShade.of(_fill, darkTheme: false)!;

          await tester.pumpWidget(
            _surface(_fill, pills: [_pill(top, fillOpacity: opacity)]),
          );
          expect(
            _rasterized(),
            isFalse,
            reason: 'the view must still paint its average colour',
          );

          expect(await _screen(tester, [top]), [
            _near(over(_fill.averageColor, shade.apply(_fill.averageColor))),
          ]);
        },
      );

      testWidgets('blends its fallback over the wallpaper by that fraction', (
        tester,
      ) async {
        await tester.pumpWidget(
          _surface(grey, pills: [_pill(top, fillOpacity: opacity)]),
        );

        expect(await _screen(tester, [top]), [
          _near(over(grey.color, _fallback)),
        ]);
      });

      for (final (label, wallpaper) in [
        ('over the shaded gradient', _fill as ChatWallpaper),
        ('over its fallback', grey),
      ]) {
        testWidgets('keeps the content inside it opaque, $label', (
          tester,
        ) async {
          const content = Color(0xFF00FF00);

          await tester.pumpWidget(
            _surface(
              wallpaper,
              pills: [
                _pill(
                  top,
                  fillOpacity: opacity,
                  child: const ColoredBox(color: content),
                ),
              ],
            ),
          );
          await _deliver(tester);

          expect(await _screen(tester, [top]), [content]);
        });
      }
    });
  });
}
