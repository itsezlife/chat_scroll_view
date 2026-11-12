import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  ContentLibraryContract.run(
    ({required limits}) async => FakeContentLibrary(limits: limits),
  );

  group('FakeContentLibrary', () {
    const limits = LibraryLimits(favouriteStickers: 5, savedGifs: 200);

    test('starts from the state it was given', () {
      final library = FakeContentLibrary(
        limits: limits,
        initial: LibraryState(savedGifs: const [ContentKey.external('a')]),
      );

      expect(library.savedGifs.value, [const ContentKey.external('a')]);
      library.dispose();
    });

    test('records the edits it committed, in order', () async {
      final library = FakeContentLibrary(limits: limits);
      const save = LibraryEdit.saveGif(ContentKey.external('a'));

      await library.apply(save).outcome;

      expect(library.committed, [save]);
      library.dispose();
    });

    test('fails its commits while failure is set', () async {
      final library = FakeContentLibrary(limits: limits)
        ..failure = Exception('offline');

      final outcome = await library
          .apply(const LibraryEdit.saveGif(ContentKey.external('a')))
          .outcome;

      expect(outcome, isA<EditOutcome$Failed>());
      expect(library.committed, isEmpty);
      library.dispose();
    });
  });
}
