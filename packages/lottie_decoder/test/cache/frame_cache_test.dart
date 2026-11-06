import 'dart:async';
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

/// Counts the files written and read through it, and lets a test wait for the
/// n-th write to be on disk without sleeping.
class _CountingFiles extends FrameCacheFiles {
  _CountingFiles(super.directory);

  final List<String> written = [];
  final List<String> reads = [];
  final List<(int, Completer<void>)> _waiters = [];

  /// Completes once [count] writes have finished.
  Future<void> writes(int count) {
    if (written.length >= count) return Future.value();
    final waiter = Completer<void>();
    _waiters.add((count, waiter));
    return waiter.future;
  }

  @override
  Future<FileSystemException?> write(
    String stem,
    Uint8List bytes, {
    required DateTime modified,
  }) async {
    final stampFailure = await super.write(stem, bytes, modified: modified);
    written.add(stem);
    for (final (count, waiter) in _waiters.toList()) {
      if (written.length >= count) {
        _waiters.remove((count, waiter));
        waiter.complete();
      }
    }
    return stampFailure;
  }

  @override
  Future<Uint8List?> read(String stem, {required int maxBytes}) {
    reads.add(stem);
    return super.read(stem, maxBytes: maxBytes);
  }
}

/// Files whose timestamps cannot be set (a file system without them).
class _UnstampableFiles extends FrameCacheFiles {
  _UnstampableFiles(super.directory);

  @override
  @protected
  Future<void> stamp(File target, DateTime modified) =>
      Future<void>.error(const FileSystemException('no timestamps here'));
}

/// Records the temp file of every write before it is published.
class _TempRecordingFiles extends FrameCacheFiles {
  _TempRecordingFiles(super.directory, this.temps);

  final List<String> temps;

