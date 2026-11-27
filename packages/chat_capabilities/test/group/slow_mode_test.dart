import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);

  test('no slow mode lets the user send at any time', () {
    expect(SlowMode.none.isActive, isFalse);
    expect(SlowMode.none.canSendAt(now), isTrue);
    expect(SlowMode.none.remainingAt(now), Duration.zero);
  });

  test('a free slow mode lets the user send', () {
    const slow = SlowMode.active(interval: Duration(seconds: 30));
    expect(slow.isActive, isTrue);
    expect(slow.canSendAt(now), isTrue);
    expect(slow.remainingAt(now), Duration.zero);
  });

  test('waits until the next send time, which is itself allowed', () {
    final slow = SlowMode.active(
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
    const slow = SlowMode.active(
      interval: Duration(seconds: 30),
      pending: true,
    );
    expect(slow.canSendAt(now), isFalse);
    expect(slow.remainingAt(now), Duration.zero);
  });

  test('the two forms are told apart by a switch and equal by value', () {
    String describe(SlowMode slow) => switch (slow) {
      SlowMode$None() => 'none',
      SlowMode$Active(:final interval, :final pending) =>
        '${interval.inSeconds}s pending=$pending',
    };
    expect(describe(SlowMode.none), 'none');
    expect(
      describe(const SlowMode.active(interval: Duration(seconds: 5))),
      '5s pending=false',
    );
    expect(
      SlowMode.active(interval: const Duration(seconds: 5), nextSendAt: now),
      SlowMode.active(
        interval: const Duration(seconds: 5),
        nextSendAt: DateTime.utc(2026, 11, 27, 12),
      ),
    );
    expect(
      const SlowMode.active(interval: Duration(seconds: 5)),
      isNot(SlowMode.none),
    );
  });

  test('copyWith of an active slow mode replaces or clears its wait', () {
    final slow = SlowMode$Active(
      interval: const Duration(seconds: 30),
      nextSendAt: now,
    );
    expect(slow.copyWith(pending: true).pending, isTrue);
    expect(slow.copyWith(pending: true).nextSendAt, now);
    expect(slow.copyWith(clearNextSendAt: true).nextSendAt, isNull);
  });
}
