import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the reference client presets', () {
    test('day is the default theme\'s popup colours', () {
      const day = PointerMenuTokens.telegramDay;
      expect(day.background, const Color(0xFFFFFFFF));
      expect(day.backgroundOver, const Color(0xFFF1F1F1));
      expect(day.text, const Color(0xFF000000));
      expect(day.textOver, const Color(0xFF000000));
      expect(day.textDisabled, const Color(0xFFCCCCCC));
      expect(day.hint, const Color(0xFF999999));
      expect(day.hintOver, const Color(0xFF919191));
      expect(day.separator, const Color(0xFFF1F1F1));
      expect(day.ripple, const Color(0xFFE5E5E5));
      expect(day.arrow, const Color(0xFF222222));
    });

    test('night is the night theme\'s popup colours', () {
      const night = PointerMenuTokens.telegramNight;
      expect(night.background, const Color(0xFF17212B));
      expect(night.backgroundOver, const Color(0xFF232E3C));
      expect(night.text, const Color(0xFFF5F5F5));
      expect(night.textOver, const Color(0xFFE9ECF0));
      expect(night.textDisabled, const Color(0xFF3D4E5C));
      expect(night.hint, const Color(0xFF708499));
      expect(night.hintOver, const Color(0xFF7C90A4));
      expect(night.separator, const Color(0xFF232F39));
      expect(night.ripple, const Color(0xFF24303D));
      expect(night.arrow, const Color(0xFFE9E8E8));
    });
  });

  group('fromPalette', () {
    test('the panel is the palette\'s surface and the text its on-surface', () {
      for (final palette in [
        const ChromePalette.light(),
        const ChromePalette.dark(),
      ]) {
        final tokens = PointerMenuTokens.fromPalette(palette);
        expect(tokens.background, palette.surface);
        expect(tokens.text, palette.onSurface);
        expect(tokens.hint, palette.onSurfaceMuted);
        expect(tokens.separator, palette.separator);
      }
    });

    test('the hovered row differs from the panel on both brightnesses', () {
      for (final palette in [
        const ChromePalette.light(),
        const ChromePalette.dark(),
      ]) {
        final tokens = PointerMenuTokens.fromPalette(palette);
        expect(tokens.backgroundOver, isNot(tokens.background));
      }
    });

    test('a disabled row is fainter than a live one', () {
      final tokens = PointerMenuTokens.fromPalette(const ChromePalette.light());
      expect(tokens.textDisabled.a, lessThan(tokens.text.a));
    });
  });

  group('copyWith, lerp and equality', () {
    test('copyWith replaces only the named field', () {
      const base = PointerMenuTokens.telegramDay;
      final next = base.copyWith(text: const Color(0xFF123456));
      expect(next.text, const Color(0xFF123456));
      expect(next.background, base.background);
    });

    test('lerp returns the endpoints and blends the middle', () {
      const a = PointerMenuTokens.telegramDay;
      const b = PointerMenuTokens.telegramNight;
      expect(PointerMenuTokens.lerp(a, b, 0), a);
      expect(PointerMenuTokens.lerp(a, b, 1), b);
      expect(
        PointerMenuTokens.lerp(a, b, 0.5).background,
        Color.lerp(a.background, b.background, 0.5),
      );
    });

    test('equality is by value', () {
      expect(
        PointerMenuTokens.fromPalette(const ChromePalette.light()),
        PointerMenuTokens.fromPalette(const ChromePalette.light()),
      );
      expect(
        PointerMenuTokens.telegramDay,
        isNot(PointerMenuTokens.telegramNight),
      );
    });
  });
}
