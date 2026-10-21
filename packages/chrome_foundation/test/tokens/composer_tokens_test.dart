import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('maps the light palette to the Telegram-derived composer colours', () {
      final tokens = ComposerTokens.fromPalette(const ChromePalette.light());
      expect(tokens.background, const Color(0xFFFFFFFF));
      expect(tokens.text, const Color(0xFF000000));
      expect(tokens.contentFade, const Color(0xFFFFFFFF));
      expect(tokens.shadow, const Color(0xFF000000));
    });

    test('follows the palette: reply accents use the accent role', () {
      final palette = const ChromePalette.dark().copyWith(
        accent: const Color(0xFFFF00FF),
      );
      final tokens = ComposerTokens.fromPalette(palette);
      expect(tokens.cursor, const Color(0xFFFF00FF));
      expect(tokens.replyLine, const Color(0xFFFF00FF));
      expect(tokens.replyName, const Color(0xFFFF00FF));
    });
  });

  group('copyWith', () {
    test('overrides one field and keeps the rest', () {
      final base = ComposerTokens.fromPalette(const ChromePalette.light());
      final next = base.copyWith(cursor: const Color(0xFF123456));
      expect(next.cursor, const Color(0xFF123456));
      expect(next.background, base.background);
      expect(next.copyWith(cursor: base.cursor), base);
    });
  });

  group('lerp', () {
    final a = ComposerTokens.fromPalette(const ChromePalette.light());
    final b = ComposerTokens.fromPalette(const ChromePalette.dark());

    test('returns the endpoints at 0 and 1', () {
      expect(ComposerTokens.lerp(a, b, 0), a);
      expect(ComposerTokens.lerp(a, b, 1), b);
    });

    test('blends every field halfway', () {
      final mid = ComposerTokens.lerp(a, b, 0.5);
      expect(mid.background, Color.lerp(a.background, b.background, 0.5));
      expect(mid.replyText, Color.lerp(a.replyText, b.replyText, 0.5));
    });
  });

  test('equality is by value', () {
    final a = ComposerTokens.fromPalette(const ChromePalette.light());
    final b = ComposerTokens.fromPalette(const ChromePalette.light());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(ComposerTokens.fromPalette(const ChromePalette.dark())));
  });
}
