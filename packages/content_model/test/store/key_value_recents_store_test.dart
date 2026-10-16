import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

const _namespace = 'chat_chrome';
const _thumbs = ContentKey.unicode('\u{1F44D}\u{1F3FB}');
const _heart = ContentKey.unicode('\u{2764}\u{FE0F}');
const _sticker = ContentKey.document('5368');
const _gif = ContentKey.external('tenor-77');

DateTime _at(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

StoredValue _record(List<Map<String, Object>> entries, {int version = 1}) =>
    StoredValue(jsonEncode({'entries': entries}), version: version);

Map<String, Object> _entry(String key, int count, int lastUsed) => {
  'key': key,
  'count': count,
  'lastUsed': lastUsed,
};

void main() {
  runRecentsStoreContract(
    ({required capacity}) => KeyValueRecentsStore.load(
      FakeKeyValueStore(),
      namespace: _namespace,
      capacity: capacity,
    ),
  );

  group('KeyValueRecentsStore', () {
    late FakeKeyValueStore storage;
    var now = 1000;

    Future<KeyValueRecentsStore> open({int capacity = 48}) =>
        KeyValueRecentsStore.load(
          storage,
          namespace: _namespace,
          capacity: capacity,
          clock: () => _at(now),
        );

    setUp(() {
      storage = FakeKeyValueStore();
      now = 1000;
    });

    group('persistence', () {
      test(
        'writes one versioned record per kind, under the namespace',
        () async {
          final store = await open();

          now = 1500;
          await store.record(_thumbs, kind: SemanticKind.unicodeEmoji);
          now = 1600;
          await store.record(_thumbs, kind: SemanticKind.unicodeEmoji);
          await store.record(_sticker, kind: SemanticKind.sticker);

          expect(storage.entries.keys, [
            '$_namespace:recents.unicode_emoji',
            '$_namespace:recents.sticker',
          ]);
          final emoji = storage.entries['$_namespace:recents.unicode_emoji']!;
          expect(emoji.version, 1);
          expect(jsonDecode(emoji.value), {
            'entries': [
              {'key': 'unicode:1F44D-1F3FB', 'count': 2, 'lastUsed': 1600},
            ],
          });
        },
      );

      test('hands the next store what the last one recorded', () async {
        final first = await open();
        await first.record(_heart, kind: SemanticKind.unicodeEmoji);
        await first.record(_thumbs, kind: SemanticKind.unicodeEmoji);
        await first.record(_thumbs, kind: SemanticKind.unicodeEmoji);
        await first.record(_sticker, kind: SemanticKind.sticker);

        final second = await open();

        expect(second.recents(SemanticKind.unicodeEmoji), [_thumbs, _heart]);
        expect(second.recents(SemanticKind.sticker), [_sticker]);
      });

      test('round-trips document and external keys', () async {
        final first = await open();
        await first.record(_sticker, kind: SemanticKind.sticker);
        await first.record(_gif, kind: SemanticKind.gif);

        final second = await open();

        expect(second.recents(SemanticKind.sticker), [_sticker]);
        expect(second.recents(SemanticKind.gif), [_gif]);
        expect(
          second.recents(SemanticKind.sticker).single,
          isA<ContentKey$Document>(),
        );
        expect(
          second.recents(SemanticKind.gif).single,
          isA<ContentKey$External>(),
        );
      });

      test(
        'keeps counts across stores, so later picks still outrank',
        () async {
          final first = await open();
          await first.record(_heart, kind: SemanticKind.unicodeEmoji);
          await first.record(_heart, kind: SemanticKind.unicodeEmoji);
          await first.record(_thumbs, kind: SemanticKind.unicodeEmoji);

          final second = await open();
          await second.record(_thumbs, kind: SemanticKind.unicodeEmoji);
          expect(second.recents(SemanticKind.unicodeEmoji), [_thumbs, _heart]);
        },
      );

      test('stamps a pick later than anything it loaded', () async {
        await storage.write(
          _namespace,
          'recents.unicode_emoji',
          _record([_entry('unicode:2764-FE0F', 1, 9000)]),
        );
        final store = await open();
        now = 10;

        await store.record(_thumbs, kind: SemanticKind.unicodeEmoji);

        expect(store.recents(SemanticKind.unicodeEmoji), [_thumbs, _heart]);
      });

      test('removes the record of a kind that was cleared', () async {
        final store = await open();
        await store.record(_thumbs, kind: SemanticKind.unicodeEmoji);
        await store.record(_sticker, kind: SemanticKind.sticker);

        await store.clear(kind: SemanticKind.sticker);

        expect(storage.entries.keys, ['$_namespace:recents.unicode_emoji']);
      });

      test('removes every record when everything is cleared', () async {
        final store = await open();
        await store.record(_thumbs, kind: SemanticKind.unicodeEmoji);
        await store.record(_sticker, kind: SemanticKind.sticker);

        await store.clear();

        expect(storage.entries, isEmpty);
        expect((await open()).recents(SemanticKind.sticker), isEmpty);
      });

      test('writes nothing for a search pick', () async {
        final store = await open();

        await store.record(
          _thumbs,
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.search,
        );

        expect(storage.writeCount, 0);
      });

      test('leaves other namespaces and other keys alone', () async {
        const other = StoredValue('theirs', version: 1);
        await storage.write('other_pkg', 'recents.unicode_emoji', other);
        await storage.write(_namespace, 'preferences', other);
        final store = await open();

        await store.record(_thumbs, kind: SemanticKind.unicodeEmoji);
        await store.clear();

        expect(await storage.read('other_pkg', 'recents.unicode_emoji'), other);
        expect(await storage.read(_namespace, 'preferences'), other);
      });
    });

    group('loading stored data', () {
      Future<List<ContentKey>> loadEmoji(StoredValue value) async {
        await storage.write(_namespace, 'recents.unicode_emoji', value);
        return (await open()).recents(SemanticKind.unicodeEmoji);
      }

      test('orders by count then recency whatever the stored order', () async {
        final keys = await loadEmoji(
          _record([
            _entry('unicode:1F44D-1F3FB', 1, 10),
            _entry('unicode:2764-FE0F', 1, 20),
            _entry('document:5368', 4, 5),
          ]),
        );

        expect(keys, [_sticker, _heart, _thumbs]);
      });

      test('discards a record written under another version', () async {
        final keys = await loadEmoji(
          _record([_entry('unicode:2764-FE0F', 1, 10)], version: 2),
        );

        expect(keys, isEmpty);
      });

      test('discards a record that is not JSON', () async {
        final keys = await loadEmoji(const StoredValue('{oops', version: 1));

        expect(keys, isEmpty);
      });

      test('discards a record of the wrong shape', () async {
        expect(
          await loadEmoji(const StoredValue('[1,2]', version: 1)),
          isEmpty,
        );
        expect(
          await loadEmoji(const StoredValue('{"entries":7}', version: 1)),
          isEmpty,
        );
        expect(await loadEmoji(const StoredValue('{}', version: 1)), isEmpty);
      });

      test('skips an entry it cannot read and keeps the others', () async {
        final keys = await loadEmoji(
          StoredValue(
            jsonEncode({
              'entries': [
                _entry('unicode:2764-FE0F', 2, 10),
                {'key': 'nonsense:1', 'count': 3, 'lastUsed': 11},
                {'key': 'unicode:1F44D', 'count': 0, 'lastUsed': 12},
                {'key': 'unicode:1F525', 'count': -1, 'lastUsed': 12},
                {'key': 'unicode:1F525', 'count': 'many', 'lastUsed': 12},
                {'key': 'unicode:1F525', 'count': 1},
                {'count': 1, 'lastUsed': 1},
                'junk',
                null,
              ],
            }),
            version: 1,
          ),
        );

        expect(keys, [_heart]);
      });

      test('keeps the first of a key that is stored twice', () async {
        final keys = await loadEmoji(
          _record([
            _entry('unicode:2764-FE0F', 5, 10),
            _entry('unicode:2764-FE0F', 1, 99),
          ]),
        );
        expect(keys, [_heart]);
      });

      test(
        'keeps only the best entries when stored more than capacity',
        () async {
          await storage.write(
            _namespace,
            'recents.unicode_emoji',
            _record([
              _entry('unicode:1F44D-1F3FB', 3, 1),
              _entry('unicode:2764-FE0F', 2, 2),
              _entry('unicode:1F525', 1, 3),
            ]),
          );

          final store = await open(capacity: 2);

          expect(store.recents(SemanticKind.unicodeEmoji), [_thumbs, _heart]);
        },
      );

      test(
        'reads the record of a kind this version does not know as none',
        () async {
          await storage.write(
            _namespace,
            'recents.hologram',
            _record([_entry('unicode:2764-FE0F', 1, 1)]),
          );

          final store = await open();

          for (final kind in SemanticKind.values) {
            expect(store.recents(kind), isEmpty);
          }
        },
      );
    });

    group('failure', () {
      test('fails to load when storage cannot be read', () async {
        storage.failure = Exception('disk');

        await expectLater(open(), throwsException);
      });

      test(
        'fails the pick that could not be persisted, keeping it in memory',
        () async {
          final store = await open();
          var signals = 0;
          store.changes.addListener(() => signals++);
          storage.failure = Exception('disk');

          await expectLater(
            store.record(_thumbs, kind: SemanticKind.unicodeEmoji),
            throwsException,
          );

          expect(store.recents(SemanticKind.unicodeEmoji), [_thumbs]);
          expect(signals, 1);
        },
      );

      test('persists the whole state on the next success', () async {
        final store = await open();
        storage.failure = Exception('disk');
        await expectLater(
          store.record(_thumbs, kind: SemanticKind.unicodeEmoji),
          throwsException,
        );
        storage.failure = null;

        await store.record(_heart, kind: SemanticKind.unicodeEmoji);

        final reopened = await open();
        expect(reopened.recents(SemanticKind.unicodeEmoji), [_heart, _thumbs]);
      });

      test(
        'fails a clear that could not be persisted, keeping it in memory',
        () async {
          final store = await open();
          await store.record(_thumbs, kind: SemanticKind.unicodeEmoji);
          storage.failure = Exception('disk');

          await expectLater(store.clear(), throwsException);

          expect(store.recents(SemanticKind.unicodeEmoji), isEmpty);
        },
      );
    });

    group('creation', () {
      test('rejects a namespace the key-value store would reject', () async {
        await expectLater(
          KeyValueRecentsStore.load(storage, namespace: 'a:b'),
          throwsArgumentError,
        );
      });

      test('rejects a capacity below one', () async {
        await expectLater(
          KeyValueRecentsStore.load(
            storage,
            namespace: _namespace,
            capacity: 0,
          ),
          throwsArgumentError,
        );
      });

      test('holds 48 keys per kind by default', () async {
        final store = await KeyValueRecentsStore.load(
          storage,
          namespace: _namespace,
        );
        for (var i = 0; i < 50; i++) {
          await store.record(
            ContentKey.document('$i'),
            kind: SemanticKind.sticker,
          );
        }

        expect(store.recents(SemanticKind.sticker), hasLength(48));
        expect(KeyValueRecentsStore.defaultCapacity, 48);
      });
    });
  });
}
