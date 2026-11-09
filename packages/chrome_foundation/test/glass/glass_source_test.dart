import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/src/glass/glass_source.dart';
import 'package:chrome_foundation/src/glass/glass_style.dart';
import 'package:chrome_foundation/src/glass/strategy/glass_backdrops.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/missing_shaders.dart';

const _style = GlassStyle(
  fill: Color(0xD9202020),
  strokeTop: Color(0x28FFFFFF),
  strokeBottom: Color(0x14FFFFFF),
  shadowColor: Color(0x00000000),
);

const _filtersOnly = GlassCapabilities(
  sampledBackdrop: false,
  shaderFilter: false,
  backdropFilter: true,
);

const _sourceKey = ValueKey('source');
const _glassKey = ValueKey('glass');

Widget _themed(Widget child, {GlassCapabilities? capabilities}) =>
    ChromeThemeScope(
      palette: const ChromePalette.dark(),
      child: GlassQualityScope(
        capabilities: capabilities ?? GlassCapabilities.all,
        child: child,
      ),
    );

Widget _scene() => const GlassSourceScope(
  child: Stack(
    children: [
      Positioned.fill(
        key: _sourceKey,
        child: GlassSource(child: ColoredBox(color: Color(0xFF3366FF))),
      ),
      Center(
        child: SizedBox(
          width: 200,
          height: 44,
          child: GlassSurface(
            key: _glassKey,
            material: GlassMaterial.composerIsland,
            child: SizedBox.expand(),
          ),
        ),
      ),
    ],
  ),
);

Route<void> _route(Widget child) => PageRouteBuilder<void>(
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, animation, secondaryAnimation) => child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(1, 0), end: Offset.zero),
        ),
        child: child,
      ),
);

bool _readsBackdrop(WidgetTester tester) =>
    tester.layers.whereType<BackdropFilterLayer>().isNotEmpty;

bool _drawsGlass() => find
    .descendant(
      of: find.byKey(_glassKey),
      matching: find.byType(SampledGlassBackdrop),
    )
    .evaluate()
    .isNotEmpty;

class _Sampler implements GlassSampler {
  _Sampler(this.region);

  Rect region;

  @override
  Rect? sampleRegion(RenderGlassSource source) => region;

  @override
  double get samplePixelRatio => 0.5;

  @override
  double get sampleBlurSigma => 2;
}

/// The upper and lower halves of an 800 x 600 source, each a repaint
/// boundary of its own, so a change to one leaves the other's layer as it is.
class _Halves {
  final top = ValueNotifier<Color>(const Color(0xFF3366FF));
  final bottom = ValueNotifier<Color>(const Color(0xFF33CC66));
  late GlassSourceLink link;

  static const lower = Rect.fromLTWH(0, 300, 800, 300);

  Widget _half(ValueNotifier<Color> color, {Widget? over}) => Expanded(
    child: RepaintBoundary(
      child: ValueListenableBuilder<Color>(
        valueListenable: color,
        builder: (context, value, _) =>
            ColoredBox(color: value, child: over ?? const SizedBox.expand()),
      ),
    ),
  );

