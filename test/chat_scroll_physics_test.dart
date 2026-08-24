import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fling', () {
    test('starts flinging and settles to idle', () {
      final physics = ChatScrollPhysics()..startFling(1200);
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
      final physics = ChatScrollPhysics()
        ..startFling(800)
        ..cancelFling();
      expect(physics.isFlinging, isFalse);
      expect(physics.tickFling(Duration.zero), 0);
    });
  });
}
