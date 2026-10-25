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
  });
}
