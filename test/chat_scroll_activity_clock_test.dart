import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_activity.dart';
import 'package:flutter_test/flutter_test.dart';

const ChatScrollActivityTiming _timing = ChatScrollActivityTiming();

/// Runs [body] against a fresh clock and disposes it inside the test body —
/// pending timers and active tickers are checked before `tearDown` runs.
void _clockTest(
  String description,
  Future<void> Function(
    WidgetTester tester,
    ChatScrollActivityClock clock,
    int Function() changes,
  )
  body, {
  ChatScrollActivityTiming timing = _timing,
}) {
  testWidgets(description, (tester) async {
    var changes = 0;
    final clock = ChatScrollActivityClock(
      timing: timing,
      onChanged: () => changes++,
    );
    try {
      await body(tester, clock, () => changes);
    } finally {
      clock.dispose();
    }
  });
}

Future<void> _shown(WidgetTester tester, ChatScrollActivityClock clock) async {
  clock.hold();
  await tester.pump();
  await tester.pump(_timing.fadeIn);
}

void main() {
  group('ChatScrollActivityClock', () {
    _clockTest('starts idle', (tester, clock, changes) async {
      expect(clock.value, 0);
    });

    _clockTest('hold eases in along a sine over fadeIn', (
      tester,
      clock,
      changes,
    ) async {
      clock.hold();
      expect(clock.value, 0, reason: 'never changes synchronously');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(clock.value, closeTo(0.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 25));
      expect(clock.value, closeTo(0.75, 1e-9), reason: '(1 - cos(2π/3)) / 2');
      await tester.pump(const Duration(milliseconds: 50));
      expect(clock.value, 1);
      expect(changes(), greaterThan(0));
    });

    _clockTest('release holds for idleDelay, then fades out', (
      tester,
      clock,
      changes,
    ) async {
      await _shown(tester, clock);
      clock.release();

      await tester.pump(const Duration(milliseconds: 499));
      expect(clock.value, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 75));
      expect(clock.value, closeTo(0.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 75));
      expect(clock.value, 0);
    });

    _clockTest('hold during the idle delay cancels the hide', (
      tester,
      clock,
      changes,
    ) async {
      await _shown(tester, clock);
      clock.release();
      await tester.pump(const Duration(milliseconds: 300));
      clock.hold();
      await tester.pump(const Duration(seconds: 2));
      expect(clock.value, 1);
    });

    _clockTest('hold mid-fade-out reverses from the current value', (
      tester,
      clock,
      changes,
    ) async {
      await _shown(tester, clock);
      clock.release();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 75));
      final mid = clock.value;
      expect(mid, closeTo(0.5, 1e-9));

      clock.hold();
      await tester.pump();
      expect(clock.value, closeTo(mid, 1e-9));
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 1);
    });

    _clockTest('pulse shows, then hides navigationIdleDelay after the pulse', (
      tester,
      clock,
      changes,
    ) async {
      clock.pulse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 1);

      await tester.pump(const Duration(milliseconds: 849));
      expect(clock.value, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 0);
    });

    _clockTest('a release after a navigation hold waits the navigation delay', (
      tester,
      clock,
      changes,
    ) async {
      clock.hold(navigation: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      clock.release();
      await tester.pump(const Duration(milliseconds: 999));
      expect(clock.value, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 0);
    });

    _clockTest('pulse while holding does not schedule a hide', (
      tester,
      clock,
      changes,
    ) async {
      clock.hold();
      await tester.pump();
      clock.pulse();
      await tester.pump(const Duration(seconds: 3));
      expect(clock.value, 1);
    });

    _clockTest('non-navigation pulse hides idleDelay after the pulse', (
      tester,
      clock,
      changes,
    ) async {
      clock.pulse(navigation: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 349));
      expect(clock.value, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 0);
    });

    _clockTest('hide skips a pending delay and fades out now', (
      tester,
      clock,
      changes,
    ) async {
      clock.pulse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 1);

      clock.hide();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(clock.value, closeTo(0.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 75));
      expect(clock.value, 0);
    });

    _clockTest('hide mid-fade-in reverses from the current value', (
      tester,
      clock,
      changes,
    ) async {
      clock.pulse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final mid = clock.value;
      clock.hide();
      await tester.pump();
      expect(clock.value, closeTo(mid, 1e-9));
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 0);
    });

    _clockTest('hide is a no-op while a hold is active', (
      tester,
      clock,
      changes,
    ) async {
      await _shown(tester, clock);
      clock.hide();
      await tester.pump(const Duration(seconds: 3));
      expect(clock.value, 1);
    });

    _clockTest('hide is a no-op while pinned', (tester, clock, changes) async {
      clock.pinned = true;
      clock.hide();
      await tester.pump(const Duration(seconds: 3));
      expect(clock.value, 1);
    });

    _clockTest('a release after hide waits the idle delay again', (
      tester,
      clock,
      changes,
    ) async {
      clock.pulse();
      await tester.pump();
      clock.hide();
      await tester.pump(const Duration(milliseconds: 200));
      expect(clock.value, 0);

      clock.hold();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      clock.release();
      await tester.pump(const Duration(milliseconds: 499));
      expect(clock.value, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 0);
    });

    _clockTest('reports a pending hide that waits out a navigation delay', (
      tester,
      clock,
      changes,
    ) async {
      expect(clock.isNavigationHidePending, isFalse);
      clock.pulse();
      expect(clock.isNavigationHidePending, isTrue);
      clock.pulse(navigation: false);
      expect(clock.isNavigationHidePending, isFalse);

      clock.hold(navigation: true);
      expect(clock.isNavigationHidePending, isFalse, reason: 'held, none');
      clock.release();
      expect(clock.isNavigationHidePending, isTrue);
      await tester.pump(_timing.navigationIdleDelay);
      expect(clock.isNavigationHidePending, isFalse, reason: 'fired');
      await tester.pump(_timing.fadeOut);

      clock.pulse();
      clock.hide();
      expect(clock.isNavigationHidePending, isFalse, reason: 'cancelled');
      await tester.pump(_timing.fadeOut);
    });

    _clockTest('pinned snaps to 1 without notifying and never hides', (
      tester,
      clock,
      changes,
    ) async {
      clock.pinned = true;
      expect(clock.value, 1);
      expect(changes(), 0);
      clock.release();
      await tester.pump(const Duration(seconds: 3));
      expect(clock.value, 1);
    });

    _clockTest('pinning mid-fade-out stops the fade at 1', (
      tester,
      clock,
      changes,
    ) async {
      await _shown(tester, clock);
      clock.release();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 75));
      clock.pinned = true;
      expect(clock.value, 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 1);
    });

    _clockTest('unpinning waits idleDelay, then fades out', (
      tester,
      clock,
      changes,
    ) async {
      clock.pinned = true;
      clock.pinned = false;
      await tester.pump(const Duration(milliseconds: 499));
      expect(clock.value, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(clock.value, 0);
    });

    _clockTest('unpinning while holding waits for release', (
      tester,
      clock,
      changes,
    ) async {
      clock.hold();
      clock.pinned = true;
      clock.pinned = false;
      await tester.pump(const Duration(seconds: 3));
      expect(clock.value, 1);
    });

    _clockTest(
      'zero durations snap on the next frame',
      (tester, clock, changes) async {
        clock.hold();
        await tester.pump();
        expect(clock.value, 1);
        clock.release();
        await tester.pump(Duration.zero);
        expect(clock.value, 0);
      },
      timing: const ChatScrollActivityTiming(
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
        idleDelay: Duration.zero,
      ),
    );

    testWidgets('a clock started shown pulses without a fade-in', (
      tester,
    ) async {
      var changes = 0;
      final clock = ChatScrollActivityClock(
        timing: _timing,
        onChanged: () => changes++,
        initialValue: 1,
      );
      try {
        expect(clock.value, 1);
        clock.pulse(navigation: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 499));
        expect(clock.value, 1);
        expect(changes, 0, reason: 'already at 1: nothing to fade');
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 150));
        expect(clock.value, 0);
      } finally {
        clock.dispose();
      }
    });

    _clockTest('dispose cancels a pending hide', (
      tester,
      clock,
      changes,
    ) async {
      clock.hold();
      await tester.pump();
      clock.release();
      // _clockTest disposes; a leaked Timer would fail the test.
    });
  });
}
