import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

const _namespace = 'library';
const _sticker = ContentKey.document('sticker-1');
const _edit = LibraryEdit.addRecentSticker(_sticker);

void main() {
  LibraryStorageContract.run(() async {
    final backing = FakeKeyValueStore();
    return LibraryStorageHarness(
      open: () => KeyValueLibraryStorage(backing, namespace: _namespace),
      failWrites: ({required failing}) =>
          backing.failure = failing ? Exception('disk full') : null,
    );
  });

  group('KeyValueLibraryStorage', () {
    late FakeKeyValueStore backing;

    KeyValueLibraryStorage open() =>
        KeyValueLibraryStorage(backing, namespace: _namespace);

    setUp(() => backing = FakeKeyValueStore());

    test('rejects an invalid namespace', () {
      expect(
        () => KeyValueLibraryStorage(backing, namespace: 'a:b'),
        throwsArgumentError,
      );
    });

    test('writes one versioned record per list that holds keys', () async {
      await open().commit(
        _edit,
        LibraryState(
          recentStickers: const [_sticker],
          installedPacks: const {
            PackKind.emoji: [PackId('cats')],
          },
        ),
      );

      expect(backing.entries.keys.toSet(), {
        '$_namespace:recent_stickers',
        '$_namespace:installed_packs.emoji',
      });
      final recent = backing.entries['$_namespace:recent_stickers']!;
      expect(recent.version, KeyValueLibraryStorage.recordVersion);
      expect(jsonDecode(recent.value), {
        'items': ['document:sticker-1'],
      });
    });

    test('writes only the lists that changed since the last commit', () async {
      final storage = open();
      final first = LibraryState(recentStickers: const [_sticker]);
      await storage.commit(_edit, first);
      final writes = backing.writeCount;

      await storage.commit(
        _edit,
        first.copyWith(savedGifs: const [ContentKey.external('gif')]),
      );

      expect(backing.writeCount, writes + 1);
    });

    test('reads a record it cannot understand as an empty list', () async {
      await backing.write(
        _namespace,
        'saved_gifs',
        const StoredValue('not json', version: 1),
      );
      await backing.write(
        _namespace,
        'favourite_stickers',
        StoredValue(
          jsonEncode({
            'items': ['document:a'],
          }),
          version: 99,
        ),
      );
      await backing.write(
        _namespace,
        'recent_stickers',
        StoredValue(
          jsonEncode({
            'items': ['document:a', 'nonsense', 7],
          }),
          version: 1,
        ),
      );

      expect(
        await open().read(),
        LibraryState(recentStickers: const [ContentKey.document('a')]),
      );
    });
  });
}
