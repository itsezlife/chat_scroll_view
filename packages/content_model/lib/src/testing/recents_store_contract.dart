import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// Makes the [RecentsStore] under test, holding at most [capacity] keys per
/// kind and nothing recorded yet.
typedef RecentsStoreFactory =
    Future<RecentsStore> Function({required int capacity});

/// Runs the [RecentsStore] contract against the stores [create] returns.
///
/// [create] is called once per test. Persistence is not part of this
/// contract; an implementation that persists also needs a test that reopens
/// it.
void runRecentsStoreContract(RecentsStoreFactory create) {
  group('RecentsStore contract', () {
    const thumbs = ContentKey.unicode('\u{1F44D}');
    const heart = ContentKey.unicode('\u{2764}\u{FE0F}');
    const fire = ContentKey.unicode('\u{1F525}');
    const sticker = ContentKey.document('5368');
    const gif = ContentKey.external('tenor-77');
    const emoji = SemanticKind.unicodeEmoji;

    late RecentsStore store;
    late int signals;

    Future<void> open({int capacity = 48}) async {
      store = await create(capacity: capacity);
      signals = 0;
      store.changes.addListener(() => signals++);
    }

    Future<void> pick(
      ContentKey key, {
      SemanticKind kind = emoji,
      int times = 1,
    }) async {
      for (var i = 0; i < times; i++) {
        await store.record(key, kind: kind);
      }
    }

    setUp(open);

    tearDown(() => store.dispose());

    group('listing', () {
      test('is empty for every kind before anything is recorded', () {
        for (final kind in SemanticKind.values) {
          expect(store.recents(kind), isEmpty);
        }
      });

      test('lists a recorded key under its kind', () async {
        await pick(thumbs);

        expect(store.recents(emoji), [thumbs]);
      });

      test('lists a key once however often it was picked', () async {
        await pick(thumbs, times: 3);

        expect(store.recents(emoji), [thumbs]);
      });

      test('holds keys of any variant', () async {
        await store.record(sticker, kind: SemanticKind.sticker);
        await store.record(gif, kind: SemanticKind.gif);
        await store.record(thumbs, kind: emoji);

        expect(store.recents(SemanticKind.sticker), [sticker]);
        expect(store.recents(SemanticKind.gif), [gif]);
        expect(store.recents(emoji), [thumbs]);
      });

      test('hands out a list that cannot be changed', () async {
        await pick(thumbs);

        expect(() => store.recents(emoji).add(heart), throwsUnsupportedError);
        expect(store.recents(emoji), [thumbs]);
      });
    });

    group('ordering', () {
      test('puts the most picked key first', () async {
        await pick(thumbs, times: 1);
        await pick(heart, times: 3);
        await pick(fire, times: 2);

        expect(store.recents(emoji), [heart, fire, thumbs]);
      });

      test('breaks a tie by recency, latest first', () async {
        await pick(thumbs);
        await pick(heart);
        await pick(fire);

        expect(store.recents(emoji), [fire, heart, thumbs]);
      });

      test('lets a key rise above an older one by being picked more', () async {
        await pick(thumbs);
        await pick(heart);
        await pick(thumbs);

        expect(store.recents(emoji), [thumbs, heart]);
      });

      test('prefers frequency over recency', () async {
        await pick(thumbs, times: 2);
        await pick(heart);

        expect(store.recents(emoji), [thumbs, heart]);
      });
    });

    group('kinds', () {
      test('keeps one list per kind', () async {
        await pick(thumbs, kind: SemanticKind.unicodeEmoji);
        await pick(heart, kind: SemanticKind.customEmoji);

        expect(store.recents(SemanticKind.unicodeEmoji), [thumbs]);
        expect(store.recents(SemanticKind.customEmoji), [heart]);
        expect(store.recents(SemanticKind.sticker), isEmpty);
      });

      test('counts a key picked under two kinds separately in each', () async {
        await pick(thumbs, kind: SemanticKind.unicodeEmoji, times: 2);
        await pick(heart, kind: SemanticKind.unicodeEmoji);
        await pick(thumbs, kind: SemanticKind.sticker);
        await pick(heart, kind: SemanticKind.sticker, times: 2);

        expect(store.recents(SemanticKind.unicodeEmoji), [thumbs, heart]);
        expect(store.recents(SemanticKind.sticker), [heart, thumbs]);
      });
    });

    group('which picks count', () {
      test('ignores a pick made from search results', () async {
        await store.record(thumbs, kind: emoji, source: PickSource.search);

        expect(store.recents(emoji), isEmpty);
        expect(signals, 0);
      });

      test('does not let a search pick raise a listed key', () async {
        await pick(thumbs);
        await pick(heart);
        await store.record(thumbs, kind: emoji, source: PickSource.search);

        expect(store.recents(emoji), [heart, thumbs]);
      });

      test('counts a pick made from the recents list', () async {
        await store.record(thumbs, kind: emoji, source: PickSource.recents);

        expect(store.recents(emoji), [thumbs]);
      });

      test('counts a pick made from a collection', () async {
        await store.record(thumbs, kind: emoji, source: PickSource.collection);

        expect(store.recents(emoji), [thumbs]);
      });
    });

    group('signal', () {
      test('goes out once per counted pick', () async {
        await pick(thumbs);
        await pick(thumbs);
        await pick(heart);

        expect(signals, 3);
      });

      test('arrives with the pick already listed', () async {
        List<ContentKey>? seen;
        store.changes.addListener(() => seen = store.recents(emoji));

        await pick(thumbs);

        expect(seen, [thumbs]);
      });

      test('precedes the completion of record', () async {
        final done = store.record(thumbs, kind: emoji);

        expect(store.recents(emoji), [thumbs]);
        expect(signals, 1);
        await done;
      });
    });

    group('capacity', () {
      test('keeps at most the capacity per kind', () async {
        await open(capacity: 2);

        await pick(thumbs);
        await pick(heart);
        await pick(fire);

        expect(store.recents(emoji), hasLength(2));
      });

      test('lets a new pick in by dropping the key that ranked last', () async {
        await open(capacity: 3);
        await pick(thumbs, times: 3);
        await pick(heart, times: 2);
        await pick(fire);

        await pick(sticker);

        expect(store.recents(emoji), [thumbs, heart, sticker]);
      });

      test('keeps a new pick even when every listed key outranks it', () async {
        await open(capacity: 2);
        await pick(thumbs, times: 5);
        await pick(heart, times: 5);

        await pick(fire);

        expect(store.recents(emoji), [heart, fire]);
      });

      test('drops nobody when a listed key is picked again', () async {
        await open(capacity: 2);
        await pick(thumbs);
        await pick(heart);

        await pick(thumbs);

        expect(store.recents(emoji), [thumbs, heart]);
      });

      test('counts each kind against its own capacity', () async {
        await open(capacity: 1);

        await pick(thumbs, kind: SemanticKind.unicodeEmoji);
        await pick(heart, kind: SemanticKind.customEmoji);

        expect(store.recents(SemanticKind.unicodeEmoji), [thumbs]);
        expect(store.recents(SemanticKind.customEmoji), [heart]);
      });

      test('holds a single key at a capacity of one', () async {
        await open(capacity: 1);

        await pick(thumbs, times: 4);
        await pick(heart);

        expect(store.recents(emoji), [heart]);
      });
    });

    group('clear', () {
      test('forgets one kind and leaves the others', () async {
        await pick(thumbs, kind: SemanticKind.unicodeEmoji);
        await pick(sticker, kind: SemanticKind.sticker);
        signals = 0;

        await store.clear(kind: SemanticKind.unicodeEmoji);

        expect(store.recents(SemanticKind.unicodeEmoji), isEmpty);
        expect(store.recents(SemanticKind.sticker), [sticker]);
        expect(signals, 1);
      });

      test('forgets every kind when none is named, with one signal', () async {
        await pick(thumbs, kind: SemanticKind.unicodeEmoji);
        await pick(sticker, kind: SemanticKind.sticker);
        await pick(gif, kind: SemanticKind.gif);
        signals = 0;

        await store.clear();

        for (final kind in SemanticKind.values) {
          expect(store.recents(kind), isEmpty);
        }
        expect(signals, 1);
      });

      test('says nothing when the named kind held nothing', () async {
        await pick(sticker, kind: SemanticKind.sticker);
        signals = 0;

        await store.clear(kind: SemanticKind.gif);

        expect(signals, 0);
        expect(store.recents(SemanticKind.sticker), [sticker]);
      });

      test('says nothing when nothing was recorded at all', () async {
        await store.clear();

        expect(signals, 0);
      });

      test('starts counting from zero afterwards', () async {
        await pick(thumbs, times: 3);
        await pick(heart);
        await store.clear();

        await pick(heart);
        await pick(thumbs);

        expect(store.recents(emoji), [thumbs, heart]);
      });
    });

    group('after dispose', () {
      test('is silent', () async {
        await pick(thumbs);
        signals = 0;

        store.dispose();
        await pick(heart);
        await store.clear();

        expect(signals, 0);
      });

      test('keeps answering with the last state', () async {
        await pick(thumbs);
        await pick(heart);

        store.dispose();

        expect(store.recents(emoji), [heart, thumbs]);
      });

      test('ignores commands', () async {
        await pick(thumbs);
        store.dispose();

        await pick(heart);
        await store.clear();

        expect(store.recents(emoji), [thumbs]);
      });

      test('can be disposed twice', () {
        store.dispose();

        expect(store.dispose, returnsNormally);
      });
    });
  });
}