  @override
  @protected
  Future<void> publish(File temp, File target) {
    temps.add(temp.uri.pathSegments.last);
    return super.publish(temp, target);
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

  group('damaged files', () {
    late Directory dir;
    final key = _key('a');
    late File file;
    late List<Object> reported;

    /// A valid file for [key], then [damage] applied to its bytes.
    Future<void> writeThenDamage(
      Uint8List Function(Uint8List bytes) damage,
    ) async {
      dir = _tempDir();
      final writer = FrameCache(directory: dir, clock: clock);
      putAll(writer, key, 3, 10);
      await writer.dispose();
      file = File('${dir.path}/${key.toFileStem()}.frames');
      file.writeAsBytesSync(damage(file.readAsBytesSync()));
    }

    /// Where the offsets table starts for [key]: after the fixed header, the
    /// engine version "1.0.0" and the hash "a".
    const tablesStart = 36 + 5 + 1;

    Uint8List patch(Uint8List bytes, void Function(ByteData data) edit) {
      edit(ByteData.sublistView(bytes));
      return bytes;
    }

    final damages = <String, Uint8List Function(Uint8List)>{
      'empty': (b) => Uint8List(0),
      'truncated inside the header': (b) => b.sublist(0, 20),
      'truncated inside the payload': (b) => b.sublist(0, b.length - 3),
      'longer than it says': (b) => Uint8List.fromList([...b, 0]),
      'bad magic': (b) => patch(b, (d) => d.setUint8(0, 0)),
      'another format version': (b) =>
          patch(b, (d) => d.setUint32(4, 2, Endian.little)),
      'payload bit flipped': (b) =>
          patch(b, (d) => d.setUint8(b.length - 1, 0xFF)),
      'wrong CRC': (b) => patch(b, (d) => d.setUint32(24, 0, Endian.little)),
      'impossible frame count': (b) =>
          patch(b, (d) => d.setUint32(16, 0xFFFFFFFF, Endian.little)),
      'zero frame count': (b) =>
          patch(b, (d) => d.setUint32(16, 0, Endian.little)),
      'impossible engine length': (b) =>
          patch(b, (d) => d.setUint32(28, 0xFFFFFFFF, Endian.little)),
      'offset past the payload': (b) => patch(
        b,
        (d) => d.setUint32(tablesStart + 4, 0xFFFFFFF0, Endian.little),
      ),
      'offsets that do not tile': (b) =>
          patch(b, (d) => d.setUint32(tablesStart + 4, 3, Endian.little)),
      'a length past the payload': (b) => patch(
        b,
        (d) => d.setUint32(tablesStart + 3 * 4, 0xFFFFFFF0, Endian.little),
      ),
    };

    for (final MapEntry(key: name, value: damage) in damages.entries) {
      test('$name is a miss, deleted, and not an error', () async {
        reported = [];
        await writeThenDamage(damage);
        final cache = FrameCache(
          directory: dir,
          clock: clock,
          onError: (e, _) => reported.add(e),
        );
        addTearDown(cache.dispose);

        expect(await cache.open(key), isNull);
        expect(file.existsSync(), isFalse, reason: 'removed');
        expect(reported, isEmpty);
      });
    }

    test('a file renamed onto another key is not served as that key', () async {
      await writeThenDamage((b) => b);
      for (final other in [
        _key('a', size: 64), // another display size
        _key('b'), // another content
        FrameCacheKey(
          contentHash: 'a',
          width: 128,
          height: 128,
          engineVersion: '2.0.0',
        ), // another engine
      ]) {
        final copy = File('${dir.path}/${other.toFileStem()}.frames')
          ..writeAsBytesSync(file.readAsBytesSync());
        final cache = FrameCache(directory: dir, clock: clock);
        addTearDown(cache.dispose);
        expect(await cache.open(other), isNull, reason: '$other');
        expect(copy.existsSync(), isFalse);
      }
      expect(file.existsSync(), isTrue, reason: 'the genuine file stays');
    });

    test('after a miss the animation can be cached again', () async {
      await writeThenDamage((b) => b.sublist(0, 30));
      final again = FrameCache(directory: dir, clock: clock);
      expect(await again.open(key), isNull);
      putAll(again, key, 3, 10);
      await again.dispose();

      final third = FrameCache(directory: dir, clock: clock);
      addTearDown(third.dispose);
      expect(await third.open(key), 3);
      expect(third.frame(key, 2), _bytes(10, 3));
    });
  });

  group('disk budget', () {
    late Directory dir;
    late _CountingFiles files;

    /// The size of the file of an animation of three 10-byte frames under a
    /// one-letter hash.
    const fileBytes = 36 + 5 + 1 + 3 * 8 + 30;

    FrameCache build({required int budget, _CountingFiles? with_}) {
      files = with_ ?? _CountingFiles(dir);
      final cache = FrameCache(
        directory: dir,
        files: files,
        diskBudgetBytes: budget,
        clock: clock,
      );
      addTearDown(cache.dispose);
      return cache;
    }

    setUp(() => dir = _tempDir());

    test('evicts the least recently used file after a write', () async {
      final cache = build(budget: fileBytes * 2 + 1);
      putAll(cache, _key('a'), 3, 10);
      await files.writes(1);
      advance();
      putAll(cache, _key('b'), 3, 10);
      await files.writes(2);
      advance();
      cache.frame(_key('a'), 0); // a is more recent than b now
      advance();
      putAll(cache, _key('c'), 3, 10);
      await cache.dispose();

      expect(_names(dir, '.frames'), [
        '${_key('a').toFileStem()}.frames',
        '${_key('c').toFileStem()}.frames',
      ]);
    });

    test('evicts on the first scan, oldest first, by the clock that stamped '
        'the files', () async {
      final writer = build(budget: fileBytes * 10);
      for (final name in ['a', 'b', 'c']) {
        putAll(writer, _key(name), 3, 10);
        await files.writes(files.written.length + 1);
        advance();
      }
      await writer.dispose();
      expect(_names(dir, '.frames'), hasLength(3));

      final restarted = build(budget: fileBytes * 2 + 1);
      expect(await restarted.open(_key('c')), 3);
      expect(_names(dir, '.frames'), [
        '${_key('b').toFileStem()}.frames',
        '${_key('c').toFileStem()}.frames',
      ]);
    });

    test('reading a file counts as using it across restarts', () async {
      final writer = build(budget: fileBytes * 10);
      for (final name in ['a', 'b', 'c']) {
        putAll(writer, _key(name), 3, 10);
        await files.writes(files.written.length + 1);
        advance();
      }
      await writer.dispose();

      final reader = build(budget: fileBytes * 10);
      expect(await reader.open(_key('a')), 3); // a: now the most recent
      await reader.dispose();
      advance();

      final restarted = build(budget: fileBytes * 2 + 1);
      expect(await restarted.open(_key('a')), 3);
      expect(_names(dir, '.frames'), [
        '${_key('a').toFileStem()}.frames',
        '${_key('c').toFileStem()}.frames',
      ]);
    });
  });

  group('a file larger than the disk budget', () {
    test('is a miss and deleted, not read whole', () async {
      final dir = _tempDir();
      final key = _key('a');
      final small = FrameCache(directory: dir, clock: clock);
      putAll(small, key, 3, 10);
      await small.dispose();
      const fits = 36 + 5 + 1 + 3 * 8 + 30;

      final files = _CountingFiles(dir);
      final reader = FrameCache(
        directory: dir,
        files: files,
        diskBudgetBytes: fits + 10,
        clock: clock,
      );
      addTearDown(reader.dispose);
      // The scan sees the small file...
      expect(await reader.open(_key('other')), isNull);
      // ...then another writer replaces it with a valid, larger one.
      final bigger = FrameCache(directory: dir, clock: clock);
      putAll(bigger, key, 3, 400);
      await bigger.dispose();
      expect(
        File('${dir.path}/${key.toFileStem()}.frames').lengthSync(),
        greaterThan(fits + 10),
      );

      expect(await reader.open(key), isNull);
      expect(_names(dir, '.frames'), isEmpty, reason: 'deleted');
    });
  });

  group('temp files', () {
    test(
      'are named per process and per call, so no two writes share one',
      () async {
        final dir = _tempDir();
        final temps = <String>[];
        final first = _TempRecordingFiles(dir, temps);
        final second = _TempRecordingFiles(dir, temps);
        final bytes = _bytes(4, 1);

        await first.write('s', bytes, modified: now);
        await first.write('s', bytes, modified: now);
        await second.write('s', bytes, modified: now);

        expect(temps.toSet(), hasLength(3));
        for (final name in temps) {
          expect(
            name,
            matches(RegExp('^s\\.frames\\.$pid\\.\\d+\\.[0-9a-f]{8}\\.tmp\$')),
          );
        }
      },
    );
  });

  group('a timestamp that cannot be set', () {
    test(
      'does not make the cache unwritable: the entry was published',
      () async {
        final dir = _tempDir();
        final reported = <Object>[];
        final files = _UnstampableFiles(dir);
        final cache = FrameCache(
          directory: dir,
          files: files,
          clock: clock,
          onError: (e, _) => reported.add(e),
        );
        putAll(cache, _key('a'), 2, 10);
        await cache.dispose();
        expect(_names(dir, '.frames'), ['${_key('a').toFileStem()}.frames']);

        // Later writes still go to disk, and are tracked for eviction.
        final again = FrameCache(
          directory: dir,
          files: files,
          clock: clock,
          onError: (e, _) => reported.add(e),
        );
        putAll(again, _key('b'), 2, 10);
        putAll(again, _key('c'), 2, 10);
        await again.dispose();
        expect(_names(dir, '.frames'), hasLength(3));
        expect(reported.every((e) => e is FileSystemException), isTrue);
      },
    );

    test('is still told to the host, once', () async {
      final dir = _tempDir();
      final reported = <Object>[];
      final cache = FrameCache(
        directory: dir,
        files: _UnstampableFiles(dir),
        clock: clock,
        onError: (e, _) => reported.add(e),
      );
      putAll(cache, _key('a'), 2, 10);
      putAll(cache, _key('b'), 2, 10);
      await cache.dispose();

      expect(reported, hasLength(1));
    });
  });

  group('failures degrade to memory', () {
    late Directory dir;
    late List<Object> reported;

    bool isRoot() =>
        !Platform.isWindows &&
        Process.runSync('id', ['-u']).stdout.toString().trim() == '0';

    setUp(() {
      dir = _tempDir();
      reported = [];
    });

    test(
      'a read-only directory is reported once and frames stay in memory',
      () async {
        if (isRoot()) {
          markTestSkipped('root ignores file modes');
          return;
        }
        Process.runSync('chmod', ['500', dir.path]);
        final cache = FrameCache(
          directory: dir,
          clock: clock,
          onError: (e, _) => reported.add(e),
        );
        putAll(cache, _key('a'), 2, 10);
        putAll(cache, _key('b'), 2, 10);
        await cache.dispose();

        expect(reported, hasLength(1));
        expect(reported.single, isA<FileSystemException>());
        expect(cache.frame(_key('a'), 1), _bytes(10, 2));
        expect(cache.frame(_key('b'), 0), _bytes(10, 1));
        expect(dir.listSync(), isEmpty);
      },
    );

    test('an unreadable file is a reported miss, not a thrown error', () async {
      if (isRoot()) {
        markTestSkipped('root ignores file modes');
        return;
      }
      final writer = FrameCache(directory: dir, clock: clock);
      putAll(writer, _key('a'), 2, 10);
      await writer.dispose();
      Process.runSync('chmod', [
        '000',
        '${dir.path}/${_key('a').toFileStem()}.frames',
      ]);

      final cache = FrameCache(
        directory: dir,
        clock: clock,
        onError: (e, _) => reported.add(e),
      );
      addTearDown(cache.dispose);
      expect(await cache.open(_key('a')), isNull);
      expect(reported, hasLength(1));
    });

    test('a directory that is a file never fails a put', () async {
      final blocker = File('${dir.path}/cache')..writeAsStringSync('x');
      final cache = FrameCache(
        directory: Directory(blocker.path),
        clock: clock,
        onError: (e, _) => reported.add(e),
      );
      putAll(cache, _key('a'), 2, 10);
      await cache.dispose();
      expect(cache.frame(_key('a'), 0), _bytes(10, 1));
      expect(reported, hasLength(1));
    });
  });

  group('concurrency and lifecycle', () {
    late Directory dir;
    setUp(() => dir = _tempDir());

    test('concurrent opens of one key share one read', () async {
      final writer = FrameCache(directory: dir, clock: clock);
      putAll(writer, _key('a'), 3, 10);
      await writer.dispose();

      final files = _CountingFiles(dir);
      final cache = FrameCache(directory: dir, files: files, clock: clock);
      addTearDown(cache.dispose);
      final counts = await Future.wait([
        cache.open(_key('a')),
        cache.open(_key('a')),
        cache.open(_key('a')),
      ]);
      expect(counts, [3, 3, 3]);
      expect(files.reads, [_key('a').toFileStem()]);

      expect(await cache.open(_key('a')), 3);
      expect(files.reads, hasLength(1), reason: 'resident: no further read');
    });

    test('open is idempotent for a different key too', () async {
      final writer = FrameCache(directory: dir, clock: clock);
      putAll(writer, _key('a'), 2, 10);
      putAll(writer, _key('b'), 2, 10);
      await writer.dispose();

      final files = _CountingFiles(dir);
      final cache = FrameCache(directory: dir, files: files, clock: clock);
      addTearDown(cache.dispose);
      await Future.wait([cache.open(_key('a')), cache.open(_key('b'))]);
      expect(files.reads, hasLength(2));
    });

    test('dispose finishes pending writes and is idempotent', () async {
      final cache = FrameCache(directory: dir, clock: clock);
      putAll(cache, _key('a'), 2, 10);
      await Future.wait([cache.dispose(), cache.dispose()]);
      await cache.dispose();
      expect(_names(dir, '.frames'), hasLength(1));
      expect(_names(dir, '.tmp'), isEmpty);
    });

    test('a put or an open after dispose is a StateError', () async {
      final cache = FrameCache(directory: dir, clock: clock);
      await cache.dispose();
      expect(
        () => cache.put(_key('a'), 0, _bytes(1, 1), frameCount: 1),
        throwsStateError,
      );
      expect(cache.open(_key('a')), throwsStateError);
    });

    test('clear drops both tiers, after a pending write finishes', () async {
      final cache = FrameCache(directory: dir, clock: clock);
      putAll(cache, _key('a'), 2, 10);
      await cache.clear();

      expect(cache.has(_key('a'), 0), isFalse);
      expect(await cache.open(_key('a')), isNull);
      await cache.dispose();
      expect(_names(dir, '.frames'), isEmpty, reason: 'the write was cleared');
    });

    test('a cache is usable again after clear', () async {
      final cache = FrameCache(directory: dir, clock: clock);
      putAll(cache, _key('a'), 2, 10);
      await cache.clear();
      putAll(cache, _key('a'), 2, 10);
      await cache.dispose();
      expect(_names(dir, '.frames'), hasLength(1));
    });

    test(
      'invalidate drops the RAM entry and the file of one animation',
      () async {
        final cache = FrameCache(directory: dir, clock: clock);
        addTearDown(cache.dispose);
        putAll(cache, _key('a'), 2, 10);
        putAll(cache, _key('b'), 2, 10);
        await cache.dispose();
        final reopened = FrameCache(directory: dir, clock: clock);
        addTearDown(reopened.dispose);
        expect(await reopened.open(_key('a')), 2);

        await reopened.invalidate(_key('a'));

        expect(reopened.has(_key('a'), 0), isFalse);
        expect(await reopened.open(_key('a')), isNull);
        expect(_names(dir, '.frames'), [
          '${_key('b').toFileStem()}.frames',
        ], reason: 'only the invalidated file went');
        expect(await reopened.open(_key('b')), 2, reason: 'b is untouched');
      },
    );

    test(
      'invalidate waits for a write under way, so its file goes too',
      () async {
        final cache = FrameCache(directory: dir, clock: clock);
        addTearDown(cache.dispose);
        putAll(cache, _key('a'), 2, 10);

        await cache.invalidate(_key('a'));

        expect(_names(dir, '.frames'), isEmpty);
      },
    );

    test('invalidate of an unknown key is harmless', () async {
      final cache = FrameCache(directory: dir, clock: clock);
      addTearDown(cache.dispose);

      await expectLater(cache.invalidate(_key('nope')), completes);
    });

    test('invalidate frees the RAM it held, in a memory-only cache', () async {
      final cache = FrameCache(directory: null, clock: clock);
      addTearDown(cache.dispose);
      putAll(cache, _key('a'), 2, 10);

      await cache.invalidate(_key('a'));

      expect(cache.has(_key('a'), 0), isFalse);
      expect(await cache.open(_key('a')), isNull);
    });

    test('isDisposed tells a renderer to stop using the cache', () async {
      final cache = FrameCache(directory: dir, clock: clock);
      expect(cache.isDisposed, isFalse);
      await cache.dispose();
      expect(cache.isDisposed, isTrue);
    });
  });
}
