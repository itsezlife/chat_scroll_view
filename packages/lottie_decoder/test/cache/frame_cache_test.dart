import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:meta/meta.dart';

FrameCacheKey _key(String hash, {int size = 128}) => FrameCacheKey(
  contentHash: hash,
  width: size,
  height: size,
  engineVersion: '1.0.0',
);

/// [length] bytes, each [fill].
Uint8List _bytes(int length, int fill) =>
    Uint8List(length)..fillRange(0, length, fill);

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('frame_cache_test_');
  addTearDown(() {
    if (dir.existsSync()) {
      // A test may have made it read-only.
      if (!Platform.isWindows)
        Process.runSync('chmod', ['-R', '700', dir.path]);
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

/// The files of [dir] with [extension], by name.
List<String> _names(Directory dir, String extension) =>
    dir
        .listSync()
        .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .where((n) => n.endsWith(extension))
        .toList()
      ..sort();

/// Counts the files written through it.
class _CountingFiles extends FrameCacheFiles {
  _CountingFiles(super.directory);

  final List<String> written = [];

  @override
  Future<void> write(
    String stem,
    Uint8List bytes, {
    required DateTime modified,
  }) {
    written.add(stem);
    return super.write(stem, bytes, modified: modified);
  }
}

/// A process that dies after the temp file is complete and before the rename.
class _CrashingFiles extends FrameCacheFiles {
  _CrashingFiles(super.directory);

  @override
  @protected
  Future<void> publish(File temp, File target) =>
      Future<void>.error(const FileSystemException('killed before rename'));

  // A dead process cleans nothing up.
  @override
  @protected
  Future<void> discardTemp(File temp) async {}
}

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
          ramBudgetBytes: 130,
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

  group('disk tier', () {
    late Directory dir;
    late _CountingFiles files;
    late FrameCache cache;
    setUp(() {
      dir = _tempDir();
      files = _CountingFiles(dir);
      cache = FrameCache(directory: dir, files: files, clock: clock);
    });

    test('a complete animation is written once, as one file', () async {
      putAll(cache, _key('a'), 3, 10);
      await cache.dispose();
      expect(_names(dir, '.frames'), ['${_key('a').toFileStem()}.frames']);
      expect(files.written, [_key('a').toFileStem()]);
      expect(_names(dir, '.tmp'), isEmpty);
    });

    test(
      'putting a frame again after completion does not write again',
      () async {
        putAll(cache, _key('a'), 2, 10);
        putAll(cache, _key('a'), 2, 10);
        await cache.dispose();
        expect(files.written, hasLength(1));
      },
    );

    test('a partial animation is not written, and a restart misses', () async {
      cache.put(_key('a'), 0, _bytes(10, 1), frameCount: 3);
      cache.put(_key('a'), 2, _bytes(10, 3), frameCount: 3);
      await cache.dispose();
      expect(dir.listSync(), isEmpty);

      final restarted = FrameCache(directory: dir, clock: clock);
      addTearDown(restarted.dispose);
      expect(await restarted.open(_key('a')), isNull);
    });

    test(
      'a second cache on the directory serves the frames byte for byte',
      () async {
        final key = _key('a');
        putAll(cache, key, 3, 10);
        await cache.dispose();

        final second = FrameCache(directory: dir, clock: clock);
        addTearDown(second.dispose);
        expect(second.has(key, 0), isFalse, reason: 'not resident before open');
        expect(await second.open(key), 3);
        for (var i = 0; i < 3; i++) {
          expect(second.frame(key, i), _bytes(10, i + 1));
        }
      },
    );

    test('the file starts with the documented little-endian header', () async {
      final key = FrameCacheKey(
        contentHash: 'ab',
        width: 64,
        height: 32,
        engineVersion: '1.0.0',
      );
      putAll(cache, key, 2, 5);
      await cache.dispose();

      final bytes = File(
        '${dir.path}/${key.toFileStem()}.frames',
      ).readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      expect(bytes.sublist(0, 4), [0x46, 0x52, 0x4D, 0x43], reason: 'FRMC');
      expect(header.getUint32(4, Endian.little), 1, reason: 'format version');
      expect(header.getUint32(8, Endian.little), 64);
      expect(header.getUint32(12, Endian.little), 32);
      expect(header.getUint32(16, Endian.little), 2, reason: 'frame count');
      expect(header.getUint32(20, Endian.little), 10, reason: 'payload bytes');
      expect(header.getUint32(28, Endian.little), 5, reason: 'engine length');
      expect(header.getUint32(32, Endian.little), 2, reason: 'hash length');
      expect(String.fromCharCodes(bytes.sublist(36, 41)), '1.0.0');
      expect(String.fromCharCodes(bytes.sublist(41, 43)), 'ab');
      // Offsets (0, 5), lengths (5, 5), then the payload.
      expect(header.getUint32(43, Endian.little), 0);
      expect(header.getUint32(47, Endian.little), 5);
      expect(header.getUint32(51, Endian.little), 5);
      expect(header.getUint32(55, Endian.little), 5);
      expect(bytes.sublist(59), [...List.filled(5, 1), ...List.filled(5, 2)]);
      // CRC-32 of the ten payload bytes, from an independent implementation
      // (python zlib.crc32).
      expect(header.getUint32(24, Endian.little), 0xB5C783AF);
    });

    test('a crash between writing the temp file and the rename leaves no '
        'entry, and the leftover is never read as one', () async {
      final key = _key('a');
      final crashing = FrameCache(
        directory: dir,
        files: _CrashingFiles(dir),
        onError: (_, _) {},
        clock: clock,
      );
      putAll(crashing, key, 2, 10);
      await crashing.dispose();
      expect(_names(dir, '.frames'), isEmpty);
      expect(_names(dir, '.tmp'), isNotEmpty, reason: 'the crash left it');

      final restarted = FrameCache(directory: dir, clock: clock);
      addTearDown(restarted.dispose);
      expect(await restarted.open(key), isNull);
      expect(_names(dir, '.tmp'), isEmpty, reason: 'swept on the first scan');
    });
  });
}
