import 'dart:math' as math;
import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Arc = ({Rect rect, double start, double sweep, Paint paint});

/// What one paint asks of the canvas, copied at the call as the engine does.
final class _Recording implements Canvas {
  final List<({Offset center, double radius, Color color})> discs = [];
  final List<_Arc> arcs = [];
  int lines = 0;

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      discs.add((center: c, radius: radius, color: paint.color));

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) => arcs.add((
    rect: rect,
    start: startAngle,
    sweep: sweepAngle,
    paint: Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = paint.strokeCap
      ..style = paint.style,
  ));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

double _rad(double degrees) => degrees * math.pi / 180;

const _frame = Duration(milliseconds: 17);

void main() {
  const center = Offset(50, 60);

  _Recording paint(
    RadialProgress indicator, {
    double radius = 12,
    double opacity = 1,
  }) {
    final canvas = _Recording();
    indicator.paint(canvas, center, radius: radius, opacity: opacity);
    return canvas;
  }

  // Advances [indicator] [frames] frames of 17 ms after a first one at zero.
  void run(RadialProgress indicator, int frames, {Duration from = .zero}) {
    for (var i = 0; i <= frames; i++) {
      indicator.advance(from + _frame * i);
    }
  }

  // The panel's GIF cell: a 24 dp box, so radius 12.
  group('the panel size, radius 12', () {
    test('a translucent black disc and a bare arc inside it', () {
      final canvas = paint(RadialProgress());

      expect(canvas.discs.single.center, center);
      expect(canvas.discs.single.radius, 12);
      expect(canvas.discs.single.color.toARGB32(), 0x66000000);
      // The arc rect is the disc's box inset by 4: radius 8.
      expect(
        canvas.arcs.single.rect,
        Rect.fromCircle(center: center, radius: 8),
      );
      // Below 0.7 of the 48 dp referenceDiameter the stroke thins to 2.
      expect(canvas.arcs.single.paint.strokeWidth, 2);
      expect(canvas.arcs.single.paint.strokeCap, StrokeCap.round);
      expect(canvas.arcs.single.paint.style, PaintingStyle.stroke);
      expect(canvas.arcs.single.paint.color.toARGB32(), 0xFFFFFFFF);
      // The loading state of a grid cell is a bare arc with no cross.
      expect(canvas.lines, 0);
    });
  });

  group('the message size, radius 22', () {
    test('the stroke is 3 and the arc sits at radius 18', () {
      final canvas = paint(RadialProgress(), radius: 22);

      expect(canvas.discs.single.radius, 22);
      expect(
        canvas.arcs.single.rect,
        Rect.fromCircle(center: center, radius: 18),
      );
      expect(canvas.arcs.single.paint.strokeWidth, 3);
    });
  });

  group('a new indicator', () {
    test('starts at 112 degrees with a 4 degree dot', () {
      final arc = paint(RadialProgress()).arcs.single;

      expect(arc.start, closeTo(_rad(112), 1e-9));
      expect(arc.sweep, closeTo(_rad(4), 1e-9));
    });

    test('shows the progress it starts with at once', () {
      final indicator = RadialProgress(progress: 0.5);

      expect(indicator.shownProgress, 0.5);
      expect(paint(indicator).arcs.single.sweep, closeTo(_rad(180), 1e-9));
    });
  });

  group('the turn', () {
    test('is 360 degrees per 2500 ms, stepped by the frames', () {
      final indicator = RadialProgress();

      run(indicator, 1);

      // 112 + 360 * 17 / 2500.
      expect(indicator.startDegrees, closeTo(114.448, 1e-9));
    });

    test('a long gap between frames counts as 17 ms', () {
      final indicator = RadialProgress()
        ..advance(Duration.zero)
        ..advance(const Duration(seconds: 1));

      expect(indicator.startDegrees, closeTo(114.448, 1e-9));
    });

    test('the first frame only sets the clock', () {
      final indicator = RadialProgress()..advance(const Duration(seconds: 7));

      expect(indicator.startDegrees, 112);
    });

    test('wraps past a full circle', () {
      final indicator = RadialProgress();

      run(indicator, 150);

      // 112 + 360 * 2550 / 2500 = 479.2, less a turn.
      expect(indicator.startDegrees, closeTo(119.2, 1e-6));
    });

    test('a frame time that goes back does not turn it', () {
      final indicator = RadialProgress()
        ..advance(const Duration(seconds: 1))
        ..advance(Duration.zero);

      expect(indicator.startDegrees, 112);
    });
  });

  group('a new fraction', () {
    test('eases in over 200 ms, decelerating', () {
      final indicator = RadialProgress()..setProgress(0.5);

      run(indicator, 6);
      // 102 ms of 200: 0.5 * (1 - (1 - 0.51)^2).
      expect(indicator.shownProgress, closeTo(0.37995, 1e-9));

      run(indicator, 6, from: _frame * 7);
      expect(indicator.shownProgress, 0.5);
      expect(indicator.progress, 0.5);
    });

    test('mid-ease eases on from where the arc is', () {
      final indicator = RadialProgress()..setProgress(0.5);
      run(indicator, 6);

      indicator.setProgress(1);
      expect(indicator.shownProgress, closeTo(0.37995, 1e-9));

      // Six more frames: another 102 ms. 0.37995 + 0.62005 * 0.7599.
      run(indicator, 5, from: _frame * 7);
      expect(indicator.shownProgress, closeTo(0.851126, 1e-6));
    });

    test('a lower one shows at once', () {
      final indicator = RadialProgress(progress: 0.8)..setProgress(0.2);

      expect(indicator.shownProgress, 0.2);
    });

    test('without animation shows at once', () {
      final indicator = RadialProgress()..setProgress(0.6, animated: false);

      expect(indicator.shownProgress, 0.6);
      expect(paint(indicator).arcs.single.sweep, closeTo(_rad(216), 1e-9));
    });

    test('is clamped to 0..1', () {
      final indicator = RadialProgress()..setProgress(3, animated: false);

      expect(indicator.shownProgress, 1);
    });
  });

  test('opacity scales the disc and the arc together', () {
    final canvas = paint(RadialProgress(), radius: 22, opacity: 0.5);

    expect(canvas.discs.single.color.a, closeTo(0x66 / 255 * 0.5, 0.005));
    expect(canvas.arcs.single.paint.color.a, closeTo(0.5, 0.005));
  });

  test('nothing is drawn at opacity 0', () {
    final canvas = paint(RadialProgress(), radius: 22, opacity: 0);

    expect(canvas.discs, isEmpty);
    expect(canvas.arcs, isEmpty);
  });
}
