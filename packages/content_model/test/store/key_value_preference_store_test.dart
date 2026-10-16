import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

const _namespace = 'chat_chrome';
const _address = '$_namespace:preferences';
const _thumbs = ContentKey$Unicode('\u{1F44D}');
const _thumbsDark = ContentKey$Unicode('\u{1F44D}\u{1F3FF}');
const _wave = ContentKey$Unicode('\u{1F44B}');
const _waveMedium = ContentKey$Unicode('\u{1F44B}\u{1F3FD}');

void main() {
  runPreferenceStoreContract(
    () => KeyValuePreferenceStore.load(
      FakeKeyValueStore(),
      namespace: _namespace,
    ),
  );

  group('KeyValuePreferenceStore', () {
    late FakeKeyValueStore storage;

    Future<KeyValuePreferenceStore> open() =>
        KeyValuePreferenceStore.load(storage, namespace: _namespace);

    Future<KeyValuePreferenceStore> openWith(
      String text, {
      int version = 1,
    }) async {
      await storage.write(
        _namespace,
        'preferences',
        StoredValue(text, version: version),
      );
      return open();
    }

    setUp(() => storage = FakeKeyValueStore());

    group('persistence', () {
      test('writes one versioned record under the namespace', () async {
        final store = await open();

        await store.setPreferredVariant(_thumbs, _thumbsDark);
        await store.setSelectedPageId('emoji');

        expect(storage.entries.keys, [_address]);
        final record = storage.entries[_address]!;
        expect(record.version, 1);
        expect(jsonDecode(record.value), {
          'variants': {'unicode:1F44D': 'unicode:1F44D-1F3FF'},
          'selectedPageId': 'emoji',
        });
      });

      test(
        'writes the dock preference into the record, only when on',
        () async {
          final store = await open();

          await store.setDockPreferred(preferred: true);
          expect(jsonDecode(storage.entries[_address]!.value), {
            'dockPreferred': true,
          });

          await store.setDockPreferred(preferred: false);
          expect(storage.entries, isEmpty);
        },
      );

      test('hands the next store the dock preference', () async {
        final first = await open();
        await first.setDockPreferred(preferred: true);
        await first.setSelectedPageId('stickers');

        final second = await open();

        expect(second.dockPreferred, isTrue);
        expect(second.selectedPageId, 'stickers');
      });

      test('hands the next store what the last one chose', () async {
        final first = await open();
        await first.setPreferredVariant(_thumbs, _thumbsDark);
        await first.setPreferredVariant(_wave, _waveMedium);
        await first.setSelectedPageId('stickers');

        final second = await open();

        expect(second.preferredVariant(_thumbs), _thumbsDark);
        expect(second.preferredVariant(_wave), _waveMedium);
        expect(second.selectedPageId, 'stickers');
      });

      test('forgets a choice for good', () async {
        final first = await open();
        await first.setPreferredVariant(_thumbs, _thumbsDark);
        await first.setSelectedPageId('stickers');
        await first.setPreferredVariant(_thumbs, null);

        final second = await open();

        expect(second.preferredVariant(_thumbs), isNull);
        expect(second.selectedPageId, 'stickers');
      });

      test('removes the record once nothing is chosen', () async {
        final store = await open();
        await store.setSelectedPageId('stickers');

        await store.setSelectedPageId(null);

        expect(storage.entries, isEmpty);
      });

      test('writes nothing for a choice that changes nothing', () async {
        final store = await open();
        await store.setSelectedPageId('stickers');
        final before = storage.writeCount;

        await store.setSelectedPageId('stickers');
        await store.setPreferredVariant(_thumbs, null);

        expect(storage.writeCount, before);
      });

      test('leaves other namespaces and other keys alone', () async {
        const other = StoredValue('theirs', version: 1);
        await storage.write('other_pkg', 'preferences', other);
        await storage.write(_namespace, 'recents.sticker', other);
        final store = await open();

        await store.setSelectedPageId('stickers');
        await store.setSelectedPageId(null);

        expect(await storage.read('other_pkg', 'preferences'), other);
        expect(await storage.read(_namespace, 'recents.sticker'), other);
      });
    });

    group('loading stored data', () {
      test('starts empty when nothing was stored', () async {
        final store = await open();

        expect(store.selectedPageId, isNull);
        expect(store.preferredVariant(_thumbs), isNull);
      });

      test('discards a record written under another version', () async {
        final store = await openWith('{"selectedPageId":"emoji"}', version: 2);

        expect(store.selectedPageId, isNull);
      });

      test('discards a record that is not JSON or not an object', () async {
        expect((await openWith('{oops')).selectedPageId, isNull);
        expect((await openWith('[1]')).selectedPageId, isNull);
        expect((await openWith('"emoji"')).selectedPageId, isNull);
      });

      test('keeps the readable part of a partly readable record', () async {
        final store = await openWith(
          jsonEncode({
            'variants': {
              'unicode:1F44D': 'unicode:1F44D-1F3FF',
              'document:1': 'unicode:1F44D',
              'unicode:1F44B': 'document:2',
              'unicode:1F525': 7,
              'nonsense': 'unicode:1F44D',
            },
            'selectedPageId': 12,
          }),
        );

        expect(store.preferredVariant(_thumbs), _thumbsDark);
        expect(store.preferredVariant(_wave), isNull);
        expect(store.selectedPageId, isNull);
      });

      test('reads a record from before the dock preference as off', () async {
        final store = await openWith('{"selectedPageId":"emoji"}');

        expect(store.dockPreferred, isFalse);
      });

      test('reads the dock preference only from a boolean true', () async {
        expect((await openWith('{"dockPreferred":true}')).dockPreferred, true);
        expect(
          (await openWith('{"dockPreferred":"yes"}')).dockPreferred,
          false,
        );
        expect((await openWith('{"dockPreferred":1}')).dockPreferred, false);
      });

      test('reads a record with only a page', () async {
        final store = await openWith('{"selectedPageId":"emoji"}');

        expect(store.selectedPageId, 'emoji');
      });

      test('reads a variants entry that is not a map as none', () async {
        final store = await openWith(
          '{"variants":[1],"selectedPageId":"emoji"}',
        );

        expect(store.selectedPageId, 'emoji');
        expect(store.preferredVariant(_thumbs), isNull);
      });
    });

    group('failure', () {
      test('fails to load when storage cannot be read', () async {
        storage.failure = Exception('disk');

        await expectLater(open(), throwsException);
      });

      test(
        'fails a choice it could not persist, keeping it in memory',
        () async {
          final store = await open();
          var signals = 0;
          store.changes.addListener(() => signals++);
          storage.failure = Exception('disk');

          await expectLater(store.setSelectedPageId('emoji'), throwsException);

          expect(store.selectedPageId, 'emoji');
          expect(signals, 1);
        },
      );

      test('persists the whole state on the next success', () async {
        final store = await open();
        storage.failure = Exception('disk');
        await expectLater(
          store.setPreferredVariant(_thumbs, _thumbsDark),
          throwsException,
        );
        storage.failure = null;

        await store.setSelectedPageId('emoji');

        final reopened = await open();
        expect(reopened.preferredVariant(_thumbs), _thumbsDark);
        expect(reopened.selectedPageId, 'emoji');
      });
    });

    test('rejects a namespace the key-value store would reject', () async {
      await expectLater(
        KeyValuePreferenceStore.load(storage, namespace: ''),
        throwsArgumentError,
      );
    });
  });
}
