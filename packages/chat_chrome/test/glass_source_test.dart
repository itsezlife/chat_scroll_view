import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TelegramGlassStyle(
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
          child: TelegramGlass(
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

void main() {
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
