import 'package:meta/meta.dart';

/// The slow mode group of the chat capabilities: one send unit per
/// [interval], an album counting as one unit.
///
/// The host passes [SlowMode.none] for users it exempts (admins, a bypass the
/// user earned). The value holds no clock: a consumer asks [canSendAt] with
/// its own `now`, so a countdown ticks without a new value.
@immutable
final class SlowMode {
  /// A slow mode; with no [interval] it is [none].
  const SlowMode({
    this.interval = Duration.zero,
    this.nextSendAt,
    this.pending = false,
  });

  /// No slow mode: the user may send at any time.
  static const none = SlowMode();

  /// The time between two send units; zero when there is no slow mode.
  final Duration interval;

  /// When the user may send next; null when the user may send now.
  final DateTime? nextSendAt;

  /// Whether a message of the user's is still sending, which holds the next
  /// send until it settles.
  final bool pending;

  /// Whether a slow mode applies.
  bool get isActive => interval > Duration.zero;

  /// Whether the user may send a unit at [now].
  ///
  /// The next send time itself is allowed. Without a slow mode nothing
  /// holds a send, [pending] included.
  bool canSendAt(DateTime now) {
    if (!isActive) return true;
    if (pending) return false;
    return switch (nextSendAt) {
      final next? => !now.isBefore(next),
      null => true,
    };
  }

  /// How long the user waits at [now] for the next send time; zero when the
  /// time has come or there is none.
  ///
  /// [pending] is not a wait of known length, so it is not counted here.
  Duration remainingAt(DateTime now) => switch (nextSendAt) {
    final next? when isActive && now.isBefore(next) => next.difference(now),
    _ => Duration.zero,
  };

  /// A copy with the given fields replaced; [clearNextSendAt] makes the next
  /// send free.
  SlowMode copyWith({
    Duration? interval,
    DateTime? nextSendAt,
    bool clearNextSendAt = false,
    bool? pending,
  }) => SlowMode(
    interval: interval ?? this.interval,
    nextSendAt: clearNextSendAt ? null : nextSendAt ?? this.nextSendAt,
    pending: pending ?? this.pending,
  );

  @override
  bool operator ==(Object other) =>
      other is SlowMode &&
      other.interval == interval &&
      other.nextSendAt == nextSendAt &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(interval, nextSendAt, pending);

  @override
  String toString() =>
      'SlowMode(interval: $interval, nextSendAt: $nextSendAt, '
      'pending: $pending)';
}
