import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

FrameCacheKey _key(String hash, {int size = 128}) => FrameCacheKey(
  contentHash: hash,
  width: size,
  height: size,
  engineVersion: '1.0.0',
);

/// [length] bytes, each [fill].
Uint8List _bytes(int length, int fill) =>
    Uint8List(length)..fillRange(0, length, fill);

void main() {
  late DateTime now;
  DateTime clock() => now;
  void advance() => now = now.add(const Duration(seconds: 1));

  setUp(() => now = DateTime.utc(2026, 11, 6));

  /// Puts every frame of an animation of [count] frames of [length] bytes.
  void putAll(FrameCache cache, FrameCacheKey key, int count, int length) {
    for (var i = 0; i < count; i++) {
      cache.put(key, i, _bytes(length, i + 1), frameCount: count);
    }
  }

  group('memory only', () {
    late FrameCache cache;
    setUp(() => cache = FrameCache(directory: null, clock: clock));
    tearDown(() => cache.dispose());

    test('a frame put is had and read back byte for byte', () {
      final key = _key('a');
      cache.put(key, 1, _bytes(4, 7), frameCount: 3);
      expect(cache.has(key, 1), isTrue);
      expect(cache.has(key, 0), isFalse);
      expect(cache.frame(key, 1), _bytes(4, 7));
      expect(cache.frame(key, 0), isNull);
    });

    test('an unknown animation is a miss', () async {
      expect(cache.has(_key('a'), 0), isFalse);
      expect(cache.frame(_key('a'), 0), isNull);
      expect(await cache.open(_key('a')), isNull);
    });

    test('open reports the frame count of what was put', () async {
      cache.put(_key('a'), 0, _bytes(2, 1), frameCount: 5);
      expect(await cache.open(_key('a')), 5);
    });

    test('the first write of a frame wins', () {
      final key = _key('a');
      cache.put(key, 0, _bytes(2, 1), frameCount: 1);
      cache.put(key, 0, _bytes(2, 9), frameCount: 1);
      expect(cache.frame(key, 0), _bytes(2, 1));
    });

    test('a key above the display cap is rejected, not cached', () async {
      final big = _key('a', size: 513);
      expect(
        () => cache.put(big, 0, _bytes(2, 1), frameCount: 1),
        throwsArgumentError,
      );
      expect(cache.has(big, 0), isFalse);
      expect(await cache.open(big), isNull);
    });

    test(
      'a frame count that disagrees with the earlier one is a StateError',
      () {
        cache.put(_key('a'), 0, _bytes(2, 1), frameCount: 3);
        expect(
          () => cache.put(_key('a'), 1, _bytes(2, 1), frameCount: 4),
          throwsStateError,
        );
      },
    );

    test(
      'an index outside the frame count, or an empty count, is rejected',
      () {
        expect(
          () => cache.put(_key('a'), 3, _bytes(2, 1), frameCount: 3),
          throwsRangeError,
        );
        expect(
          () => cache.put(_key('b'), 0, _bytes(2, 1), frameCount: 0),
          throwsArgumentError,
        );
      },
    );
  });

  group('RAM tier', () {
    test(
      'evicts the least recently used animation, whole, over the budget',
      () {
        final cache = FrameCache(
          directory: null,
          ramBudgetBytes: 100,
          clock: clock,
        );
        putAll(cache, _key('a'), 2, 30);
        advance();
        putAll(cache, _key('b'), 2, 30);
        expect(cache.has(_key('a'), 0), isTrue);
        expect(cache.has(_key('b'), 0), isTrue);

        advance();
        cache.frame(_key('a'), 0); // a is now more recent than b
        advance();
        putAll(cache, _key('c'), 2, 30);

        expect(cache.has(_key('b'), 0), isFalse, reason: 'least recent');
        expect(cache.has(_key('b'), 1), isFalse, reason: 'evicted whole');
        expect(cache.has(_key('a'), 0), isTrue);
        expect(cache.has(_key('c'), 1), isTrue);
      },
    );

    test('never evicts the animation being filled when it is the only one', () {
      final cache = FrameCache(
        directory: null,
        ramBudgetBytes: 50,
        clock: clock,
      );
      putAll(cache, _key('a'), 3, 40);
      for (var i = 0; i < 3; i++) {
        expect(cache.has(_key('a'), i), isTrue);
      }
    });

    test('a filling animation survives pressure from older ones', () {
      final cache = FrameCache(
        directory: null,
        ramBudgetBytes: 100,
        clock: clock,
      );
      putAll(cache, _key('old'), 1, 60);
      advance();
      cache.put(_key('new'), 0, _bytes(60, 1), frameCount: 2);
      expect(cache.has(_key('old'), 0), isFalse);
      expect(cache.has(_key('new'), 0), isTrue);
    });
  });
}
