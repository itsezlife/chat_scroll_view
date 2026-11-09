import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Recording implements Canvas {
  final List<({RRect rrect, Color color})> rrects = [];
  int circles = 0;

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      rrects.add((rrect: rrect, color: paint.color));

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const rect = Rect.fromLTWH(10, 20, 100, 60);

  test('is a quiet rounded square on the shorter side, centred', () {
    final canvas = _Recording();

    const SoftPlaceholder().paint(canvas, rect, const AssetPaintContext());

    expect(canvas.circles, 0);
    final drawn = canvas.rrects.single.rrect;
    expect(
      drawn.outerRect,
      Rect.fromCenter(center: rect.center, width: 60, height: 60),
    );
    expect(drawn.tlRadiusX, closeTo(60 * SoftPlaceholder.cornerFraction, 1e-9));
  });

  test('is 25 of 255 of the text colour, or of 0xFF73787B without one', () {
    final grey = _Recording();
    final tinted = _Recording();

    const SoftPlaceholder().paint(grey, rect, const AssetPaintContext());
    const SoftPlaceholder().paint(
      tinted,
      rect,
      const AssetPaintContext(tint: Color(0xFFFF0000)),
    );

    expect(grey.rrects.single.color.toARGB32(), 0x1973787B);
    expect(tinted.rrects.single.color.toARGB32(), 0x19FF0000);
  });

  test('never animates, holds nothing and has no sprite', () {
    const placeholder = SoftPlaceholder();

    expect(placeholder.isAnimated, isFalse);
    expect(placeholder.isHolding, isFalse);
    expect(placeholder.sprite, isNull);
    expect(placeholder.restart(), isFalse);
  });
}
