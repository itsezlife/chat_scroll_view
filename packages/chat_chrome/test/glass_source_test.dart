import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = LiquidGlassStyle(
  fill: Color(0xD9202020),
  strokeTop: Color(0x28FFFFFF),
  strokeBottom: Color(0x14FFFFFF),
  shadowColor: Color(0x00000000),
);

const _sourceKey = ValueKey('source');
const _glassKey = ValueKey('glass');

Widget _scene() => GlassSourceScope(
  child: Stack(
    children: [
      const Positioned.fill(
        key: _sourceKey,
        child: GlassSource(child: ColoredBox(color: Color(0xFF3366FF))),
      ),
      const Center(
        child: SizedBox(
          width: 200,
          height: 44,
          child: LiquidGlass(
            key: _glassKey,
            style: _style,
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
    .descendant(of: find.byKey(_glassKey), matching: find.byType(GlassBackdrop))
    .evaluate()
    .isNotEmpty;

class _Sampler implements GlassSampler {
  _Sampler(this.region);

  final Rect region;

  @override
  Rect? sampleRegion(RenderGlassSource source) => region;

  @override
  double get samplePixelRatio => 0.5;

  @override
  double get sampleBlurSigma => 2;
}

void main() {
  group('mergeGlassRegions', () {
    test('merges regions whose bounds stay cheap', () {
      const composer = Rect.fromLTWH(0, 700, 400, 100);
      const button = Rect.fromLTWH(340, 630, 60, 60);

      expect(mergeGlassRegions([composer, button]), [
        composer.expandToInclude(button),
      ]);
    });

    test('keeps distant regions apart', () {
      const top = Rect.fromLTWH(0, 0, 400, 60);
      const bottom = Rect.fromLTWH(0, 740, 400, 60);

      expect(mergeGlassRegions([top, bottom]), [top, bottom]);
    });
  });

  group('GlassSourceLink', () {
    late GlassSourceLink link;

    Future<void> pumpScope(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: GlassSourceScope(
          child: Builder(
            builder: (context) {
              link = GlassSourceScope.maybeOf(context)!;
              return const GlassSource(
                child: ColoredBox(color: Color(0xFF3366FF)),
              );
            },
          ),
        ),
      ),
    );

    testWidgets('shares one capture between nearby samplers', (tester) async {
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

    testWidgets('captures distant samplers separately', (tester) async {
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

  group('GlassSource', () {
    setUp(() => GlassBackdrop.debugCaptureSupported = true);
    tearDown(() => GlassBackdrop.debugCaptureSupported = null);

    testWidgets('captures a region at the requested scale', (tester) async {
      await tester.pumpWidget(MaterialApp(home: _scene()));

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

    testWidgets('frosts without reading back the frame', (tester) async {
      await tester.pumpWidget(MaterialApp(home: _scene()));

      expect(_drawsGlass(), isTrue);
      expect(_readsBackdrop(tester), isFalse);
    });

    testWidgets('keeps the glass on while its route moves', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      navigator.currentState!.push(_route(_scene())).ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_drawsGlass(), isTrue);
      expect(_readsBackdrop(tester), isFalse);
    });

    testWidgets('filters the scene when the backend cannot capture', (
      tester,
    ) async {
      GlassBackdrop.debugCaptureSupported = false;
      await tester.pumpWidget(MaterialApp(home: _scene()));

      expect(_readsBackdrop(tester), isTrue);
    });
  });
}
