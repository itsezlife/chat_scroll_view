import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  LibraryStorageContract.run(() async {
    final storage = FakeLibraryStorage();
    return LibraryStorageHarness(
      open: () => storage,
      failWrites: ({required failing}) =>
          storage.failure = failing ? Exception('offline') : null,
    );
  });

  group('FakeLibraryStorage', () {
    test('records each commit with its edit, in order', () async {
      final storage = FakeLibraryStorage();
      const first = LibraryEdit.saveGif(ContentKey.external('a'));
      const second = LibraryEdit.unsaveGif(ContentKey.external('a'));

      await storage.commit(first, LibraryState.empty);
      await storage.commit(second, LibraryState.empty);

      expect(storage.edits, [first, second]);
    });

    test('starts from the state it was given', () async {
      final state = LibraryState(savedGifs: const [ContentKey.external('a')]);

      expect(await FakeLibraryStorage(state).read(), state);
    });
  });
}
