/// Goldens of the default media layout's geometry: a single box and the
/// mosaics of two and three items, each cell a flat rounded fill.
///
/// The fills stand in for pictures, which are drawn by the cells, not by
/// the geometry: the scenes check sizes, seams and corner radii only.
/// Regenerate with `scripts/goldens --update` (baselines are the CI
/// runner's).
library;

import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';
import 'package:message_media/message_media.dart';

const Color _fill = Color(0xFF3A3A40);
const Color _backdrop = Color(0xFF121215);

Widget _box({required Widget child, double width = 420, double height = 480}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _backdrop,
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ColoredBox(
              color: _backdrop,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

/// Paints rounded rects at the geometry's rects, with the geometry's radii.
class _GeometryFill extends StatelessWidget {
  const _GeometryFill({required this.size, required this.cells});

  /// A single box at [maxWidth] with the outer media corner on every side.
  factory _GeometryFill.single({
    required double aspectRatio,
    double maxWidth = 300,
  }) {
    final size = computeSingleMediaSize(
      aspectRatio: aspectRatio,
      maxWidth: maxWidth,
    );
    final radius = BorderRadius.circular(MediaLayoutMetrics.mediaOuterRadius());
    return _GeometryFill(
      size: size,
      cells: [radius.toRRect(Offset.zero & size)],
    );
  }

  /// Every cell of [mosaic].
  factory _GeometryFill.mosaic(MosaicLayout mosaic) => _GeometryFill(
    size: mosaic.size,
    cells: [
      for (final cell in mosaic.cells) cell.borderRadius.toRRect(cell.rect),
    ],
  );

  final Size size;
  final List<RRect> cells;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: size, painter: _FillPainter(cells));
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.cells);

  final List<RRect> cells;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _fill;
    for (final cell in cells) {
      canvas.drawRRect(cell, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FillPainter oldDelegate) =>
      oldDelegate.cells != cells;
}

MosaicLayout _mosaic(List<double> aspects) {
  final grouped = GroupedMessages.calculate(
    members: [
      for (final (index, aspect) in aspects.indexed)
        GroupedMediaMember(id: MediaItemId('$index'), aspectRatio: aspect),
    ],
  );
  return MosaicLayout.project(positions: grouped.positions, mosaicWidth: 300);
}

void main() {
  useGoldenBaselines('test/goldens/media_geometry_golden_test.dart');

  Future<void> expectScene(
    WidgetTester tester,
    String name,
    _GeometryFill fill, {
    double height = 480,
  }) async {
    await tester.pumpWidget(_box(height: height, child: fill));
    await expectLater(
      find.byType(_GeometryFill),
      matchesGoldenFile('$name.png'),
    );
  }

  testWidgets('single 16:9', (tester) async {
    await expectScene(
      tester,
      'single_16x9',
      _GeometryFill.single(aspectRatio: 16 / 9),
    );
  });

  testWidgets('album 2× square', (tester) async {
    await expectScene(
      tester,
      'album_2_square',
      _GeometryFill.mosaic(_mosaic(const [1, 1])),
    );
  });

  testWidgets('album 2× wide stacked', (tester) async {
    await expectScene(
      tester,
      'album_2_wide_stacked',
      _GeometryFill.mosaic(_mosaic(const [2, 2])),
    );
  });

  testWidgets('album 3× first wide', (tester) async {
    await expectScene(
      tester,
      'album_3_first_wide',
      _GeometryFill.mosaic(_mosaic(const [1.5, 1, 1])),
      height: 560,
    );
  });

  testWidgets('album 3× first narrow sibling', (tester) async {
    await expectScene(
      tester,
      'album_3_first_narrow',
      _GeometryFill.mosaic(_mosaic(const [0.5, 1, 1])),
      height: 560,
    );
  });

  testWidgets('album awkward (line solver)', (tester) async {
    await expectScene(
      tester,
      'album_awkward',
      _GeometryFill.mosaic(_mosaic(const [2.5, 2.5, 1])),
      height: 560,
    );
  });
}
