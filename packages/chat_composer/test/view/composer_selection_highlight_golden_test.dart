import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

import '../support/material_icons.dart';

// Regenerate with `scripts/goldens --update` (baselines are the CI runner's).
// Drawn with the test font. The tolerance is far under the
// composer goldens': a seam in the highlight is one pixel row per line break,
// about a thousandth of the image, and must not pass as anti-aliasing.
const _tolerance = 0.0005;

void main() {
  useGoldenBaselines(
    'test/view/composer_selection_highlight_golden_test.dart',
    tolerance: _tolerance,
  );
  setUpAll(() async {
    await loadMaterialIcons();
  });

  testWidgets(
    'a multi-line selection on desktop is one shape',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 330));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ComposerController(
        text: ComposerTextController(
          initial: RichText('lwfwefewf\nfkwlefwlf\nwf\nwf\nwf\nw', const []),
        ),
      );
      addTearDown(controller.dispose);
      final palette = ChromePalette.forBrightness(Brightness.dark);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            textSelectionTheme: const TextSelectionThemeData(
              selectionColor: Color(0x665588FF),
            ),
          ),
          home: RepaintBoundary(
            key: const ValueKey('golden'),
            child: ChromeThemeScope(
              palette: palette,
              child: ChromeStringsScope(
                strings: ChromeStringsPresets.english,
                child: GlassQualityScope(
                  quality: GlassQuality.flat,
                  child: ColoredBox(
                    color: palette.surfaceDim,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ComposerView(
                        controller: controller,
                        spec: ComposerSpec(),
                        safeAreaBottom: 0,
                        autofocus: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      controller.text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.text.length,
      );
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byKey(const ValueKey('golden')),
        matchesGoldenFile('../goldens/composer_selection_highlight.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
