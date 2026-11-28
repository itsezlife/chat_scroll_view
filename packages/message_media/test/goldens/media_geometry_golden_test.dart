/// Goldens of the Android media layout: a single box and the mosaics of two
/// and three items, laid out by the message media policy, each cell a flat
/// rounded fill.
///
/// The fills stand in for pictures, which are drawn by the cells, not by
/// the layout: the scenes check sizes, seams and corner radii only.
/// Regenerate with `scripts/goldens --update` (baselines are the CI
/// runner's).
library;

import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';
import 'package:message_media/message_media.dart';

import '../support/media_scopes.dart';

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

/// Paints a media layout's cells as rounded rects: a corner whose two sides
/// touch the bubble's edge takes the outer media radius, any other the inner
/// one.
class _GeometryFill extends StatelessWidget {
  _GeometryFill(this.layout)
    : cells = [for (final cell in layout.cells) _rrectOf(cell)];

  final MediaLayout layout;
  final List<RRect> cells;

  static RRect _rrectOf(MediaCell cell) {
    final outer = Radius.circular(MediaLayoutMetrics.mediaOuterRadius());
    const inner = Radius.circular(MediaLayoutMetrics.mediaInnerRadius);
    final MediaCell(:rect, neighbours: n) = cell;
    Radius corner(MediaNeighbour a, MediaNeighbour b) =>
        a == MediaNeighbour.bubbleEdge && b == MediaNeighbour.bubbleEdge
        ? outer
        : inner;
    return RRect.fromRectAndCorners(
      rect,
      topLeft: corner(n.top, n.left),
      topRight: corner(n.top, n.right),
      bottomLeft: corner(n.bottom, n.left),
      bottomRight: corner(n.bottom, n.right),
    );
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: layout.size, painter: _FillPainter(cells));
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

const _policy = MessageMediaPolicy.android();

MediaItem _item(int index, ContentSize size) => MediaItem(
  id: MediaItemId('$index'),
  kind: MediaItemKind.photo,
  descriptor: ContentDescriptor(key: ContentKey.document('$index'), size: size),
);

/// A single box 300 wide: a list 364 wide less the landscape inset of 64.
_GeometryFill _single(ContentSize size) => _GeometryFill(
  _policy.layout(
    MediaLayoutInput(
      text: MediaScopes.text,
      items: [_item(0, size)],
      availableWidth: 364,
      displaySize: const Size(364, 800),
    ),
  ),
);

/// An album 300 wide (0.8 of a list 375 wide) whose rows are bounded by
/// half of a 610.5 screen height: 305.25, the height the mosaic's own
/// proportions give at that width, so the scenes keep the geometry's
/// baselines.
_GeometryFill _album(List<ContentSize> sizes) => _GeometryFill(
  _policy.layout(
    MediaLayoutInput(
      text: MediaScopes.text,
      items: [for (final (index, size) in sizes.indexed) _item(index, size)],
      availableWidth: 375,
      displaySize: const Size(375, 610.5),
    ),
  ),
);

void main() {
  useGoldenBaselines('test/goldens/media_geometry_golden_test.dart');

  Future<void> expectScene(
    WidgetTester tester,
    String name,
    _GeometryFill fill, {
    double height = 480,
  }) async {
    await tester.pumpWidget(
      MediaScopes.wrap(_box(height: height, child: fill)),
    );
    await expectLater(
      find.byType(_GeometryFill),
      matchesGoldenFile('$name.png'),
    );
  }

  testWidgets('single 16:9', (tester) async {
    await expectScene(
      tester,
      'single_16x9',
      _single(const ContentSize(1600, 900)),
    );
  });

  testWidgets('album 2× square', (tester) async {
    await expectScene(
      tester,
      'album_2_square',
      _album(const [ContentSize(1, 1), ContentSize(1, 1)]),
    );
  });

  testWidgets('album 2× wide stacked', (tester) async {
    await expectScene(
      tester,
      'album_2_wide_stacked',
      _album(const [ContentSize(2, 1), ContentSize(2, 1)]),
    );
  });

  testWidgets('album 3× first wide', (tester) async {
    await expectScene(
      tester,
      'album_3_first_wide',
      _album(const [ContentSize(3, 2), ContentSize(1, 1), ContentSize(1, 1)]),
      height: 560,
    );
  });

  testWidgets('album 3× first narrow sibling', (tester) async {
    await expectScene(
      tester,
      'album_3_first_narrow',
      _album(const [ContentSize(1, 2), ContentSize(1, 1), ContentSize(1, 1)]),
      height: 560,
    );
  });

  testWidgets('album awkward (line solver)', (tester) async {
    await expectScene(
      tester,
      'album_awkward',
      _album(const [ContentSize(5, 2), ContentSize(5, 2), ContentSize(1, 1)]),
      height: 560,
    );
  });
}
