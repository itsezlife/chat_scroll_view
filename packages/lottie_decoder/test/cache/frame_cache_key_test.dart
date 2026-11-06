import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

FrameCacheKey _key({
  String hash = 'abc123',
  int width = 128,
  int height = 128,
  String engine = '1.2.0',
}) => FrameCacheKey(
  contentHash: hash,
  width: width,
  height: height,
  engineVersion: engine,
);

void main() {
  group('equality', () {
    test('keys with the same parts are equal and hash alike', () {
      expect(_key(), _key());
      expect(_key().hashCode, _key().hashCode);
    });

    test('each part tells keys apart', () {
      expect(_key(), isNot(_key(hash: 'abc124')));
      expect(_key(), isNot(_key(width: 64)));
      expect(_key(), isNot(_key(height: 64)));
      expect(_key(), isNot(_key(engine: '1.3.0')));
    });

    test('letter case is normalised, so case-insensitive disks cannot alias '
        'two keys', () {
      expect(
        _key(hash: 'ABC123', engine: 'V1'),
        _key(hash: 'abc123', engine: 'v1'),
      );
    });
  });

  group('toFileStem', () {
    test('spells the content, the display size and the engine', () {
      expect(_key().toFileStem(), 'abc123_128x128_1.2.0');
    });

    test('is distinct for distinct keys', () {
      final stems = {
        _key().toFileStem(),
        _key(width: 64).toFileStem(),
        _key(height: 64).toFileStem(),
        _key(hash: 'abd').toFileStem(),
        _key(engine: '2').toFileStem(),
      };
      expect(stems, hasLength(5));
    });

    test('a hash or engine version with path characters is rejected', () {
      for (final bad in ['', 'a/b', r'a\b', '..', 'a b', 'a_b', 'a\u0000b']) {
        expect(
          () => _key(hash: bad),
          throwsArgumentError,
          reason: 'hash "$bad"',
        );
      }
      for (final bad in ['', 'a/b', '..', '.hidden', 'a_b', 'v 1']) {
        expect(
          () => _key(engine: bad),
          throwsArgumentError,
          reason: 'engine "$bad"',
        );
      }
    });

    test('a negative size is rejected', () {
      expect(() => _key(width: -1), throwsArgumentError);
      expect(() => _key(height: -1), throwsArgumentError);
    });
  });

  group('admitted', () {
    test('both edges from 1 to 512 are cacheable', () {
      expect(_key(width: 1, height: 1).admitted(), isTrue);
      expect(_key(width: 512, height: 512).admitted(), isTrue);
      expect(_key(width: 512, height: 7).admitted(), isTrue);
    });

    test('an edge above the cap, or empty, is not', () {
      expect(_key(width: 513, height: 64).admitted(), isFalse);
      expect(_key(width: 64, height: 513).admitted(), isFalse);
      expect(_key(width: 0, height: 64).admitted(), isFalse);
      expect(_key(width: 64, height: 0).admitted(), isFalse);
    });

    test('the cap is a parameter', () {
      expect(_key(width: 256, height: 256).admitted(256), isTrue);
      expect(_key(width: 257, height: 256).admitted(256), isFalse);
    });
  });
}
