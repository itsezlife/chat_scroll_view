import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';

void main() {
  final key = FrameCacheKey(
    contentHash: 'abc',
    width: 48,
    height: 48,
    engineVersion: '1.0.0',
  );

  group('LottieSource', () {
    test('is a value: the same handle, key and frame count are equal', () {
      final a = LottieSource(
        const LottieHandle(1),
        cacheKey: key,
        frameCount: 60,
      );
      final b = LottieSource(
        const LottieHandle(1),
        cacheKey: key,
        frameCount: 60,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs by handle, key and frame count', () {
      final base = LottieSource(
        const LottieHandle(1),
        cacheKey: key,
        frameCount: 60,
      );

      expect(
        base,
        isNot(
          LottieSource(const LottieHandle(2), cacheKey: key, frameCount: 60),
        ),
      );
      expect(base, isNot(LottieSource(const LottieHandle(1), frameCount: 60)));
      expect(
        base,
        isNot(
          LottieSource(const LottieHandle(1), cacheKey: key, frameCount: 61),
        ),
      );
    });

    test('has no key unless given one: it is not cached', () {
      expect(
        LottieSource(const LottieHandle(1), frameCount: 10).cacheKey,
        isNull,
      );
    });
  });
}
