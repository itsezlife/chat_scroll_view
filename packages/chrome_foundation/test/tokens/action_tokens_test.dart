import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('maps the light palette to the Telegram-derived floating chrome', () {
      final tokens = ActionTokens.fromPalette(const ChromePalette.light());
      expect(tokens.floatingFill, const Color(0xFFE8EAED));
      expect(tokens.floatingSelectedFill, const Color(0xFFFFFFFF));
      expect(tokens.floatingLabel, const Color(0xFF000000));
    });

    test(
      'an action icon under the pointer takes the palette\'s active icon',
      () {
        for (final palette in [
          const ChromePalette.light(),
          const ChromePalette.dark(),
        ]) {
          final tokens = ActionTokens.fromPalette(palette);

          expect(tokens.iconHover, palette.iconActive);
          expect(tokens.iconHover, isNot(tokens.icon));
        }
      },
    );

    test('the send button is the accent with its on-accent glyph', () {
      final palette = const ChromePalette.dark().copyWith(
        accent: const Color(0xFF0000FF),
        onAccent: const Color(0xFFFFFF00),
      );
      final tokens = ActionTokens.fromPalette(palette);
      expect(tokens.send, const Color(0xFF0000FF));
      expect(tokens.onSend, const Color(0xFFFFFF00));
    });
  });

  group('copyWith', () {
    test('overrides one field and keeps the rest', () {
      final base = ActionTokens.fromPalette(const ChromePalette.light());
      final next = base.copyWith(send: const Color(0xFF010203));
      expect(next.send, const Color(0xFF010203));
      expect(next.icon, base.icon);
      expect(next.copyWith(send: base.send), base);
    });

    test('overrides the hover icon too', () {
      final base = ActionTokens.fromPalette(const ChromePalette.light());

      expect(
        base.copyWith(iconHover: const Color(0xFF040506)).iconHover,
        const Color(0xFF040506),
      );
    });
  });

  group('lerp', () {
    final a = ActionTokens.fromPalette(const ChromePalette.light());
    final b = ActionTokens.fromPalette(const ChromePalette.dark());

    test('returns the endpoints at 0 and 1', () {
      expect(ActionTokens.lerp(a, b, 0), a);
      expect(ActionTokens.lerp(a, b, 1), b);
    });

    test('blends every field halfway', () {
      final mid = ActionTokens.lerp(a, b, 0.5);
      expect(mid.floatingFill, Color.lerp(a.floatingFill, b.floatingFill, 0.5));
      expect(mid.send, Color.lerp(a.send, b.send, 0.5));
      expect(mid.iconHover, Color.lerp(a.iconHover, b.iconHover, 0.5));
    });
  });

  test('equality is by value', () {
    final a = ActionTokens.fromPalette(const ChromePalette.light());
    expect(a, ActionTokens.fromPalette(const ChromePalette.light()));
    expect(
      a.hashCode,
      ActionTokens.fromPalette(const ChromePalette.light()).hashCode,
    );
    expect(a, isNot(ActionTokens.fromPalette(const ChromePalette.dark())));
  });
}
