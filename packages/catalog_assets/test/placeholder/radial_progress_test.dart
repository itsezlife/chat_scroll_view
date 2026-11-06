import 'dart:math' as math;
import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Arc = ({Rect rect, double start, double sweep, Paint paint});
typedef _Line = ({Offset from, Offset to, Paint paint});

/// What one paint asks of the canvas, copied at the call as the engine does.
final class _Recording implements Canvas {
  final List<({Offset center, double radius, Color color})> discs = [];
  final List<_Arc> arcs = [];
  final List<_Line> lines = [];

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
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add((
    from: p1,
    to: p2,
    paint: Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth,
  ));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

double _rad(double degrees) => degrees * math.pi / 180;

void main() {
  const center = Offset(50, 60);

  _Recording paint({
    required double radius,
    Duration time = Duration.zero,
    double? progress,
    double opacity = 1,
  }) {
    final canvas = _Recording();
    RadialProgress.paint(
      canvas,
      center,
      radius: radius,
      time: time,
      progress: progress,
      opacity: opacity,
    );
    return canvas;
  }

  // The panel's GIF cell: a 24 dp box, so radius 12 (ContextLinkCell).
  group('the panel size, radius 12', () {
    test('a translucent black disc, the arc inside it, a cross in the arc', () {
      final canvas = paint(radius: 12);

      expect(canvas.discs.single.center, center);
      expect(canvas.discs.single.radius, 12);
      expect(canvas.discs.single.color, const Color(0x66000000));
      // The arc rect is the disc's box inset by 4: radius 8.
      expect(
        canvas.arcs.single.rect,
        Rect.fromCircle(center: center, radius: 8),
      );
      // Below 0.7 of the 48 dp reference the stroke thins to 2.
      expect(canvas.arcs.single.paint.strokeWidth, 2);
      expect(canvas.arcs.single.paint.strokeCap, StrokeCap.round);
      expect(canvas.arcs.single.paint.style, PaintingStyle.stroke);
      expect(canvas.arcs.single.paint.color, const Color(0xFFFFFFFF));
      // The cross reaches 7 * (24 / 48) = 3.5 from the centre.
      expect(canvas.lines, hasLength(2));
      expect(canvas.lines[0].from, center + const Offset(-3.5, -3.5));
      expect(canvas.lines[0].to, center + const Offset(3.5, 3.5));
      expect(canvas.lines[1].from, center + const Offset(3.5, -3.5));
      expect(canvas.lines[1].to, center + const Offset(-3.5, 3.5));
      expect(canvas.lines[0].paint.strokeWidth, 2);
    });
  });

  group('the message size, radius 22', () {
    test('the stroke is 3 and the arc sits at radius 18', () {
      final canvas = paint(radius: 22);

      expect(canvas.discs.single.radius, 22);
      expect(
        canvas.arcs.single.rect,
        Rect.fromCircle(center: center, radius: 18),
      );
      expect(canvas.arcs.single.paint.strokeWidth, 3);
      // 7 * (44 / 48) = 6.41666...
      expect(canvas.lines[0].to.dx - center.dx, closeTo(6.4166, 0.001));
    });
  });

  group('the arc', () {
    test('turns a full circle every 2.5 seconds, linearly', () {
      expect(paint(radius: 22).arcs.single.start, 0);
      expect(
        paint(
          radius: 22,
          time: const Duration(milliseconds: 625),
        ).arcs.single.start,
        closeTo(_rad(90), 1e-9),
      );
      expect(
        paint(
          radius: 22,
          time: const Duration(milliseconds: 1250),
        ).arcs.single.start,
        closeTo(_rad(180), 1e-9),
      );
      expect(
        paint(
          radius: 22,
          time: const Duration(milliseconds: 2500),
        ).arcs.single.start,
        closeTo(0, 1e-9),
      );
      expect(
        paint(
          radius: 22,
          time: const Duration(milliseconds: 3125),
        ).arcs.single.start,
        closeTo(_rad(90), 1e-9),
      );
    });

    test('sweeps the fraction done, never less than 4 degrees', () {
      expect(
        paint(radius: 22, progress: 0.5).arcs.single.sweep,
        closeTo(_rad(180), 1e-9),
      );
      expect(
        paint(radius: 22, progress: 1).arcs.single.sweep,
        closeTo(_rad(360), 1e-9),
      );
      expect(
        paint(radius: 22, progress: 0).arcs.single.sweep,
        closeTo(_rad(4), 1e-9),
      );
      expect(
        paint(radius: 22, progress: 0.005).arcs.single.sweep,
        closeTo(_rad(4), 1e-9),
      );
    });

    test('with no progress known it sweeps a quarter', () {
      expect(paint(radius: 22).arcs.single.sweep, closeTo(_rad(90), 1e-9));
    });
  });

  test('opacity scales the disc, the arc and the cross together', () {
    final canvas = paint(radius: 22, opacity: 0.5);

    expect(canvas.discs.single.color.a, closeTo(0x66 / 255 * 0.5, 0.005));
    expect(canvas.arcs.single.paint.color.a, closeTo(0.5, 0.005));
    expect(canvas.lines[0].paint.color.a, closeTo(0.5, 0.005));
  });

  test('nothing is drawn at opacity 0', () {
    final canvas = paint(radius: 22, opacity: 0);

    expect(canvas.discs, isEmpty);
    expect(canvas.arcs, isEmpty);
    expect(canvas.lines, isEmpty);
  });
}
