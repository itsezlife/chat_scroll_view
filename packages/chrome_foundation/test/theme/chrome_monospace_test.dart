import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChromeMonospace', () {
    test('names a system face where the CSS generic does not resolve', () {
      expect(ChromeMonospace.familyFor(TargetPlatform.iOS), 'Menlo');
      expect(ChromeMonospace.familyFor(TargetPlatform.macOS), 'Menlo');
      expect(ChromeMonospace.familyFor(TargetPlatform.windows), 'Consolas');
    });

    test('keeps the generic where the platform resolves it', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
      ]) {
        expect(ChromeMonospace.familyFor(platform), 'monospace');
      }
    });

    test('the fallback chain ends in the generic', () {
      expect(ChromeMonospace.fallback.last, 'monospace');
    });

    test('style sets the family and the fallback on top of a base', () {
      const base = TextStyle(fontSize: 13, fontFamily: 'Body');
      final style = ChromeMonospace.style(base, platform: TargetPlatform.iOS);
      expect(style.fontFamily, 'Menlo');
      expect(style.fontFamilyFallback, ChromeMonospace.fallback);
      expect(style.fontSize, 13);
    });

    test('a base in a packaged font does not prefix the monospace face', () {
      // A host's text theme in a bundled font carries its package, and
      // copyWith / merge keep it: 'monospace' would resolve as
      // 'packages/app_ui/monospace', which nobody has, and fall back to the
      // body face on every platform.
      const base = TextStyle(
        fontFamily: 'Body',
        package: 'app_ui',
        fontSize: 13,
        color: Color(0xFF112233),
      );
      for (final platform in TargetPlatform.values) {
        final style = ChromeMonospace.style(base, platform: platform);
        expect(style.fontFamily, ChromeMonospace.familyFor(platform));
        expect(style.fontFamilyFallback, ChromeMonospace.fallback);
        expect(style.fontSize, 13);
        expect(style.color, const Color(0xFF112233));
      }
    });

    test('a style merged on top keeps the monospace face', () {
      const base = TextStyle(fontFamily: 'Body', package: 'app_ui');
      final style = ChromeMonospace.style(
        base,
        platform: TargetPlatform.android,
      ).merge(const TextStyle(fontWeight: FontWeight.bold));
      expect(style.fontFamily, 'monospace');
    });
  });
}
