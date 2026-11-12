import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _short = Duration(milliseconds: 1500);
const _prolonged = Duration(milliseconds: 5000);

/// An undo bulletin that counts its callbacks.
final class _Undo {
  int undos = 0;
  int commits = 0;

  late final Bulletin bulletin = Bulletin(
    message: 'Stickers removed',
    action: BulletinAction.undo(
      onUndo: () => undos++,
      onCommit: () => commits++,
    ),
  );
}

void main() {
  late ManualBulletinClock clock;
  late BulletinController controller;

  setUp(() {
    clock = ManualBulletinClock();
    controller = BulletinController(
      policy: const BulletinPolicy.android(),
      clock: clock,
    );
  });

  tearDown(() => controller.dispose());

  Future<BulletinExit> exitOf(BulletinHandle handle) => handle.closed;

  group('one slot', () {
    test('show takes the slot and signals', () {
      var signals = 0;
      controller.current.addListener(() => signals++);
      final handle = controller.show(const Bulletin(message: 'Copied'));
      expect(controller.current.value, same(handle));
      expect(handle.isClosed, isFalse);
      expect(signals, 1);
    });

    test('a second show replaces the first', () async {
      final first = controller.show(const Bulletin(message: 'One'));
      final second = controller.show(const Bulletin(message: 'Two'));
      expect(controller.current.value, same(second));
      expect(first.isClosed, isTrue);
      expect(await exitOf(first), BulletinExit.replaced);
      expect(second.isClosed, isFalse);
    });

    test('closing empties the slot and signals', () {
      final handle = controller.show(const Bulletin(message: 'Copied'));
      var signals = 0;
      controller.current.addListener(() => signals++);
      handle.dismiss();
      expect(controller.current.value, isNull);
      expect(signals, 1);
    });

    test('closing a replaced handle leaves the current one', () {
      final first = controller.show(const Bulletin(message: 'One'));
      final second = controller.show(const Bulletin(message: 'Two'));
      first.dismiss();
      expect(controller.current.value, same(second));
      expect(second.isClosed, isFalse);
    });

    test('controller dismiss closes the current one', () async {
      final handle = controller.show(const Bulletin(message: 'Copied'));
      controller.dismiss();
      expect(await exitOf(handle), BulletinExit.dismissed);
      expect(controller.current.value, isNull);
    });
  });

  group('timer', () {
    test('starts when the view reports the bulletin entered', () async {
      final handle = controller.show(const Bulletin(message: 'Copied'));
      clock.advance(_short * 2);
      expect(handle.isClosed, isFalse);

      handle.markEntered();
      clock.advance(_short - const Duration(milliseconds: 1));
      expect(handle.isClosed, isFalse);
      clock.advance(const Duration(milliseconds: 1));
      expect(await exitOf(handle), BulletinExit.timedOut);
    });

    test('uses the policy timeout of the duration class', () {
      final handle = controller.show(
        Bulletin(
          message: 'Removed',
          action: BulletinAction.undo(onUndo: () {}),
        ),
      )..markEntered();
      expect(handle.timeout, _prolonged);
      clock.advance(_prolonged - const Duration(milliseconds: 1));
      expect(handle.isClosed, isFalse);
      clock.advance(const Duration(milliseconds: 1));
      expect(handle.exit, BulletinExit.timedOut);
    });

    test('an exact duration is used as given', () {
      final handle = controller.show(
        const Bulletin(
          message: 'Copied',
          duration: BulletinDuration.exactly(Duration(seconds: 4)),
        ),
      )..markEntered();
      clock.advance(const Duration(seconds: 4));
      expect(handle.exit, BulletinExit.timedOut);
    });

    test('until dismissed never times out', () {
      final handle = controller.show(
        const Bulletin(
          message: 'Copied',
          duration: BulletinDuration.untilDismissed,
        ),
      )..markEntered();
      clock.advance(const Duration(hours: 1));
      expect(handle.isClosed, isFalse);
      expect(handle.timeout, isNull);
      expect(handle.remaining, isNull);
    });

    test('a second markEntered does not restart the timer', () {
      final handle = controller.show(const Bulletin(message: 'Copied'))
        ..markEntered();
      clock.advance(const Duration(milliseconds: 1000));
      handle.markEntered();
      clock.advance(const Duration(milliseconds: 500));
      expect(handle.exit, BulletinExit.timedOut);
    });

    test('remaining is the full timeout before entering, then counts down', () {
      final handle = controller.show(const Bulletin(message: 'Copied'));
      expect(handle.remaining, _short);
      handle.markEntered();
      clock.advance(const Duration(milliseconds: 400));
      expect(handle.remaining, const Duration(milliseconds: 1100));
    });

    test('a replaced bulletin cancels its timer', () {
      controller.show(const Bulletin(message: 'One')).markEntered();
      controller.show(const Bulletin(message: 'Two'));
      expect(clock.pendingCount, 0);
    });
  });

  group('pause', () {
    test('holds the timer, and resume starts the whole timeout again', () {
      final handle = controller.show(const Bulletin(message: 'Copied'))
        ..markEntered();
      clock.advance(const Duration(milliseconds: 1000));
      handle.pause();
      expect(handle.isPaused, isTrue);
      clock.advance(const Duration(seconds: 10));
      expect(handle.isClosed, isFalse);
      expect(handle.remaining, _short);

      handle.resume();
      clock.advance(_short - const Duration(milliseconds: 1));
      expect(handle.isClosed, isFalse);
      clock.advance(const Duration(milliseconds: 1));
      expect(handle.exit, BulletinExit.timedOut);
    });

    test('before entering, the timer waits for both entering and resume', () {
      final handle = controller.show(const Bulletin(message: 'Copied'))
        ..pause()
        ..markEntered();
      clock.advance(const Duration(seconds: 10));
      expect(handle.isClosed, isFalse);
      handle.resume();
      clock.advance(_short);
      expect(handle.exit, BulletinExit.timedOut);
    });

    test('resume without a pause changes nothing', () {
      final handle = controller.show(const Bulletin(message: 'Copied'))
        ..markEntered();
      clock.advance(const Duration(milliseconds: 1000));
      handle.resume();
      clock.advance(const Duration(milliseconds: 500));
      expect(handle.exit, BulletinExit.timedOut);
    });
  });

  group('commit on leave', () {
    test('a timeout commits', () {
      final undo = _Undo();
      controller.show(undo.bulletin).markEntered();
      clock.advance(_prolonged);
      expect(undo.commits, 1);
      expect(undo.undos, 0);
    });

    test('a replacement commits', () {
      final undo = _Undo();
      controller
        ..show(undo.bulletin)
        ..show(const Bulletin(message: 'Copied'));
      expect(undo.commits, 1);
    });

    test('a dismissal commits', () {
      final undo = _Undo();
      controller.show(undo.bulletin).dismiss();
      expect(undo.commits, 1);
    });

    test('a swipe commits', () async {
      final undo = _Undo();
      final handle = controller.show(undo.bulletin)..swipeAway();
      expect(undo.commits, 1);
      expect(await exitOf(handle), BulletinExit.swiped);
    });

    test('the surface going commits', () async {
      final undo = _Undo();
      final handle = controller.show(undo.bulletin);
      controller.detach();
      expect(undo.commits, 1);
      expect(await exitOf(handle), BulletinExit.surfaceGone);
      expect(controller.current.value, isNull);
    });

    test('disposing the controller commits', () async {
      final undo = _Undo();
      final handle = controller.show(undo.bulletin);
      controller.dispose();
      expect(undo.commits, 1);
      expect(await exitOf(handle), BulletinExit.surfaceGone);
    });

    test('Undo undoes once and never commits', () async {
      final undo = _Undo();
      final handle = controller.show(undo.bulletin)
        ..markEntered()
        ..pressAction();
      expect(await exitOf(handle), BulletinExit.undone);
      handle
        ..pressAction()
        ..dismiss();
      controller.dispose();
      clock.advance(const Duration(minutes: 1));
      expect(undo.undos, 1);
      expect(undo.commits, 0);
    });

    test('every path commits exactly once', () {
      final undo = _Undo();
      final handle = controller.show(undo.bulletin)..markEntered();
      handle
        ..dismiss()
        ..swipeAway()
        ..pressAction();
      controller
        ..detach()
        ..dispose();
      clock.advance(const Duration(minutes: 1));
      expect(undo.commits, 1);
      expect(undo.undos, 0);
      expect(handle.exit, BulletinExit.dismissed);
    });

    test('an undo without a commit callback closes quietly', () async {
      var undos = 0;
      final handle = controller.show(
        Bulletin(
          message: 'Removed',
          action: BulletinAction.undo(onUndo: () => undos++),
        ),
      )..dismiss();
      expect(await exitOf(handle), BulletinExit.dismissed);
      expect(undos, 0);
    });
  });

  group('button action', () {
    test('pressing runs it once and closes', () async {
      var presses = 0;
      final handle = controller.show(
        Bulletin(
          message: 'Saved',
          action: BulletinAction.button(
            label: 'View',
            onPressed: () => presses++,
          ),
        ),
      )..pressAction();
      handle.pressAction();
      expect(presses, 1);
      expect(await exitOf(handle), BulletinExit.actionPressed);
    });

    test('pressing a bulletin with no action does nothing', () {
      final handle = controller.show(const Bulletin(message: 'Copied'))
        ..pressAction();
      expect(handle.isClosed, isFalse);
    });
  });

  group('callbacks that throw', () {
    late FlutterExceptionHandler? previous;
    final reported = <FlutterErrorDetails>[];

    setUp(() {
      previous = FlutterError.onError;
      FlutterError.onError = reported.add;
    });

    tearDown(() {
      FlutterError.onError = previous;
      reported.clear();
    });

    test('a throwing commit is reported and the bulletin still closes', () {
      final handle = controller.show(
        Bulletin(
          message: 'Removed',
          action: BulletinAction.undo(
            onUndo: () {},
            onCommit: () => throw StateError('commit'),
          ),
        ),
      )..dismiss();
      expect(handle.exit, BulletinExit.dismissed);
      expect(controller.current.value, isNull);
      expect(reported, hasLength(1));
      expect(reported.single.library, 'bulletins');
    });
  });

  test('BulletinExit commits on every exit but undone', () {
    expect(BulletinExit.values.where((e) => !e.commits), [BulletinExit.undone]);
  });

  group('disposal', () {
    test('show after dispose closes at once as surface gone and commits', () {
      controller.dispose();
      final undo = _Undo();
      final handle = controller.show(undo.bulletin);
      expect(handle.exit, BulletinExit.surfaceGone);
      expect(undo.commits, 1);
      expect(controller.current.value, isNull);
    });

    test('is idempotent', () {
      controller
        ..dispose()
        ..dispose();
      expect(controller.isDisposed, isTrue);
    });
  });
}
