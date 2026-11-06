import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cell = Rect.fromLTWH(10, 20, 100, 100);

  group('contain', () {
    test('a wide source is inscribed with bars above and below', () {
      final placed = AssetFit.contain.place(const Size(200, 100), cell);

      expect(placed.source, const Rect.fromLTWH(0, 0, 200, 100));
      expect(placed.destination, const Rect.fromLTWH(10, 45, 100, 50));
    });

    test('a source of the cell aspect fills it', () {
      final placed = AssetFit.contain.place(const Size(50, 50), cell);

      expect(placed.source, const Rect.fromLTWH(0, 0, 50, 50));
      expect(placed.destination, cell);
    });
  });

  group('cover', () {
    test('a wide source in a square cell is cropped left and right', () {
      final placed = AssetFit.cover.place(const Size(400, 100), cell);

      expect(placed.destination, cell);
      expect(placed.source, const Rect.fromLTWH(150, 0, 100, 100));
    });

    test('a tall source in a square cell is cropped above and below', () {
      final placed = AssetFit.cover.place(const Size(100, 400), cell);

      expect(placed.destination, cell);
      expect(placed.source, const Rect.fromLTWH(0, 150, 100, 100));
    });

    test('the crop keeps the cell aspect, whatever the scale', () {
      final placed = AssetFit.cover.place(
        const Size(300, 200),
        const Rect.fromLTWH(0, 0, 90, 90),
      );

      // 300x200 into 90x90: the longer side is cut to the cell's aspect.
      expect(placed.source.width / placed.source.height, closeTo(1, 1e-9));
      expect(placed.source, const Rect.fromLTWH(50, 0, 200, 200));
    });

    test('a source of the cell aspect is not cropped', () {
      final placed = AssetFit.cover.place(const Size(50, 50), cell);

      expect(placed.source, const Rect.fromLTWH(0, 0, 50, 50));
      expect(placed.destination, cell);
    });
  });

  test('a region of a page is placed as a picture, the crop offset by it', () {
    const region = Rect.fromLTWH(30, 40, 400, 100);

    final placed = AssetFit.cover.placeRegion(region, cell);

    expect(placed.destination, cell);
    expect(placed.source, const Rect.fromLTWH(180, 40, 100, 100));
    expect(
      AssetFit.contain.placeRegion(region, cell).source,
      region,
      reason: 'contain draws the whole region',
    );
  });

  test('an empty source or cell is placed as it is, never divided by', () {
    for (final fit in AssetFit.values) {
      final placed = fit.place(Size.zero, cell);
      expect(placed.destination, cell);
      expect(placed.source, Rect.zero);
      expect(fit.place(const Size(10, 10), Rect.zero).destination, Rect.zero);
    }
  });
}
