import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('public API', () {
    final barrel = File('lib/chrome_foundation.dart').readAsStringSync();
    final exports = RegExp(
      "export '([^']+)'( show ([^;]+))?;",
    ).allMatches(barrel).toList();

    test('exports no strategy, shader or resolved-style file', () {
      final paths = [for (final e in exports) e.group(1)!];

      expect(
        paths.where(
          (p) =>
              p.startsWith('src/glass/strategy/') ||
              p.startsWith('src/glass/shader/') ||
              p == 'src/glass/glass_style.dart',
        ),
        isEmpty,
      );
    });

    test('exposes only the scope and source of the glass source file', () {
      final source = exports.singleWhere(
        (e) => e.group(1) == 'src/glass/glass_source.dart',
      );

      expect(source.group(3)!.split(',').map((s) => s.trim()).toSet(), {
        'GlassSource',
        'GlassSourceScope',
      });
    });

    test('the glass directory holds nothing but the audited exports', () {
      final glassExports = {
        for (final e in exports)
          if (e.group(1)!.startsWith('src/glass/')) e.group(1)!,
      };

      expect(glassExports, {
        'src/glass/glass_capabilities.dart',
        'src/glass/glass_material.dart',
        'src/glass/glass_quality.dart',
        'src/glass/glass_quality_scope.dart',
        'src/glass/glass_source.dart',
        'src/glass/glass_surface.dart',
      });
    });
  });
}
