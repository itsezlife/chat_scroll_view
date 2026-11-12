import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Recording implements Canvas {
  final List<({Rect rect, Color color})> rects = [];
  int circles = 0;
  int rrects = 0;

  @override
  void drawRect(Rect rect, Paint paint) =>
      rects.add((rect: rect, color: paint.color));

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  void drawRRect(RRect rrect, Paint paint) => rrects++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const rect = Rect.fromLTWH(10, 20, 150, 100);

  test('fills the whole rectangle, not a circle on its shorter side', () {
    final canvas = _Recording();

    const RectPlaceholder().paint(canvas, rect, const AssetPaintContext());

    expect(canvas.circles, 0);
    expect(canvas.rrects, 0);
    expect(canvas.rects.single.rect, rect);
  });

  test('is the context tint, or the flat 0xFFEDF3F7 without one', () {
    final grey = _Recording();
    final tinted = _Recording();

    const RectPlaceholder().paint(grey, rect, const AssetPaintContext());
    const RectPlaceholder().paint(
      tinted,
      rect,
      const AssetPaintContext(tint: Color(0xFF336699), opacity: 0.5),
    );

    expect(grey.rects.single.color.toARGB32(), 0xFFEDF3F7);
    expect(
      tinted.rects.single.color.toARGB32(),
      const Color(0xFF336699).withValues(alpha: 0.5).toARGB32(),
    );
  });

  test('paints nothing into an empty rectangle', () {
    final canvas = _Recording();

    const RectPlaceholder().paint(canvas, Rect.zero, const AssetPaintContext());

    expect(canvas.rects, isEmpty);
  });

  test('never animates, holds nothing and has no sprite', () {
    const placeholder = RectPlaceholder();

    expect(placeholder.isAnimated, isFalse);
    expect(placeholder.isHolding, isFalse);
    expect(placeholder.sprite, isNull);
    expect(placeholder.restart(), isFalse);
  });
}
