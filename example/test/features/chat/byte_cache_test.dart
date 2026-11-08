/// The disk tier of the host's fetcher: bytes kept in a folder between
/// launches, under a budget.
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

  ByteCache open({int budgetBytes = 1024}) =>
      ByteCache.directory('${folder.path}/stills', budgetBytes: budgetBytes)!;

  Uint8List bytes(int length, int value) =>
      Uint8List.fromList(List.filled(length, value));

  test('has nothing under a name never written', () async {
    expect(await open().read('a'), isNull);
  });

  test('reads back what was written, in a later launch too', () async {
    await open().write('a', bytes(3, 7));

    expect(await open().read('a'), [7, 7, 7]);
  });

  test('replaces what a name held', () async {
    final cache = open();
    await cache.write('a', bytes(1, 1));
    await cache.write('a', bytes(2, 2));

    expect(await cache.read('a'), [2, 2]);
  });

  test('drops the least recently used past its budget', () async {
    final cache = open(budgetBytes: 10);
    await cache.write('a', bytes(4, 1));
    await cache.write('b', bytes(4, 2));
    await cache.read('a');

    await cache.write('c', bytes(4, 3));

    expect(await cache.read('b'), isNull);
    expect(await cache.read('a'), isNotNull);
    expect(await cache.read('c'), isNotNull);
  });

  test('counts what an earlier launch left against the budget', () async {
    await open(budgetBytes: 10).write('a', bytes(6, 1));

    await open(budgetBytes: 10).write('b', bytes(6, 2));

    final later = open(budgetBytes: 10);
    expect(await later.read('a'), isNull);
    expect(await later.read('b'), [2, 2, 2, 2, 2, 2]);
  });

  test('keeps nothing, and never throws, where the folder cannot be', () async {
    File('${folder.path}/stills').writeAsStringSync('a file in the way');
    final cache = open();

    await cache.write('a', bytes(1, 1));

    expect(await cache.read('a'), isNull);
  });
}
