import 'dart:ui';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatSmoothContour — Cross Product & Corner Orientation', () {
    test('computes 2D cross product of orthogonal tangent vectors', () {
      // Clockwise 90-degree turns (convex outer corners in screen coordinates: Y-down)
      // Right to Down
      expect(
        ChatSmoothContour.crossProduct(const Offset(1, 0), const Offset(0, 1)),
        1,
      );
      // Down to Left
      expect(
        ChatSmoothContour.crossProduct(const Offset(0, 1), const Offset(-1, 0)),
        1,
      );
      // Left to Up
      expect(
        ChatSmoothContour.crossProduct(
          const Offset(-1, 0),
          const Offset(0, -1),
        ),
        1,
      );
      // Up to Right
      expect(
        ChatSmoothContour.crossProduct(const Offset(0, -1), const Offset(1, 0)),
        1,
      );

      // Counter-clockwise 90-degree turns (reflex inner corners)
      // Down to Right
      expect(
        ChatSmoothContour.crossProduct(const Offset(0, 1), const Offset(1, 0)),
        -1,
      );
      // Right to Up
      expect(
        ChatSmoothContour.crossProduct(const Offset(1, 0), const Offset(0, -1)),
        -1,
      );

      // Collinear vectors
      expect(
        ChatSmoothContour.crossProduct(const Offset(1, 0), const Offset(1, 0)),
        0,
      );
    });

    test(
      'cornerOrientation correctly classifies convex, reflex, and collinear',
      () {
        expect(
          ChatSmoothContour.cornerOrientation(
            const Offset(1, 0),
            const Offset(0, 1),
          ),
          ChatCornerOrientation.convex,
        );
        expect(
          ChatSmoothContour.cornerOrientation(
            const Offset(0, 1),
            const Offset(1, 0),
          ),
          ChatCornerOrientation.reflex,
        );
        expect(
          ChatSmoothContour.cornerOrientation(
            const Offset(1, 0),
            const Offset(2, 0),
          ),
          ChatCornerOrientation.collinear,
        );
      },
    );
  });

  group('ChatSmoothContour — Empty & Degenerate Inputs', () {
    test('returns empty path for empty boxes list', () {
      final path = ChatSmoothContour.buildPath(const []);
      expect(path.getBounds(), Rect.zero);
      expect(path.computeMetrics().isEmpty, isTrue);
    });

    test('ignores zero-width or zero-height boxes', () {
      final path = ChatSmoothContour.buildPath(const [
        Rect.fromLTRB(10, 10, 10, 30), // zero width
        Rect.fromLTRB(20, 20, 50, 20), // zero height
        Rect.fromLTRB(30, 30, 20, 40), // negative width
      ]);
      expect(path.getBounds(), Rect.zero);
      expect(path.computeMetrics().isEmpty, isTrue);
    });

    test('builds sharp path when radius is 0 or negative', () {
      const box = Rect.fromLTWH(10, 10, 100, 30);
      final path0 = ChatSmoothContour.buildPath([box], radius: 0);
      expect(path0.getBounds(), box);

      final metrics0 = path0.computeMetrics().toList();
      expect(metrics0.length, 1);
      expect(metrics0.first.isClosed, isTrue);
      // Sharp corner (10, 10) is contained
      expect(path0.contains(const Offset(10.1, 10.1)), isTrue);

      final pathNeg = ChatSmoothContour.buildPath([box], radius: -5);
      expect(pathNeg.getBounds(), box);
      final metricsNeg = pathNeg.computeMetrics().toList();
      expect(metricsNeg.length, 1);
      expect(metricsNeg.first.isClosed, isTrue);
      expect(pathNeg.contains(const Offset(10.1, 10.1)), isTrue);
    });
  });

  group('ChatSmoothContour — Single-Line Text Boxes', () {
    test('builds closed 4-corner rounded path with correct bounds', () {
      const box = Rect.fromLTWH(20, 30, 120, 40);
      final path = ChatSmoothContour.buildPath([box], radius: 6);

      expect(path.getBounds(), box);

      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.isClosed, isTrue);

      // Center point is contained
      expect(path.contains(const Offset(80, 50)), isTrue);
      // Outside points are not contained
      expect(path.contains(const Offset(10, 10)), isFalse);
      expect(path.contains(const Offset(150, 50)), isFalse);

      // Corner point (20, 30) is outside the rounded arc
      expect(path.contains(const Offset(20.5, 30.5)), isFalse);
      // Point slightly inward from the corner is inside
      expect(path.contains(const Offset(26, 36)), isTrue);
    });

    test('clamps corner radius to half minimum edge length', () {
      // Height is 10, so max radius can be at most 5.0
      const box = Rect.fromLTWH(0, 0, 100, 10);
      final path = ChatSmoothContour.buildPath([box], radius: 20);

      expect(path.getBounds(), box);
      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.isClosed, isTrue);
      expect(path.contains(const Offset(50, 5)), isTrue);
    });
  });

  group('ChatSmoothContour — Multi-Line Wrapped Text', () {
    test(
      'handles 2-line wrapped text (first line indented, second line full width)',
      () {
        // Line 0: [60, 200], Y in [10, 30]
        // Line 1: [10, 180], Y in [30, 50]
        const line0 = Rect.fromLTRB(60, 10, 200, 30);
        const line1 = Rect.fromLTRB(10, 30, 180, 50);

        final path = ChatSmoothContour.buildPath([line0, line1], radius: 4);

        expect(path.getBounds(), const Rect.fromLTRB(10, 10, 200, 50));

        final metrics = path.computeMetrics().toList();
        expect(metrics.length, 1);
        expect(metrics.first.isClosed, isTrue);

        // Inside line 0
        expect(path.contains(const Offset(100, 20)), isTrue);
        // Inside line 1
        expect(path.contains(const Offset(50, 40)), isTrue);

        // In the notch above line 1 (left of line 0): outside!
        expect(path.contains(const Offset(30, 20)), isFalse);
        // In the notch below line 0 (right of line 1): outside!
        expect(path.contains(const Offset(190, 40)), isFalse);

        // Near the reflex corner (60, 30):
        // (62, 28) is inside line 0
        expect(path.contains(const Offset(62, 28)), isTrue);
        // (58, 32) is inside line 1
        expect(path.contains(const Offset(58, 32)), isTrue);
        // (59.5, 29.5) is inside the smooth reflex fillet bridging the step
        expect(path.contains(const Offset(59.5, 29.5)), isTrue);
        // (55, 25) is outside the fillet
        expect(path.contains(const Offset(55, 25)), isFalse);
      },
    );

    test('handles 3-line wrapped text with reflex inner corners', () {
      // Line 0: [80, 300], Y in [0, 20]
      // Line 1: [20, 300], Y in [20, 40]
      // Line 2: [20, 160], Y in [40, 60]
      const line0 = Rect.fromLTRB(80, 0, 300, 20);
      const line1 = Rect.fromLTRB(20, 20, 300, 40);
      const line2 = Rect.fromLTRB(20, 40, 160, 60);

      final path = ChatSmoothContour.buildPath([
        line0,
        line1,
        line2,
      ], radius: 4);

      expect(path.getBounds(), const Rect.fromLTRB(20, 0, 300, 60));

      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.isClosed, isTrue);

      // Line 0 interior
      expect(path.contains(const Offset(150, 10)), isTrue);
      // Line 1 interior
      expect(path.contains(const Offset(50, 30)), isTrue);
      // Line 2 interior
      expect(path.contains(const Offset(50, 50)), isTrue);

      // Empty space above line 1 (left of line 0)
      expect(path.contains(const Offset(40, 10)), isFalse);
      // Empty space below line 1 (right of line 2)
      expect(path.contains(const Offset(250, 50)), isFalse);
    });

    test('eliminates collinear vertices when adjacent lines share edges', () {
      // Two lines with identical horizontal extents
      const line0 = Rect.fromLTRB(20, 10, 200, 30);
      const line1 = Rect.fromLTRB(20, 30, 200, 50);

      final path = ChatSmoothContour.buildPath([line0, line1], radius: 5);

      expect(path.getBounds(), const Rect.fromLTRB(20, 10, 200, 50));

      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.isClosed, isTrue);

      // Middle points along the shared boundary Y=30 are cleanly inside
      expect(path.contains(const Offset(100, 30)), isTrue);
      expect(path.contains(const Offset(21, 30)), isTrue);
      expect(path.contains(const Offset(199, 30)), isTrue);
    });

    test(
      'smooths small step transitions with clamped radius without self-intersections',
      () {
        // Line 0 and Line 1 differ by only 2dp horizontally
        const line0 = Rect.fromLTRB(20, 0, 102, 20);
        const line1 = Rect.fromLTRB(20, 20, 100, 40);

        final path = ChatSmoothContour.buildPath([line0, line1], radius: 6);

        expect(path.getBounds(), const Rect.fromLTRB(20, 0, 102, 40));

        final metrics = path.computeMetrics().toList();
        expect(metrics.length, 1);
        expect(metrics.first.isClosed, isTrue);
        expect(path.contains(const Offset(50, 20)), isTrue);
      },
    );

    test('merges multiple boxes on the same line', () {
      // Two fragmented spans on line 0, plus line 1
      const span0a = Rect.fromLTRB(20, 0, 60, 20);
      const span0b = Rect.fromLTRB(60, 0, 120, 20);
      const line1 = Rect.fromLTRB(20, 20, 80, 40);

      final path = ChatSmoothContour.buildPath([
        span0a,
        span0b,
        line1,
      ], radius: 4);

      expect(path.getBounds(), const Rect.fromLTRB(20, 0, 120, 40));

      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.isClosed, isTrue);
    });

    test(
      'handles vertically or horizontally disconnected boxes as distinct closed contours',
      () {
        // Two boxes with a vertical gap (e.g. separate paragraphs)
        const box1 = Rect.fromLTWH(10, 10, 100, 20);
        const box2 = Rect.fromLTWH(10, 50, 100, 20);

        final path = ChatSmoothContour.buildPath([box1, box2], radius: 4);

        final metrics = path.computeMetrics().toList();
        expect(metrics.length, 2);
        expect(metrics[0].isClosed, isTrue);
        expect(metrics[1].isClosed, isTrue);

        expect(path.contains(const Offset(50, 20)), isTrue);
        expect(path.contains(const Offset(50, 60)), isTrue);
        // In the gap: outside!
        expect(path.contains(const Offset(50, 35)), isFalse);
      },
    );
  });
}
