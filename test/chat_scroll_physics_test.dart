import 'package:chatscrollview/src/chat_scroll/chat_scroll_physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyOverscrollResistance', () {
    test('returns delta unchanged when no overscroll', () {
      final physics = ChatScrollPhysics(overscrollOnSide: (_) => 0);
      expect(physics.applyOverscrollResistance(100, 0), 100);
    });

    test('returns delta unchanged when moving back toward content', () {
      final physics = ChatScrollPhysics(overscrollOnSide: (_) => 0);
      expect(physics.applyOverscrollResistance(-10, 50), -10);
      expect(physics.applyOverscrollResistance(10, -50), 10);
    });

    test('halves delta at overscrollMax magnitude', () {
      final physics = ChatScrollPhysics(
        overscrollMax: 200,
        overscrollOnSide: (_) => 0,
      );
      expect(physics.applyOverscrollResistance(100, 200), 50);
    });

    test('increases resistance as overscroll grows', () {
      final physics = ChatScrollPhysics(
        overscrollMax: 200,
        overscrollOnSide: (_) => 0,
      );
      final small = physics.applyOverscrollResistance(100, 50).abs();
      final large = physics.applyOverscrollResistance(100, 400).abs();
      expect(large, lessThan(small));
    });
  });

  group('fling', () {
    test('starts flinging and settles to idle', () {
      final physics = ChatScrollPhysics(overscrollOnSide: (_) => 0);
      physics.startFling(1200);
      expect(physics.isFlinging, isTrue);

      var elapsed = Duration.zero;
      var total = 0.0;
      for (var i = 0; i < 400; i++) {
        elapsed += const Duration(milliseconds: 16);
        total += physics.tickFling(elapsed);
      }
      expect(physics.isFlinging, isFalse);
      expect(total, isNot(0.0));
    });

    test('cancelFling stops immediately', () {
      final physics = ChatScrollPhysics(overscrollOnSide: (_) => 0);
      physics.startFling(800);
      physics.cancelFling();
      expect(physics.isFlinging, isFalse);
      expect(physics.tickFling(Duration.zero), 0);
    });
  });

  group('bounceback', () {
    test('arms, ticks, and completes', () {
      var current = 80.0;
      final physics = ChatScrollPhysics(
        bounceDuration: const Duration(milliseconds: 100),
        overscrollOnSide: (_) => current,
      );
      physics.maybeStartBounceback(80, BouncebackSide.top);
      expect(physics.isBouncing, isTrue);

      var elapsed = Duration.zero;
      for (var i = 0; i < 15; i++) {
        elapsed += const Duration(milliseconds: 10);
        final delta = physics.tickBounceback(elapsed);
        current += delta;
      }
      expect(physics.isBouncing, isFalse);
    });

    test('cancelBounceback clears active state', () {
      final physics = ChatScrollPhysics(overscrollOnSide: (_) => 50);
      physics.maybeStartBounceback(50, BouncebackSide.top);
      physics.cancelBounceback();
      expect(physics.isBouncing, isFalse);
    });
  });

  group('tick', () {
    test('combines fling and bounceback deltas', () {
      final physics = ChatScrollPhysics(overscrollOnSide: (_) => 40);
      physics.startFling(500);
      physics.maybeStartBounceback(40, BouncebackSide.top);
      final combined = physics.tick(const Duration(milliseconds: 16));
      final separate =
          physics.tickFling(const Duration(milliseconds: 16)) +
          physics.tickBounceback(const Duration(milliseconds: 16));
      expect(combined, separate);
    });
  });
}
