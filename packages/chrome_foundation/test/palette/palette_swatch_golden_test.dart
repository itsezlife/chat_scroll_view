import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/palette_swatch.dart';

// Regenerate with `flutter test --update-goldens test/palette`. The swatch is
// solid rectangles on whole pixels with no text, so the pinned platform
// (macOS and Linux CI render it identically) needs no tolerance.
void main() {
  // Goldens sit next to this file, also when test/unit_test.dart runs it.
  setUpAll(
    () => goldenFileComparator = LocalFileComparator(
      Uri.file('test/palette/palette_swatch_golden_test.dart'),
    ),
  );
  final palettes = {
    'light': const ChromePalette.light(),
    'dark': const ChromePalette.dark(),
    'high_contrast_light': const ChromePalette.highContrastLight(),
    'high_contrast_dark': const ChromePalette.highContrastDark(),
  };
  for (final MapEntry(key: name, value: palette) in palettes.entries) {
    testWidgets('$name palette swatch', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('swatch'),
          child: Align(
            alignment: Alignment.topLeft,
            child: PaletteSwatch(palette),
          ),
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('swatch')),
        matchesGoldenFile('../goldens/palette_$name.png'),
      );
    });
  }
}
