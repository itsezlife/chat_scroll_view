/// The disk tier of the host's fetcher: bytes kept in a folder between
/// launches; what is removed, and when, is the media store's.
///
/// **Seam:** [ByteCache.directory] over a temporary folder; a later launch is
/// a second cache over the same folder.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/data/byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('byte_cache_'));
  tearDown(() => folder.deleteSync(recursive: true));

  ByteCache open() => ByteCache.directory('${folder.path}/stills')!;

  Uint8List bytes(int length, int value) =>
      Uint8List.fromList(List.filled(length, value));

  test('has nothing under a name never written', () async {
    expect(await open().read('a'), isNull);
  });

  test('reads back what was written, in a later launch too', () async {
    await open().write('a', bytes(3, 7));

    expect(await open().read('a'), [7, 7, 7]);
  });

  test('says at once whether it holds a name, in a later launch too', () async {
    expect(open().holds('a'), isFalse);

    await open().write('a', bytes(1, 1));

    expect(open().holds('a'), isTrue);
    File('${folder.path}/stills/a').deleteSync();
    expect(open().holds('a'), isFalse);
  });

  test('replaces what a name held', () async {
    final cache = open();
    await cache.write('a', bytes(1, 1));
    await cache.write('a', bytes(2, 2));

    expect(await cache.read('a'), [2, 2]);
  });

  test(
    'marks a file used when it is read: the store keeps it by that',
    () async {
      final cache = open();
      await cache.write('a', bytes(1, 1));
      final file = File('${folder.path}/stills/a')
        ..setLastModifiedSync(DateTime(2020));

      await cache.read('a');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(file.lastModifiedSync().year, greaterThan(2020));
    },
  );

  test('keeps nothing, and never throws, where the folder cannot be', () async {
    File('${folder.path}/stills').writeAsStringSync('a file in the way');
    final cache = open();

    await cache.write('a', bytes(1, 1));

    expect(await cache.read('a'), isNull);
  });
}
