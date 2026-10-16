import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';

void main() {
  late ManualPanelClock clock;
  late List<String> log;

  setUp(() {
    clock = ManualPanelClock();
    log = [];
  });

  test('runs a timer only once its delay has been advanced', () {
    clock.after(const Duration(milliseconds: 300), () => log.add('a'));

    clock.advance(const Duration(milliseconds: 299));
    expect(log, isEmpty);

    clock.advance(const Duration(milliseconds: 1));
    expect(log, ['a']);
    expect(clock.pendingCount, 0);
  });

  test('runs timers in due order and ties in scheduling order', () {
    clock
      ..after(const Duration(seconds: 2), () => log.add('late'))
      ..after(const Duration(seconds: 1), () => log.add('first'))
      ..after(const Duration(seconds: 1), () => log.add('second'));

    clock.advance(const Duration(seconds: 3));

    expect(log, ['first', 'second', 'late']);
  });

  test('does not run a cancelled timer', () {
    final timer = clock.after(const Duration(seconds: 1), () => log.add('a'));
    timer.cancel();
    timer.cancel();

    clock.advance(const Duration(seconds: 5));

    expect(log, isEmpty);
    expect(clock.pendingCount, 0);
  });

  test('runs a timer scheduled by a callback when it falls due', () {
    clock.after(const Duration(seconds: 1), () {
      log.add('outer');
      clock.after(const Duration(seconds: 1), () => log.add('inner'));
    });

    clock.advance(const Duration(milliseconds: 1500));
    expect(log, ['outer']);

    clock.advance(const Duration(milliseconds: 500));
    expect(log, ['outer', 'inner']);
  });

  test('a timer scheduled during an advance is measured from its due time', () {
    clock.after(const Duration(seconds: 1), () {
      clock.after(const Duration(seconds: 1), () => log.add('inner'));
    });

    clock.advance(const Duration(seconds: 3));

    expect(log, ['inner']);
    expect(clock.elapsed, const Duration(seconds: 3));
  });

  test('the system clock runs its callback', () async {
    var ran = false;
    PanelClock.system.after(Duration.zero, () => ran = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(ran, isTrue);
  });

  test('the system clock does not run a cancelled callback', () async {
    var ran = false;
    PanelClock.system.after(Duration.zero, () => ran = true).cancel();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(ran, isFalse);
  });
}
