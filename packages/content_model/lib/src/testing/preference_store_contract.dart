import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// Runs the [PreferenceStore] contract against the stores [create] returns.
///
/// [create] is called once per test and must return a store with no choice
/// made yet. Persistence is not part of this contract; an implementation that
/// persists also needs a test that reopens it.
void runPreferenceStoreContract(Future<PreferenceStore> Function() create) {
  group('PreferenceStore contract', () {
    const thumbs = ContentKey$Unicode('\u{1F44D}');
    const thumbsDark = ContentKey$Unicode('\u{1F44D}\u{1F3FF}');
    const thumbsLight = ContentKey$Unicode('\u{1F44D}\u{1F3FB}');
    const wave = ContentKey$Unicode('\u{1F44B}');
    const waveMedium = ContentKey$Unicode('\u{1F44B}\u{1F3FD}');

    late PreferenceStore store;
    late int signals;

    setUp(() async {
      store = await create();
      signals = 0;
      store.changes.addListener(() => signals++);
    });

    tearDown(() => store.dispose());

    group('preferred variant', () {
      test('is none until one is chosen', () {
        expect(store.preferredVariant(thumbs), isNull);
      });

      test('is the exact key that was chosen', () async {
        await store.setPreferredVariant(thumbs, thumbsDark);

        expect(store.preferredVariant(thumbs), thumbsDark);
      });

      test('is chosen per base', () async {
        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setPreferredVariant(wave, waveMedium);

        expect(store.preferredVariant(thumbs), thumbsDark);
        expect(store.preferredVariant(wave), waveMedium);
      });

      test('is replaced by a later choice', () async {
        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setPreferredVariant(thumbs, thumbsLight);

        expect(store.preferredVariant(thumbs), thumbsLight);
      });

      test('is forgotten by choosing null, for that base only', () async {
        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setPreferredVariant(wave, waveMedium);

        await store.setPreferredVariant(thumbs, null);

        expect(store.preferredVariant(thumbs), isNull);
        expect(store.preferredVariant(wave), waveMedium);
      });

      test(
        'is kept as given even if it is not a variant of the base',
        () async {
          await store.setPreferredVariant(thumbs, waveMedium);

          expect(store.preferredVariant(thumbs), waveMedium);
        },
      );

      test('can name the base itself', () async {
        await store.setPreferredVariant(thumbs, thumbs);

        expect(store.preferredVariant(thumbs), thumbs);
      });
    });

    group('selected page', () {
      test('is none until one is remembered', () {
        expect(store.selectedPageId, isNull);
      });

      test('is the id that was remembered', () async {
        await store.setSelectedPageId('stickers');

        expect(store.selectedPageId, 'stickers');
      });

      test('is replaced by a later id and forgotten by null', () async {
        await store.setSelectedPageId('stickers');
        await store.setSelectedPageId('gifs');
        expect(store.selectedPageId, 'gifs');

        await store.setSelectedPageId(null);
        expect(store.selectedPageId, isNull);
      });

      test('keeps the id exactly, whatever it holds', () async {
        const odd = ' pa:ge/\u{1F600} "1"\n';
        await store.setSelectedPageId(odd);

        expect(store.selectedPageId, odd);
      });

      test('is independent of the variant choices', () async {
        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setSelectedPageId('emoji');
        await store.setPreferredVariant(thumbs, null);

        expect(store.selectedPageId, 'emoji');
      });
    });

    group('signal', () {
      test('goes out once per choice that changed something', () async {
        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setSelectedPageId('emoji');
        await store.setPreferredVariant(thumbs, null);
        await store.setSelectedPageId(null);

        expect(signals, 4);
      });

      test('stays silent when a choice repeats what is already set', () async {
        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setSelectedPageId('emoji');
        signals = 0;

        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setSelectedPageId('emoji');

        expect(signals, 0);
      });

      test('stays silent when forgetting what was never chosen', () async {
        await store.setPreferredVariant(thumbs, null);
        await store.setSelectedPageId(null);

        expect(signals, 0);
      });

      test('arrives with the choice already readable', () async {
        ContentKey$Unicode? seen;
        store.changes.addListener(() => seen = store.preferredVariant(thumbs));

        await store.setPreferredVariant(thumbs, thumbsDark);

        expect(seen, thumbsDark);
      });

      test('precedes the completion of the setter', () async {
        final done = store.setSelectedPageId('emoji');

        expect(store.selectedPageId, 'emoji');
        expect(signals, 1);
        await done;
      });
    });

    group('after dispose', () {
      test('is silent', () async {
        store.dispose();

        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setSelectedPageId('emoji');

        expect(signals, 0);
      });

      test('keeps answering with the last state', () async {
        await store.setPreferredVariant(thumbs, thumbsDark);
        await store.setSelectedPageId('emoji');

        store.dispose();

        expect(store.preferredVariant(thumbs), thumbsDark);
        expect(store.selectedPageId, 'emoji');
      });

      test('ignores setters', () async {
        await store.setSelectedPageId('emoji');
        store.dispose();

        await store.setSelectedPageId('gifs');
        await store.setPreferredVariant(thumbs, thumbsDark);

        expect(store.selectedPageId, 'emoji');
        expect(store.preferredVariant(thumbs), isNull);
      });

      test('can be disposed twice', () {
        store.dispose();

        expect(store.dispose, returnsNormally);
      });
    });
  });
}
