import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [LibraryStorage] under test: a way to open it, again and again, over one
/// backing store that starts empty.
final class LibraryStorageHarness {
  /// Creates a harness whose [open] reaches one backing store.
  const LibraryStorageHarness({required this.open, this.failWrites});

  /// Opens the storage over the harness's backing store. A second call reads
  /// what the first committed, as an app opened again would.
  final LibraryStorage Function() open;

  /// Makes writes to the backing store fail (`failing: true`) or succeed
  /// again. When null, the failure tests are skipped.
  final void Function({required bool failing})? failWrites;
}

/// The behaviour every [LibraryStorage] must have, as a test suite to run
/// against an implementation.
abstract final class LibraryStorageContract {
  /// Runs the [LibraryStorage] contract against the harnesses [create]
  /// returns, one per test.
  static void run(Future<LibraryStorageHarness> Function() create) {
    group('LibraryStorage contract', () {
      const sticker = ContentKey.document('sticker-1');
      const other = ContentKey.unicode('\u{1F44D}');
      const gif = ContentKey.external('gif-1');
      const cats = PackId('cats');
      const dogs = PackId('dogs');
      const edit = LibraryEdit.addRecentSticker(sticker);

      late LibraryStorageHarness harness;

      final full = LibraryState(
        recentStickers: const [sticker, other],
        favouriteStickers: const [other],
        savedGifs: const [gif],
        installedPacks: const {
          PackKind.stickers: [cats, dogs],
          PackKind.emoji: [dogs],
        },
        archivedPacks: const {
          PackKind.masks: [cats],
        },
      );

      setUp(() async => harness = await create());

      test('reads an empty library before anything is committed', () async {
        expect(await harness.open().read(), LibraryState.empty);
      });

      test('reads back every list it was given, keys of any kind', () async {
        await harness.open().commit(edit, full);

        expect(await harness.open().read(), full);
      });

      test('keeps the last state it was given', () async {
        final storage = harness.open();
        await storage.commit(edit, full);
        final next = full.copyWith(
          recentStickers: const [other],
          installedPacks: {
            PackKind.stickers: const [dogs, cats],
          },
        );

        await storage.commit(edit, next);

        expect(await harness.open().read(), next);
      });

      test('reads back a list emptied after it held keys', () async {
        final storage = harness.open();
        await storage.commit(edit, full);

        await storage.commit(edit, LibraryState.empty);

        expect(await harness.open().read(), LibraryState.empty);
      });

      test('fails a commit it could not store and keeps the last', () async {
        final fail = harness.failWrites;
        if (fail == null) return markTestSkipped('no failure switch');
        final storage = harness.open();
        await storage.commit(edit, full);
        fail(failing: true);

        await expectLater(
          storage.commit(edit, LibraryState.empty),
          throwsA(anything),
        );
        fail(failing: false);

        expect(await harness.open().read(), full);
      });

      test(
        'stores the whole state at the next commit after a failure',
        () async {
          final fail = harness.failWrites;
          if (fail == null) return markTestSkipped('no failure switch');
          final storage = harness.open();
          await storage.read();
          fail(failing: true);
          await expectLater(storage.commit(edit, full), throwsA(anything));
          fail(failing: false);
          final next = full.copyWith(savedGifs: const []);

          await storage.commit(edit, next);

          expect(await harness.open().read(), next);
        },
      );
    });
  }
}
