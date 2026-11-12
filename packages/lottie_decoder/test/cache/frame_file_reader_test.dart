import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/src/cache/frame_cache_codec.dart';
import 'package:lottie_decoder/src/cache/frame_file_reader.dart';

FrameCacheKey _key(String hash) =>
    FrameCacheKey(contentHash: hash, width: 8, height: 8, engineVersion: '1');

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('frame_file_reader_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  /// Writes a file of the [parity] frames of [key] whose frame i (of the
  /// parity) is [length] bytes of [fill] + i.
  String write(
    FrameCacheKey key, {
    FrameParity parity = FrameParity.even,
    int count = 3,
    int length = 4,
    int fill = 1,
  }) {
    final frames = [
      for (var i = 0; i < count; i++)
        Uint8List(length)..fillRange(0, length, fill + i),
    ];
    final path = '${dir.path}/${key.toFileStem(parity)}.frames';
    File(path).writeAsBytesSync([
      ...FrameCacheCodec.header(key, parity, [
        for (final f in frames) f.length,
      ]),
      for (final frame in frames) ...frame,
    ]);
    return path;
  }

  test('reads each frame at its offset, any order', () {
    final reader = FrameFileReader();
    addTearDown(reader.close);
    final path = write(_key('a'));

    expect(reader.read(CachedFrameFile(path, _key('a'), 4)), [3, 3, 3, 3]);
    expect(reader.read(CachedFrameFile(path, _key('a'), 0)), [1, 1, 1, 1]);
  });

  test('a file of the odd frames serves those, and never a frame of the '
      'other parity', () {
    final reader = FrameFileReader();
    addTearDown(reader.close);
    final path = write(_key('a'), parity: FrameParity.odd);

    expect(reader.read(CachedFrameFile(path, _key('a'), 1)), [1, 1, 1, 1]);
    expect(reader.read(CachedFrameFile(path, _key('a'), 5)), [3, 3, 3, 3]);
    expect(reader.read(CachedFrameFile(path, _key('a'), 2)), isNull);
    expect(reader.read(CachedFrameFile(path, _key('a'), 7)), isNull);
  });

  test('more animations than open files still read correctly', () {
    final reader = FrameFileReader(maxOpenFiles: 1);
    addTearDown(reader.close);
    final a = write(_key('a'));
    final b = write(_key('b'), fill: 7);

    for (var round = 0; round < 3; round++) {
      expect(reader.read(CachedFrameFile(a, _key('a'), 2)), [2, 2, 2, 2]);
      expect(reader.read(CachedFrameFile(b, _key('b'), 2)), [8, 8, 8, 8]);
    }
  });

  test('a file forgotten and written again is read afresh', () {
    final reader = FrameFileReader();
    addTearDown(reader.close);
    final path = write(_key('a'));
    expect(reader.read(CachedFrameFile(path, _key('a'), 0)), [1, 1, 1, 1]);

    reader.forget(path);
    write(_key('a'), length: 2, fill: 5);

    expect(reader.read(CachedFrameFile(path, _key('a'), 0)), [5, 5]);
  });

  test('a missing file or another key is null, never thrown', () {
    final reader = FrameFileReader();
    addTearDown(reader.close);
    final path = write(_key('a'));

    expect(reader.read(CachedFrameFile('$path.x', _key('a'), 0)), isNull);
    expect(reader.read(CachedFrameFile(path, _key('b'), 0)), isNull);
    expect(reader.read(CachedFrameFile(path, _key('a'), -1)), isNull);
    expect(reader.read(CachedFrameFile(path, _key('a'), 0)), [1, 1, 1, 1]);
  });

  test('a table that claims a frame larger than the size allows is refused '
      'before anything that large is allocated', () {
    final reader = FrameFileReader();
    addTearDown(reader.close);
    // 8 x 8 RGBA is 256 bytes raw; lz4's worst case is a little more.
    final path = write(_key('a'), count: 1, length: 1000);

    expect(reader.read(CachedFrameFile(path, _key('a'), 0)), isNull);
  });
}
