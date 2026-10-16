import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tolerant_golden_comparator.dart';

// Regenerate with `flutter test --update-goldens test/glass`. Goldens cover
// the flat path (fill, strokes, shadow) over a striped backdrop on the pinned
// platform (macOS); rounded anti-aliased edges get a 1% pixel tolerance. The
// sampled and filtered paths depend on the device and are covered by the
// strategy-selection table and the device checklist.
const _tolerance = 0.01;

class _Row extends StatelessWidget {
  const _Row(this.palette, this.material);

  final ChromePalette palette;
  final GlassMaterial material;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.surfaceDim,
    child: Stack(
      children: [
        const Positioned.fill(child: _Stripes()),
        Center(
          child: ChromeThemeScope(
            palette: palette,
            child: SizedBox(
              width: 160,
              height: 44,
              child: GlassSurface(
                material: material,
                cornerRadius: material == GlassMaterial.topPanel ? 0 : 22,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Stripes extends StatelessWidget {
  const _Stripes();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: ColoredBox(color: Color(0xFFE53935))),
      Expanded(child: ColoredBox(color: Color(0xFF43A047))),
      Expanded(child: ColoredBox(color: Color(0xFF1E88E5))),
    ],
  );
}

void main() {
  setUpAll(() {
    final base = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = TolerantGoldenComparator(
      base.basedir.resolve('glass_flat_golden_test.dart'),
      tolerance: _tolerance,
    );
  });

  for (final material in GlassMaterial.values) {
    testWidgets('${material.name} flat glass, light and dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 80));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GlassQualityScope(
            quality: GlassQuality.flat,
            child: RepaintBoundary(
              key: const ValueKey('glass'),
              child: Row(
                children: [
                  Expanded(child: _Row(const ChromePalette.light(), material)),
                  Expanded(child: _Row(const ChromePalette.dark(), material)),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('glass')),
        matchesGoldenFile('../goldens/glass_flat_${material.name}.png'),
      );
    });
  }
}
