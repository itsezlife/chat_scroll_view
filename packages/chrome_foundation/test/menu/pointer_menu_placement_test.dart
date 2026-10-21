import 'dart:ui';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bounds = Rect.fromLTWH(0, 0, 800, 600);
  const size = Size(200, 300);

  PointerMenuPlacement place(
    Offset pointer, {
    Size menu = size,
    Rect area = bounds,
    TextDirection direction = TextDirection.ltr,
  }) => PointerMenuPlacements.of(
    pointer: pointer,
    size: menu,
    bounds: area,
    textDirection: direction,
  );

  group('a menu opened at the pointer', () {
    test('sits 5 px right of the pointer, level with it', () {
      final p = place(const Offset(100, 100));
      expect(p.body, const Rect.fromLTWH(105, 100, 200, 300));
      expect(p.origin, PointerMenuOrigin.topLeft);
    });

    test('opens left of the pointer when it does not fit right', () {
      final p = place(const Offset(700, 100));
      expect(p.body, const Rect.fromLTWH(495, 100, 200, 300));
      expect(p.origin, PointerMenuOrigin.topRight);
    });

    test('opens upward when it does not fit below', () {
      final p = place(const Offset(100, 500));
      expect(p.body, const Rect.fromLTWH(105, 200, 200, 300));
      expect(p.origin, PointerMenuOrigin.bottomLeft);
    });

    test('flips both ways in a corner', () {
      final p = place(const Offset(700, 500));
      expect(p.body, const Rect.fromLTWH(495, 200, 200, 300));
      expect(p.origin, PointerMenuOrigin.bottomRight);
    });

    test('a menu wider than the room left of the pointer is pushed in', () {
      final p = place(
        const Offset(50, 100),
        menu: const Size(300, 100),
        area: const Rect.fromLTWH(0, 0, 340, 600),
      );
      expect(p.body.left, 0);
      expect(p.origin, PointerMenuOrigin.topRight);
    });

    test('a menu taller than the area goes to the top and spills below', () {
      final p = place(const Offset(100, 100), menu: const Size(200, 700));
      expect(p.body.top, 0);
      expect(p.body.bottom, 700);
    });

    test('is placed inside an area that does not start at the origin', () {
      final p = place(
        const Offset(120, 140),
        area: const Rect.fromLTWH(100, 100, 400, 400),
      );
      expect(p.body, const Rect.fromLTWH(125, 140, 200, 300));
    });
  });

  group('in right-to-left', () {
    test('the body sits 5 px left of the pointer', () {
      final p = place(const Offset(400, 100), direction: TextDirection.rtl);
      expect(p.body, const Rect.fromLTWH(195, 100, 200, 300));
      expect(p.origin, PointerMenuOrigin.topRight);
    });

    test('opens right of the pointer when it does not fit left', () {
      final p = place(const Offset(100, 100), direction: TextDirection.rtl);
      expect(p.body, const Rect.fromLTWH(105, 100, 200, 300));
      expect(p.origin, PointerMenuOrigin.topLeft);
    });
  });

  group('a submenu', () {
    const parent = Rect.fromLTWH(105, 100, 200, 300);
    const sub = Size(150, 200);

    test('touches the parent and starts 8 px above the row that opened it', () {
      final p = PointerMenuPlacements.submenu(
        parent: parent,
        rowTop: 174,
        size: sub,
        bounds: bounds,
      );
      expect(p.body, const Rect.fromLTWH(305, 166, 150, 200));
      expect(p.origin, PointerMenuOrigin.topLeft);
    });

    test('opens on the parent\'s left when it does not fit right', () {
      const near = Rect.fromLTWH(205, 100, 200, 300);
      final p = PointerMenuPlacements.submenu(
        parent: near,
        rowTop: 174,
        size: sub,
        bounds: const Rect.fromLTWH(0, 0, 400, 600),
      );
      expect(p.body.right, near.left);
      expect(p.origin, PointerMenuOrigin.topRight);
    });

    test('is pushed up to the bottom of the area', () {
      final p = PointerMenuPlacements.submenu(
        parent: parent,
        rowTop: 500,
        size: sub,
        bounds: bounds,
      );
      expect(p.body.bottom, 600);
    });

    test('in right-to-left opens on the parent\'s left', () {
      final p = PointerMenuPlacements.submenu(
        parent: const Rect.fromLTWH(400, 100, 200, 300),
        rowTop: 174,
        size: sub,
        bounds: bounds,
        textDirection: TextDirection.rtl,
      );
      expect(p.body.right, 400);
      expect(p.origin, PointerMenuOrigin.topRight);
    });
  });
}
