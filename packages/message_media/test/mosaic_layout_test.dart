import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

void main() {
  group('MosaicLayout.project', () {
    test('2× qq projects equal side-by-side cells with gap', () {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 400,
      );
      expect(mosaic.cells, hasLength(2));
      expect(mosaic.size.width, 400);
      final a = mosaic.cells[0].rect;
      final b = mosaic.cells[1].rect;
      expect(a.width + b.width + MediaLayoutMetrics.cellGap, closeTo(400, 0.5));
      expect(b.left - a.right, closeTo(MediaLayoutMetrics.cellGap, 0.01));
      // Outer corners large, shared vertical edge inner.
      expect(mosaic.cells[0].borderRadius.topLeft.x, 15);
      expect(mosaic.cells[0].borderRadius.topRight.x, 4);
      expect(mosaic.cells[1].borderRadius.topLeft.x, 4);
      expect(mosaic.cells[1].borderRadius.topRight.x, 15);
    });

    test('2× ww stacked cells share full width', () {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 2),
          GroupedMediaMember(aspectRatio: 2),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 400,
      );
      expect(mosaic.cells[0].rect.width, 400);
      expect(mosaic.cells[1].rect.width, 400);
      expect(
        mosaic.cells[1].rect.top - mosaic.cells[0].rect.bottom,
        closeTo(MediaLayoutMetrics.cellGap, 0.01),
      );
    });

    test('3× first narrow — left and bottom-right bottoms align', () {
      // siblingHeights is [bottom, top] (sum-only); row bands must come from
      // the right-column peers or the tall left cell undershoots / right hangs.
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 0.5),
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      expect(grouped.hasSibling, isTrue);
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
      );
      final left = mosaic.cells[0].rect;
      final topRight = mosaic.cells[1].rect;
      final bottomRight = mosaic.cells[2].rect;
      expect(left.bottom, closeTo(bottomRight.bottom, 0.01));
      expect(left.top, closeTo(topRight.top, 0.01));
      expect(
        bottomRight.top - topRight.bottom,
        closeTo(MediaLayoutMetrics.cellGap, 0.01),
      );
    });
  });
}
