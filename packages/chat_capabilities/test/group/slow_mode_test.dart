import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);

  test('no slow mode lets the user send at any time', () {
    expect(SlowMode.none.canSendAt(now), isTrue);
    expect(SlowMode.none.remainingAt(now), Duration.zero);
  });

  test('a free slow mode lets the user send', () {
    const slow = SlowMode(interval: Duration(seconds: 30));
    expect(slow.isActive, isTrue);
    expect(slow.canSendAt(now), isTrue);
    expect(slow.remainingAt(now), Duration.zero);
  });

  test('waits until the next send time, which is itself allowed', () {
    final slow = SlowMode(
      interval: const Duration(seconds: 30),
      nextSendAt: now.add(const Duration(seconds: 12)),
    );
    expect(slow.canSendAt(now), isFalse);
    expect(slow.remainingAt(now), const Duration(seconds: 12));
    final at = now.add(const Duration(seconds: 12));
    expect(slow.canSendAt(at), isTrue);
    expect(slow.remainingAt(at), Duration.zero);
    expect(slow.canSendAt(at.add(const Duration(seconds: 1))), isTrue);
  });

  test('a message still sending holds the next send', () {
    const slow = SlowMode(interval: Duration(seconds: 30), pending: true);
    expect(slow.canSendAt(now), isFalse);
  });

  test('pending without slow mode holds nothing', () {
    const slow = SlowMode(pending: true);
    expect(slow.canSendAt(now), isTrue);
  });
}
