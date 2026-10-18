import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('follows the text colour and moves the standard particles', () {
      for (final palette in [
        const ChromePalette.light(),
        const ChromePalette.dark(),
      ]) {
        final tokens = SpoilerTokens.fromPalette(palette);
        expect(tokens.color, isNull);
        expect(tokens.particles, SpoilerParticleMotion.standard);
      }
    });
  });

  group('colorOver', () {
    test('is the text colour when no override is given', () {
      final tokens = SpoilerTokens.fromPalette(const ChromePalette.light());
      expect(
        tokens.colorOver(const Color(0xFF445566)),
        const Color(0xFF445566),
      );
    });

    test('is the override when one is given', () {
      final tokens = SpoilerTokens.fromPalette(
        const ChromePalette.light(),
      ).copyWith(color: const Color(0xFFFF0000));
      expect(
        tokens.colorOver(const Color(0xFF445566)),
        const Color(0xFFFF0000),
      );
    });

    test('followingText removes an override', () {
      final tokens = SpoilerTokens.fromPalette(
        const ChromePalette.light(),
      ).copyWith(color: const Color(0xFFFF0000)).followingText();
      expect(tokens.color, isNull);
    });
  });

  group('copyWith', () {
    test('overrides the particles and keeps the colour', () {
      final base = SpoilerTokens.fromPalette(
        const ChromePalette.light(),
      ).copyWith(color: const Color(0xFF010203));
      const slow = SpoilerParticleMotion(maxSpeed: 5);
      final next = base.copyWith(particles: slow);
      expect(next.particles, slow);
      expect(next.color, base.color);
    });
  });

  group('lerp', () {
    test('blends two overrides', () {
      final a = SpoilerTokens.fromPalette(
        const ChromePalette.light(),
      ).copyWith(color: const Color(0xFF000000));
      final b = a.copyWith(color: const Color(0xFFFFFFFF));
      expect(
        SpoilerTokens.lerp(a, b, 0.5).color,
        Color.lerp(const Color(0xFF000000), const Color(0xFFFFFFFF), 0.5),
      );
    });

    test(
      'switches between an override and following the text at the middle',
      () {
        final follow = SpoilerTokens.fromPalette(const ChromePalette.light());
        final override = follow.copyWith(color: const Color(0xFFFF0000));
        expect(SpoilerTokens.lerp(follow, override, 0.25).color, isNull);
        expect(
          SpoilerTokens.lerp(follow, override, 0.75).color,
          const Color(0xFFFF0000),
        );
      },
    );

    test('returns the endpoints at 0 and 1', () {
      final a = SpoilerTokens.fromPalette(const ChromePalette.light());
      final b = a.copyWith(
        color: const Color(0xFF123456),
        particles: const SpoilerParticleMotion(maxSpeed: 12),
      );
      expect(SpoilerTokens.lerp(a, b, 0), a);
      expect(SpoilerTokens.lerp(a, b, 1), b);
    });
  });

  test('equality is by value', () {
    final a = SpoilerTokens.fromPalette(const ChromePalette.light());
    expect(a, SpoilerTokens.fromPalette(const ChromePalette.dark()));
    expect(a, isNot(a.copyWith(color: const Color(0xFF123456))));
    expect(
      a.hashCode,
      SpoilerTokens.fromPalette(const ChromePalette.light()).hashCode,
    );
  });
}
