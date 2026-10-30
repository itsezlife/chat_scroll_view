import 'package:flutter_test/flutter_test.dart';

import '../../tool/chat_perf/cooldown.dart';
import '../../tool/chat_perf/device_lock.dart';
import '../../tool/chat_perf/launch_retry.dart';

final class _MemoryLocks implements LockStore {
  final held = <String, String>{};

  @override
  bool tryCreate(String key, String owner) {
    if (held.containsKey(key)) return false;
    held[key] = owner;
    return true;
  }

  @override
  String? owner(String key) => held[key];

  @override
  void delete(String key) => held.remove(key);
}

void main() {
  group('DeviceLock', () {
    test('a second run on the same device reports the holder', () {
      final store = _MemoryLocks();
      final first = DeviceLock.acquire(store, 'R5', owner: 'pid 1');
      expect(
        () => DeviceLock.acquire(store, 'R5', owner: 'pid 2'),
        throwsA(
          isA<DeviceLockedException>().having(
            (e) => e.message,
            'message',
            allOf(contains('R5'), contains('pid 1')),
          ),
        ),
      );
      first.release();
      expect(DeviceLock.acquire(store, 'R5', owner: 'pid 2'), isNotNull);
    });

    test('a different device is not blocked', () {
      final store = _MemoryLocks();
      DeviceLock.acquire(store, 'A', owner: 'x');
      expect(DeviceLock.acquire(store, 'B', owner: 'y'), isNotNull);
    });
  });

  group('runWithRetry', () {
    test('a clean launch runs once', () async {
      var launches = 0;
      final r = await runWithRetry<int>(
        launch: () async => ++launches,
        foreignInstall: () async => false,
      );
      expect(r.value, 1);
      expect(r.discarded, 0);
    });

    test('a foreign install discards the launch and retries once', () async {
      var launches = 0;
      final foreign = [true, false];
      final r = await runWithRetry<int>(
        launch: () async => ++launches,
        foreignInstall: () async => foreign.removeAt(0),
      );
      expect(r.value, 2);
      expect(r.discarded, 1);
    });

    test('a second foreign install fails the run with that reason', () {
      expect(
        runWithRetry<int>(
          launch: () async => 0,
          foreignInstall: () async => true,
        ),
        throwsA(
          isA<ForeignInstallException>().having(
            (e) => e.message,
            'message',
            contains('replaced'),
          ),
        ),
      );
    });
  });

  group('foreign install signature', () {
    const own = 'I PackageManager: Replacing package:com.x.app';

    test('one install event is the runner own; more is foreign', () {
      expect(countInstallEvents([own, 'unrelated'], 'com.x.app'), 1);
      expect(hasForeignInstall([own, own], 'com.x.app'), isTrue);
      expect(hasForeignInstall([own], 'com.x.app'), isFalse);
      expect(hasForeignInstall([own], 'com.other'), isFalse);
    });
  });

  group('waitForCooldown', () {
    test('returns once within 2 C of the start', () async {
      final temps = [38.0, 36.5, 35.0].iterator;
      var slept = 0;
      final r = await waitForCooldown(
        startTempC: 34,
        readTempC: () async => temps.moveNext() ? temps.current : 34,
        sleep: (_) async => slept++,
        bound: const Duration(minutes: 5),
        interval: const Duration(seconds: 30),
      );
      expect(r.boundHit, isFalse);
      expect(r.endTempC, 35.0);
      expect(slept, 2);
    });

    test('records when the bound is hit', () async {
      var slept = Duration.zero;
      final r = await waitForCooldown(
        startTempC: 34,
        readTempC: () async => 40,
        sleep: (d) async => slept += d,
        bound: const Duration(minutes: 2),
        interval: const Duration(seconds: 30),
      );
      expect(r.boundHit, isTrue);
      expect(slept, const Duration(minutes: 2));
    });
  });
}