  Future<void> pump(WidgetTester tester, {Widget? overBottom}) =>
      tester.pumpWidget(
        GlassSourceScope(
          child: Builder(
            builder: (context) {
              link = GlassSourceLink.of(context)!;
              return GlassSource(
                child: Column(
                  children: [
                    _half(top),
                    _half(bottom, over: overBottom),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

/// The capture [sampler] draws with in the next frame.
Future<GlassCapture> _nextFrame(
  WidgetTester tester,
  GlassSourceLink link,
  GlassSampler sampler,
) async {
  // A frame even when nothing in the tree is dirty: the link ends its frame
  // in a post-frame callback.
  tester.binding.scheduleFrame();
  await tester.pump();
  return link.captureFor(sampler)!;
}

Future<Uint32List> _argb(WidgetTester tester, ui.Image image) async {
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
  ))!;
  return Uint32List.fromList([
    for (var i = 0; i < bytes.lengthInBytes; i += 4)
      bytes.getUint8(i + 3) << 24 |
          bytes.getUint8(i) << 16 |
          bytes.getUint8(i + 1) << 8 |
          bytes.getUint8(i + 2),
  ]);
}

void main() {
  group('GlassSourceLink.mergeRegions', () {
    test('merges regions whose bounds stay cheap', () {
      const composer = Rect.fromLTWH(0, 700, 400, 100);
      const button = Rect.fromLTWH(340, 630, 60, 60);

      expect(GlassSourceLink.mergeRegions([composer, button]), [
        composer.expandToInclude(button),
      ]);
    });

    test('keeps distant regions apart', () {
      const top = Rect.fromLTWH(0, 0, 400, 60);
      const bottom = Rect.fromLTWH(0, 740, 400, 60);

      expect(GlassSourceLink.mergeRegions([top, bottom]), [top, bottom]);
    });
  });

  group('GlassSourceLink', () {
    late GlassSourceLink link;

    Future<void> pumpScope(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: GlassSourceScope(
          child: Builder(
            builder: (context) {
              link = GlassSourceLink.of(context)!;
              return const GlassSource(
                child: ColoredBox(color: Color(0xFF3366FF)),
              );
            },
          ),
        ),
      ),
    );

    testGlassWidgets('shares one capture between nearby samplers', (
      tester,
    ) async {
      await pumpScope(tester);
      final composer = _Sampler(const Rect.fromLTWH(0, 500, 400, 100));
      final button = _Sampler(const Rect.fromLTWH(340, 430, 60, 60));
      link
        ..addSampler(composer)
        ..addSampler(button);

      final a = link.captureFor(composer)!;
      final b = link.captureFor(button)!;

      expect(identical(a.image, b.image), isTrue);
      expect(a.region, composer.region.expandToInclude(button.region));
      await tester.pump();
    });

    testGlassWidgets('captures distant samplers separately', (tester) async {
      await pumpScope(tester);
      final top = _Sampler(const Rect.fromLTWH(0, 0, 400, 60));
      final bottom = _Sampler(const Rect.fromLTWH(0, 500, 400, 60));
      link
        ..addSampler(top)
        ..addSampler(bottom);

      final a = link.captureFor(top)!;
      final b = link.captureFor(bottom)!;

      expect(identical(a.image, b.image), isFalse);
      expect((a.region, b.region), (top.region, bottom.region));
      await tester.pump();
    });
  });

  group('GlassSourceLink reuse', () {
    testGlassWidgets('keeps the capture while nothing under it changed', (
      tester,
    ) async {
      final scene = _Halves();
      await scene.pump(tester);
      final sampler = _Sampler(const Rect.fromLTWH(0, 400, 400, 100));
      scene.link.addSampler(sampler);

      final first = await _nextFrame(tester, scene.link, sampler);
      final second = await _nextFrame(tester, scene.link, sampler);

      expect(second.image, same(first.image));
      expect(first.image.debugDisposed, isFalse);
    });

    testGlassWidgets('recaptures when the content under it changes', (
      tester,
    ) async {
      final scene = _Halves();
      await scene.pump(tester);
      final sampler = _Sampler(const Rect.fromLTWH(0, 400, 400, 100));
      scene.link.addSampler(sampler);
      final first = await _nextFrame(tester, scene.link, sampler);

      scene.bottom.value = const Color(0xFFFF3333);
      final second = await _nextFrame(tester, scene.link, sampler);

      expect(second.image, isNot(same(first.image)));
      await tester.pump();
      expect(first.image.debugDisposed, isTrue);
    });

    testGlassWidgets('keeps the capture when only content beside it changes', (
      tester,
    ) async {
      final scene = _Halves();
      await scene.pump(tester);
      final sampler = _Sampler(const Rect.fromLTWH(0, 400, 400, 100));
      scene.link.addSampler(sampler);
      final first = await _nextFrame(tester, scene.link, sampler);

      scene.top.value = const Color(0xFFFF3333);
      final second = await _nextFrame(tester, scene.link, sampler);

      expect(second.image, same(first.image));
    });

    testGlassWidgets('recaptures when its region moves', (tester) async {
      final scene = _Halves();
      await scene.pump(tester);
      final sampler = _Sampler(const Rect.fromLTWH(0, 400, 400, 100));
      scene.link.addSampler(sampler);
      final first = await _nextFrame(tester, scene.link, sampler);

      sampler.region = const Rect.fromLTWH(0, 410, 400, 100);
      final second = await _nextFrame(tester, scene.link, sampler);

      expect(second.image, isNot(same(first.image)));
      expect(second.region, sampler.region);
    });

    testGlassWidgets('recaptures every frame over a playing texture', (
      tester,
    ) async {
      final scene = _Halves();
      await scene.pump(
        tester,
        overBottom: const Center(
          child: SizedBox.square(dimension: 40, child: Texture(textureId: 7)),
        ),
      );
      final sampler = _Sampler(const Rect.fromLTWH(300, 400, 200, 100));
      scene.link.addSampler(sampler);

      final first = await _nextFrame(tester, scene.link, sampler);
      final second = await _nextFrame(tester, scene.link, sampler);

      expect(second.image, isNot(same(first.image)));
    });

    testGlassWidgets('keeps the capture beside a playing texture', (
      tester,
    ) async {
      final scene = _Halves();
      await scene.pump(
        tester,
        overBottom: const Center(
          child: SizedBox.square(dimension: 40, child: Texture(textureId: 7)),
        ),
      );
      final sampler = _Sampler(const Rect.fromLTWH(0, 300, 200, 60));
      scene.link.addSampler(sampler);

      final first = await _nextFrame(tester, scene.link, sampler);
      final second = await _nextFrame(tester, scene.link, sampler);

      expect(second.image, same(first.image));
    });

    testGlassWidgets('releases the kept capture with its scope', (
      tester,
    ) async {
      final scene = _Halves();
      await scene.pump(tester);
      final sampler = _Sampler(_Halves.lower);
      scene.link.addSampler(sampler);
      final capture = await _nextFrame(tester, scene.link, sampler);

      await tester.pumpWidget(const SizedBox());

      expect(capture.image.debugDisposed, isTrue);
    });

    testGlassWidgets('releases a capture no sampler reads any more', (
      tester,
    ) async {
      final scene = _Halves();
      await scene.pump(tester);
      final sampler = _Sampler(_Halves.lower);
      scene.link.addSampler(sampler);
      final capture = await _nextFrame(tester, scene.link, sampler);

      scene.link.removeSampler(sampler);
      await tester.pump();

      expect(capture.image.debugDisposed, isTrue);
    });
  });

  group('GlassSource', () {
    testGlassWidgets('renders only what lies in the region', (tester) async {
      await tester.pumpWidget(
        const GlassSourceScope(
          child: GlassSource(
            child: Row(
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ColoredBox(color: Color(0xFFFF0000))),
                Expanded(child: ColoredBox(color: Color(0xFF0000FF))),
              ],
            ),
          ),
        ),
      );
      final source = tester.renderObject<RenderGlassSource>(
        find.byType(GlassSource),
      );

      // The region starts where the red half ends: blurred, its edge would
      // take red from beyond it; culled to the region it stays blue.
      final image = source.capture(
        const Rect.fromLTWH(400, 0, 100, 100),
        pixelRatio: 1,
        blurSigma: 4,
      )!;
      addTearDown(image.dispose);
      final pixels = await _argb(tester, image);

      expect(pixels[50 * 100], 0xFF0000FF);
    });

    testGlassWidgets('captures a region at the requested scale', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: _themed(_scene())));

      final source = tester.renderObject<RenderGlassSource>(
        find.byType(GlassSource),
      );
      final image = source.capture(
        const Rect.fromLTWH(10, 20, 100, 50),
        pixelRatio: 0.5,
        blurSigma: 2,
      )!;
      addTearDown(image.dispose);

      expect((image.width, image.height), (50, 25));
    });

    testGlassWidgets('frosts without reading back the frame', (tester) async {
      await tester.pumpWidget(MaterialApp(home: _themed(_scene())));

      expect(_drawsGlass(), isTrue);
      expect(_readsBackdrop(tester), isFalse);
    });

    testGlassWidgets('keeps the glass on while its route moves', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => _themed(child!),
          home: const SizedBox(),
        ),
      );
      navigator.currentState!.push(_route(_scene())).ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_drawsGlass(), isTrue);
      expect(_readsBackdrop(tester), isFalse);
    });

    testGlassWidgets(
      'an ancestor clip and transform apply to the captured glass',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: GlassSourceScope(
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: GlassSource(
                      child: ColoredBox(color: Color(0xFF3366FF)),
                    ),
                  ),
                  Builder(
                    builder: (context) => Center(
                      child: Transform.scale(
                        scale: 0.9,
                        child: ClipOval(
                          child: SizedBox.square(
                            dimension: 44,
                            child: SampledGlassBackdrop(
                              link: GlassSourceLink.of(context)!,
                              style: _style,
                              programs: null,
                              pixelRatio: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final glass = tester.layers.singleWhere(
          (layer) => '${layer.runtimeType}' == '_CapturedGlassLayer',
        );
        final ancestors = <Type>[
          for (Layer? layer = glass.parent; layer != null; layer = layer.parent)
            layer.runtimeType,
        ];
        expect(ancestors, containsAllInOrder([ClipPathLayer, TransformLayer]));
      },
    );

    testGlassWidgets('filters the scene when the backend cannot capture', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: _themed(_scene(), capabilities: _filtersOnly)),
      );

      expect(_readsBackdrop(tester), isTrue);
    });
  });
}
