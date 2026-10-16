import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

// Regenerate with `flutter test --update-goldens test/goldens`.
//
// The popup is drawn on the flat path: solid fills and token colours, no
// glass. The three heights cover the minimum clamp, the 0.75 ratio and the
// maximum clamp; each is drawn left-to-right and right-to-left, where the
// popup hangs from the opposite edge. flutter_test renders text with the Ahem
// font, so glyph shapes do not depend on the host platform.
//
// The goldens were generated on macOS. Pixel-exact comparison on another
// platform (CI runs Linux) is unconfirmed: if edge anti-aliasing of the
// rounded corners or the shadow differs there, regenerate on the pinned
// platform or add a tolerance comparator, and record it here.
void main() {
  const windowWidth = 640.0;
  const composerHeight = 56.0;
  const sizes = {'min_clamp': 300.0, 'ratio': 600.0, 'max_clamp': 1000.0};

  for (final MapEntry(key: sizeName, value: windowHeight) in sizes.entries) {
    for (final direction in TextDirection.values) {
      final name = 'anchored_popup_${sizeName}_${direction.name}';
      testWidgets('popup in a window ${windowHeight}px tall, $name', (
        tester,
      ) async {
        final size = Size(windowWidth, windowHeight);
        final shell = PanelShellController(
          pages: [
            FakePanelPage(
              'emoji',
              search: true,
              color: const Color(0xFFE8F0F8),
            ).page,
            FakePanelPage('stickers').page,
          ],
          preferences: FakePreferenceStore(),
        );
        final strategy = AnchoredPopupStrategy(
          style: const AnchoredPopupStyle(
            width: 360,
            cornerRadius: 12,
            shadows: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        );
        final controller = PanelPresentationController(
          shell: shell,
          policy: const PanelPresentationPolicy$Desktop(),
          strategies: [strategy],
          window: PanelWindow(width: size.width, height: size.height),
        );
        addTearDown(() {
          controller.dispose();
          shell.dispose();
          strategy.dispose();
        });
        controller.anchor(
          Rect.fromLTWH(
            0,
            size.height - composerHeight,
            size.width,
            composerHeight,
          ),
        );
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          PanelShellTestScope(
            textDirection: direction,
            size: size,
            speed: ChromeMotionSpeed.instant,
            child: RepaintBoundary(
              key: const ValueKey('stage'),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFFFFFFFF)),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: composerHeight,
                    child: ColoredBox(color: Color(0xFFD0D8E0)),
                  ),
                  Positioned.fill(
                    child: PanelPresentationView(controller: controller),
                  ),
                ],
              ),
            ),
          ),
        );
        controller.show();
        await tester.pump();
        await tester.pump();
        expect(controller.state.value, isA<PanelVisibility$Shown>());

        await expectLater(
          find.byKey(const ValueKey('stage')),
          matchesGoldenFile('$name.png'),
        );
      });
    }
  }
}
