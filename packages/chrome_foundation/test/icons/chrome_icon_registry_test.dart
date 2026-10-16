import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stock registry', () {
    const registry = ChromeIconRegistry.stock;

    test('every stock id resolves to a registered painter', () {
      for (final id in ChromeIconId.stockIds) {
        expect(registry.contains(id), isTrue, reason: id.value);
        expect(registry.painterFor(id), isNot(ChromeIconRegistry.fallback));
      }
    });

    test('stock ids are distinct', () {
      final values = ChromeIconId.stockIds.map((id) => id.value).toList();
      expect(values.toSet(), hasLength(values.length));
    });

    test('the emoji toggle states are font icons that can morph', () {
      for (final id in [
        ChromeIconId.emoji,
        ChromeIconId.keyboard,
        ChromeIconId.stickers,
        ChromeIconId.gif,
      ]) {
        expect(registry.painterFor(id), isA<ChromeIconPainter$Font>());
      }
    });
  });

  group('lookup', () {
    test('an unknown id resolves to the neutral fallback glyph', () {
      const registry = ChromeIconRegistry.stock;
      const unknown = ChromeIconId('no-such-icon');
      expect(registry.contains(unknown), isFalse);
      expect(registry.painterFor(unknown), same(ChromeIconRegistry.fallback));
      expect(
        ChromeIconRegistry.fallback,
        isA<ChromeIconPainter$Font>().having(
          (p) => p.icon,
          'icon',
          Icons.circle_outlined,
        ),
      );
    });
  });

  group('registration', () {
    const custom = ChromeIconId('host-star');
    const star = ChromeIconPainter.font(Icons.star_rounded);

    test('withPainters() adds a painter for a custom id', () {
      final registry = ChromeIconRegistry.stock.withPainters({custom: star});
      expect(registry.contains(custom), isTrue);
      expect(registry.painterFor(custom), same(star));
    });

    test('withPainters() leaves the original registry untouched', () {
      ChromeIconRegistry.stock.withPainters({custom: star});
      expect(ChromeIconRegistry.stock.contains(custom), isFalse);
    });

    test('a host painter replaces a stock id', () {
      final registry = ChromeIconRegistry.stock.withPainters({
        ChromeIconId.send: star,
      });
      expect(registry.painterFor(ChromeIconId.send), same(star));
      expect(
        registry.painterFor(ChromeIconId.emoji),
        ChromeIconRegistry.stock.painterFor(ChromeIconId.emoji),
      );
    });

    test('registries with the same entries are equal', () {
      expect(
        ChromeIconRegistry.stock.withPainters({custom: star}),
        ChromeIconRegistry.stock.withPainters({custom: star}),
      );
      expect(
        ChromeIconRegistry.stock.withPainters({custom: star}),
        isNot(ChromeIconRegistry.stock),
      );
    });
  });

  group('ChromeIconId', () {
    test('compares by value', () {
      expect(const ChromeIconId('a') == const ChromeIconId('a'), isTrue);
      expect(const ChromeIconId('a') == const ChromeIconId('b'), isFalse);
    });

    test('rejects an empty id', () {
      expect(() => ChromeIconId(''), throwsAssertionError);
    });
  });
}
