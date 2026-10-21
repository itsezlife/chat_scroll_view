import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A submenu on the right whose near edge is x = 300 from y = 100 to 300; the
  // pointer left the parent row at (250, 150).
  const apex = Offset(250, 150);
  const near = (top: Offset(300, 100), bottom: Offset(300, 300));

  bool inside(Offset p) => PointerMenuAim.contains(
    apex: apex,
    edgeTop: near.top,
    edgeBottom: near.bottom,
    point: p,
  );

  group('the aim triangle', () {
    test(
      'holds a point on the line from the apex to the middle of the edge',
      () {
        expect(inside(const Offset(275, 175)), isTrue);
      },
    );

    test('holds a point near the near edge within its height', () {
      expect(inside(const Offset(299, 120)), isTrue);
      expect(inside(const Offset(299, 280)), isTrue);
    });

    test('lets go of a point above the line to the edge\'s top', () {
      expect(inside(const Offset(275, 100)), isFalse);
    });

    test('lets go of a point below the line to the edge\'s bottom', () {
      expect(inside(const Offset(275, 260)), isFalse);
    });

    test('lets go of a point behind the apex', () {
      expect(inside(const Offset(200, 175)), isFalse);
    });

    test('lets go of a point past the near edge', () {
      expect(inside(const Offset(320, 175)), isFalse);
    });

    test('the apex itself is held', () {
      expect(inside(apex), isTrue);
    });

    test('works for a submenu on the left too', () {
      expect(
        PointerMenuAim.contains(
          apex: const Offset(350, 150),
          edgeTop: const Offset(300, 100),
          edgeBottom: const Offset(300, 300),
          point: const Offset(325, 175),
        ),
        isTrue,
      );
    });
  });
}
