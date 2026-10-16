import 'dart:ui';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChromeContrast.ratio', () {
    test('is 21 for black on white, in either order', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      expect(ChromeContrast.ratio(black, white), closeTo(21, 1e-9));
      expect(ChromeContrast.ratio(white, black), closeTo(21, 1e-9));
    });

    test('is 1 for identical opaque colours', () {
      expect(
        ChromeContrast.ratio(const Color(0xFF336699), const Color(0xFF336699)),
        closeTo(1, 1e-9),
      );
    });

    test('matches the published value for #767676 on white', () {
      // WCAG worked example: #767676 is the lightest grey that reaches 4.54.
      expect(
        ChromeContrast.ratio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
        closeTo(4.54, 0.01),
      );
    });

    test('composites a translucent foreground over the background', () {
      // Alpha 0x80 of black over white is #7F7F7F: ratio 4.0 against white.
      expect(
        ChromeContrast.ratio(const Color(0x80000000), const Color(0xFFFFFFFF)),
        closeTo(4.0, 0.01),
      );
    });

    test('composites a translucent background over the backdrop', () {
      expect(
        ChromeContrast.ratio(
          const Color(0xFFFFFFFF),
          const Color(0x80000000),
          backdrop: const Color(0xFFFFFFFF),
        ),
        closeTo(4.0, 0.01),
      );
    });
  });
}
