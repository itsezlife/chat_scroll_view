/// The deferred view of a recents store: what a panel shows while the user
/// picks, against what the real store has already counted.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

ContentKey _key(String glyph) => ContentKey.unicode(glyph);

void main() {
  late FakeRecentsStore store;
  late DeferredRecentsStore view;
  late int signals;

  setUp(() async {
    store = FakeRecentsStore();
    await store.record(_key('😀'), kind: SemanticKind.unicodeEmoji);
    view = DeferredRecentsStore(store);
    signals = 0;
    view.changes.addListener(() => signals++);
    addTearDown(store.dispose);
    addTearDown(view.dispose);
  });

  test('shows what the store held when it was made', () {
    expect(view.recents(SemanticKind.unicodeEmoji), [_key('😀')]);
  });

  test('a pick goes to the store at once and shows nothing new', () async {
    await view.record(_key('🙂'), kind: SemanticKind.unicodeEmoji);

    expect(store.recents(SemanticKind.unicodeEmoji), hasLength(2));
    expect(view.recents(SemanticKind.unicodeEmoji), [_key('😀')]);
    expect(signals, 0);
  });

  test('a commit catches up and signals once', () async {
    await view.record(_key('🙂'), kind: SemanticKind.unicodeEmoji);

    view.commit();

    expect(view.recents(SemanticKind.unicodeEmoji), hasLength(2));
    expect(signals, 1);
  });

  test('a commit with nothing new signals nothing', () {
    view.commit();

    expect(signals, 0);
  });

  test(
    'a pick that search does not count is not shown after a commit',
    () async {
      await view.record(
        _key('🙂'),
        kind: SemanticKind.unicodeEmoji,
        source: PickSource.search,
      );

      view.commit();

      expect(view.recents(SemanticKind.unicodeEmoji), [_key('😀')]);
      expect(signals, 0);
    },
  );

  test('clearing forgets at once, in the store and in the view', () async {
    await view.record(_key('🙂'), kind: SemanticKind.unicodeEmoji);

    await view.clear(kind: SemanticKind.unicodeEmoji);

    expect(store.recents(SemanticKind.unicodeEmoji), isEmpty);
    expect(view.recents(SemanticKind.unicodeEmoji), isEmpty);
    expect(signals, 1);
  });

  group('removing', () {
    test('forgets in the store and in the view at once', () async {
      await view.remove(_key('😀'), kind: SemanticKind.unicodeEmoji);

      expect(store.recents(SemanticKind.unicodeEmoji), isEmpty);
      expect(view.recents(SemanticKind.unicodeEmoji), isEmpty);
      expect(signals, 1);
    });

    test('shows no other pick that is waiting for a commit', () async {
      await view.record(_key('🙂'), kind: SemanticKind.unicodeEmoji);
      await view.record(_key('😎'), kind: SemanticKind.unicodeEmoji);

      await view.remove(_key('😀'), kind: SemanticKind.unicodeEmoji);

      expect(view.recents(SemanticKind.unicodeEmoji), isEmpty);
      view.commit();
      expect(view.recents(SemanticKind.unicodeEmoji), hasLength(2));
    });

    test('takes the key only from what was shown, keeping the order of the '
        'rest', () async {
      await store.record(_key('🙂'), kind: SemanticKind.unicodeEmoji);
      view.commit();
      signals = 0;
      expect(view.recents(SemanticKind.unicodeEmoji), [_key('🙂'), _key('😀')]);

      await view.remove(_key('😀'), kind: SemanticKind.unicodeEmoji);

      expect(view.recents(SemanticKind.unicodeEmoji), [_key('🙂')]);
      expect(signals, 1);
    });

    test('forgets a pick of the same key that was not shown yet', () async {
      await view.record(_key('😀'), kind: SemanticKind.unicodeEmoji);
      await view.record(_key('😀'), kind: SemanticKind.unicodeEmoji);

      await view.remove(_key('😀'), kind: SemanticKind.unicodeEmoji);
      view.commit();

      expect(view.recents(SemanticKind.unicodeEmoji), isEmpty);
      expect(store.recents(SemanticKind.unicodeEmoji), isEmpty);
    });

    test('a pick after it counts again from one, at the next commit', () async {
      await view.remove(_key('😀'), kind: SemanticKind.unicodeEmoji);
      await view.record(_key('😀'), kind: SemanticKind.unicodeEmoji);
      expect(view.recents(SemanticKind.unicodeEmoji), isEmpty);

      view.commit();

      expect(view.recents(SemanticKind.unicodeEmoji), [_key('😀')]);
    });

    test(
      'says nothing for a key that was not shown, and leaves other kinds',
      () async {
        await store.record(_key('😀'), kind: SemanticKind.gif);
        view.commit();
        signals = 0;

        await view.remove(_key('🙂'), kind: SemanticKind.unicodeEmoji);
        await view.remove(_key('😀'), kind: SemanticKind.sticker);

        expect(signals, 0);
        expect(view.recents(SemanticKind.gif), [_key('😀')]);
        expect(view.recents(SemanticKind.unicodeEmoji), [_key('😀')]);
      },
    );

    test(
      'after dispose the store is still told and the view is silent',
      () async {
        view.dispose();

        await view.remove(_key('😀'), kind: SemanticKind.unicodeEmoji);

        expect(store.recents(SemanticKind.unicodeEmoji), isEmpty);
        expect(signals, 0);
      },
    );
  });

  test('a kind nothing was recorded under is empty', () {
    expect(view.recents(SemanticKind.sticker), isEmpty);
  });

  test(
    'disposing the view leaves the store alone and the commands silent',
    () async {
      view.dispose();
      view.dispose();

      view.commit();
      expect(store.recents(SemanticKind.unicodeEmoji), isNotEmpty);
      expect(signals, 0);
    },
  );
}
