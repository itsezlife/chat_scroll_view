import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

// Regenerate with `flutter test --update-goldens test/goldens`.
//
// The shell is drawn on the flat path: solid fills and token colours, no
// glass or blur, which `chrome_foundation` has not introduced yet. flutter_test
// renders text with the Ahem font, so glyph shapes do not depend on the host
// platform; icons come from the Material icon font of the test bundle.
//
// The goldens were generated on macOS. Pixel-exact comparison on another
// platform (CI runs Linux) is unconfirmed: if edge anti-aliasing of the
// rounded shapes differs there, regenerate on the pinned platform or add a
// tolerance comparator, and record it here.
void main() {
  final variants = {
    'light_ltr': (Brightness.light, TextDirection.ltr),
    'dark_ltr': (Brightness.dark, TextDirection.ltr),
    'light_rtl': (Brightness.light, TextDirection.rtl),
    'dark_rtl': (Brightness.dark, TextDirection.rtl),
  };

  for (final searchOpen in [true, false]) {
    for (final MapEntry(key: variant, value: (brightness, direction))
        in variants.entries) {
      final name = '${searchOpen ? 'search_open' : 'search_closed'}_$variant';
      testWidgets('shell with two pages, $name', (tester) async {
        final emoji = FakePanelPage(
          'emoji',
          search: true,
          actions: const [PageAction.backspace()],
          color: brightness == Brightness.light
              ? const Color(0xFFE8F0F8)
              : const Color(0xFF1E2A36),
        );
        final stickers = FakePanelPage('stickers');
        final controller = PanelShellController(
          pages: [emoji.page, stickers.page],
          preferences: FakePreferenceStore(),
        );
        addTearDown(controller.dispose);

        await tester.binding.setSurfaceSize(const Size(360, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          PanelShellTestScope(
            textDirection: direction,
            brightness: brightness,
            size: const Size(360, 400),
            // The cursor blinks; a golden must not catch it mid-blink.
            speed: ChromeMotionSpeed.instant,
            child: RepaintBoundary(
              key: const ValueKey('shell'),
              child: PanelShell(
                controller: controller,
                announcer: FakePanelAnnouncer(),
              ),
            ),
          ),
        );
        if (searchOpen) {
          controller
            ..openSearch(focus: false)
            ..setQuery('cat');
        }
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(const ValueKey('shell')),
          matchesGoldenFile('../goldens/panel_shell_$name.png'),
        );
      });
    }
  }
}
