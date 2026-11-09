import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

const _limits = LibraryLimits(favouriteStickers: 5, savedGifs: 200);
const _a = ContentKey.document('a');
const _b = ContentKey.document('b');
const _gif = ContentKey.external('gif');
const _cats = PackId('cats');
const _window = Duration(minutes: 1);

void main() {
  ContentLibraryContract.run(
    ({required limits}) =>
        StoredContentLibrary.load(FakeLibraryStorage(), limits: limits),
  );

  group('StoredContentLibrary', () {
    late FakeLibraryStorage storage;
    late StoredContentLibrary library;

    Future<void> open([LibraryLimits limits = _limits]) async =>
        library = await StoredContentLibrary.load(storage, limits: limits);

    setUp(() => storage = FakeLibraryStorage());

    tearDown(() => library.dispose());

    test('starts from what storage holds', () async {
      storage = FakeLibraryStorage(
        LibraryState(
          favouriteStickers: const [_a],
          installedPacks: const {
            PackKind.stickers: [_cats],
          },
        ),
      );

      await open();

      expect(library.favouriteStickers.value, [_a]);
      expect(library.installStateOf(_cats), PackInstallState.installed);
    });

    test('cuts a list read back longer than its limit', () async {
      storage = FakeLibraryStorage(
        LibraryState(favouriteStickers: const [_a, _b]),
      );

      await open(const LibraryLimits(favouriteStickers: 1, savedGifs: 1));

      expect(library.favouriteStickers.value, [_a]);
    });

    test('fails to load when storage cannot be read', () async {
      storage.failure = Exception('offline');

      await expectLater(
        StoredContentLibrary.load(storage, limits: _limits),
        throwsException,
      );
      storage.failure = null;
      await open();
    });

    test('hands storage each edit with the committed state after it', () async {
      await open();

      await library.apply(const LibraryEdit.saveGif(_gif)).outcome;
      await library.apply(const LibraryEdit.favouriteSticker(_a)).outcome;

      expect(storage.edits, const [
        LibraryEdit.saveGif(_gif),
        LibraryEdit.favouriteSticker(_a),
      ]);
      expect(
        storage.state,
        LibraryState(savedGifs: const [_gif], favouriteStickers: const [_a]),
      );
    });

    test('never hands storage an edit taken back', () async {
      await open();

      library
          .apply(
            const LibraryEdit.installPack(_cats, PackKind.stickers),
            undoWindow: _window,
          )
          .undo();
      await library.apply(const LibraryEdit.saveGif(_gif)).outcome;

      expect(storage.edits, const [LibraryEdit.saveGif(_gif)]);
      expect(storage.state, LibraryState(savedGifs: const [_gif]));
    });

    test('commits in the order the edits were applied', () async {
      await open();
      final first = library.apply(
        const LibraryEdit.favouriteSticker(_a),
        undoWindow: _window,
      );
      final second = library.apply(const LibraryEdit.favouriteSticker(_b));

      first.commit();
      await second.outcome;

      expect(storage.edits, const [
        LibraryEdit.favouriteSticker(_a),
        LibraryEdit.favouriteSticker(_b),
      ]);
      expect(storage.state.favouriteStickers, [_b, _a]);
    });

    test('stores nothing while an edit is pending', () async {
      await open();

      library.apply(const LibraryEdit.saveGif(_gif), undoWindow: _window);
      await Future<void>.delayed(Duration.zero);

      expect(storage.edits, isEmpty);
    });

    test('keeps the change and reports a failed commit', () async {
      await open();
      storage.failure = Exception('offline');

      final outcome = await library
          .apply(const LibraryEdit.saveGif(_gif))
          .outcome;

      expect(outcome, isA<EditOutcome$Failed>());
      expect(library.savedGifs.value, [_gif]);
    });

    test('commits what is pending at dispose', () async {
      await open();
      final applied = library.apply(
        const LibraryEdit.saveGif(_gif),
        undoWindow: _window,
      );

      library.dispose();
      await applied.outcome;

      expect(storage.state.savedGifs, [_gif]);
    });
  });
}
