import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:test/test.dart';

/// Makes the [ContentLibrary] under test, empty, keeping at most [limits].
typedef ContentLibraryFactory =
    Future<ContentLibrary> Function({required LibraryLimits limits});

/// The behaviour every [ContentLibrary] must have, as a test suite to run
/// against an implementation.
abstract final class ContentLibraryContract {
  /// Runs the [ContentLibrary] contract against the libraries [create]
  /// returns, one per test.
  ///
  /// Persistence is not part of this contract; an implementation that
  /// persists also needs a test that reopens it.
  static void run(ContentLibraryFactory create) {
    group('ContentLibrary contract', () {
      const a = ContentKey.document('a');
      const b = ContentKey.document('b');
      const c = ContentKey.document('c');
      const gif = ContentKey.external('gif');
      const cats = PackId('cats');
      const dogs = PackId('dogs');
      const owls = PackId('owls');
      const stickers = PackKind.stickers;
      const limits = LibraryLimits(
        favouriteStickers: 2,
        savedGifs: 2,
        recentStickers: 2,
      );

      late ContentLibrary library;
      late Map<String, int> signals;

      void count(String name, Listenable listenable) => listenable.addListener(
        () => signals[name] = (signals[name] ?? 0) + 1,
      );

      Future<void> open({LibraryLimits limits = limits}) async {
        library = await create(limits: limits);
        signals = {};
        count('recent', library.recentStickers);
        count('favourite', library.favouriteStickers);
        count('saved', library.savedGifs);
        for (final kind in PackKind.values) {
          count('installed.${kind.value}', library.installedPacks(kind));
          count('archived.${kind.value}', library.archivedPacks(kind));
        }
      }

      AppliedEdit apply(LibraryEdit edit, {Duration? undoWindow}) =>
          undoWindow == null
          ? library.apply(edit)
          : library.apply(edit, undoWindow: undoWindow);

      void applyAll(List<LibraryEdit> edits) => edits.forEach(apply);

      setUp(open);

      tearDown(() => library.dispose());

      group('start', () {
        test('is empty, with the limits it was given', () {
          expect(library.limits, limits);
          expect(library.recentStickers.value, isEmpty);
          expect(library.favouriteStickers.value, isEmpty);
          expect(library.savedGifs.value, isEmpty);
          for (final kind in PackKind.values) {
            expect(library.installedPacks(kind).value, isEmpty);
            expect(library.archivedPacks(kind).value, isEmpty);
          }
          expect(library.installStateOf(cats), PackInstallState.notInstalled);
        });
      });

      group('most-recently-used lists', () {
        final lists =
            <
              String,
              (
                LibraryEdit Function(ContentKey),
                LibraryEdit Function(ContentKey),
                ValueListenable<List<ContentKey>> Function(),
              )
            >{
              'recent stickers': (
                LibraryEdit.addRecentSticker,
                LibraryEdit.removeRecentSticker,
                () => library.recentStickers,
              ),
              'favourite stickers': (
                LibraryEdit.favouriteSticker,
                LibraryEdit.unfavouriteSticker,
                () => library.favouriteStickers,
              ),
              'saved GIFs': (
                LibraryEdit.saveGif,
                LibraryEdit.unsaveGif,
                () => library.savedGifs,
              ),
            };

        for (final MapEntry(key: name, value: (add, remove, list))
            in lists.entries) {
          group(name, () {
            test('lists the latest key first', () {
              applyAll([add(a), add(b)]);

              expect(list().value, [b, a]);
            });

            test('moves a listed key to the front, never twice', () {
              applyAll([add(a), add(b), add(a)]);

              expect(list().value, [a, b]);
            });

            test('pushes out the oldest key when full, and says which', () {
              applyAll([add(a), add(b)]);

              final applied = apply(add(c));

              expect(list().value, [c, b]);
              expect(applied.evicted, a);
            });

            test('pushes out nothing when there is room', () {
              expect(apply(add(a)).evicted, isNull);
            });

            test('pushes out nothing when the key was listed', () {
              applyAll([add(a), add(b)]);

              expect(apply(add(a)).evicted, isNull);
            });

            test('removes a key and keeps the order of the rest', () {
              applyAll([add(a), add(b), remove(b)]);

              expect(list().value, [a]);
            });

            test('changes nothing when removing a key not listed', () async {
              apply(add(a));
              signals.clear();

              final applied = apply(remove(b));

              expect(list().value, [a]);
              expect(signals, isEmpty);
              expect(applied.isPending, isFalse);
              expect(await applied.outcome, EditOutcome.unchanged);
            });

            test('changes nothing when adding the first key again', () async {
              apply(add(a));
              signals.clear();

              expect(await apply(add(a)).outcome, EditOutcome.unchanged);
              expect(signals, isEmpty);
            });

            test('hands out a list that cannot be changed', () {
              apply(add(a));

              expect(() => list().value.add(b), throwsUnsupportedError);
            });
          });
        }

        test('keeps each list to its own limit', () async {
          library.dispose();
          await open(
            limits: const LibraryLimits(
              favouriteStickers: 1,
              savedGifs: 3,
              recentStickers: 2,
            ),
          );

          for (final key in [a, b, c]) {
            applyAll([
              LibraryEdit.favouriteSticker(key),
              LibraryEdit.saveGif(key),
              LibraryEdit.addRecentSticker(key),
            ]);
          }

          expect(library.favouriteStickers.value, [c]);
          expect(library.savedGifs.value, [c, b, a]);
          expect(library.recentStickers.value, [c, b]);
        });

        test('keeps the lists apart', () {
          applyAll([
            const LibraryEdit.addRecentSticker(a),
            const LibraryEdit.favouriteSticker(b),
            const LibraryEdit.saveGif(gif),
          ]);

          expect(library.recentStickers.value, [a]);
          expect(library.favouriteStickers.value, [b]);
          expect(library.savedGifs.value, [gif]);
        });
      });

      group('packs', () {
        test('installs a pack first among its kind', () {
          applyAll([
            const LibraryEdit.installPack(cats, stickers),
            const LibraryEdit.installPack(dogs, stickers),
          ]);

          expect(library.installedPacks(stickers).value, [dogs, cats]);
          expect(library.installStateOf(dogs), PackInstallState.installed);
        });

        test('keeps the packs of each kind apart', () {
          applyAll([
            const LibraryEdit.installPack(cats, stickers),
            const LibraryEdit.installPack(dogs, PackKind.emoji),
          ]);

          expect(library.installedPacks(stickers).value, [cats]);
          expect(library.installedPacks(PackKind.emoji).value, [dogs]);
          expect(library.installedPacks(PackKind.masks).value, isEmpty);
        });

        test('archives an installed pack to the front of the archive', () {
          applyAll([
            const LibraryEdit.installPack(cats, stickers),
            const LibraryEdit.installPack(dogs, stickers),
            const LibraryEdit.archivePack(cats, stickers),
            const LibraryEdit.archivePack(dogs, stickers),
          ]);

          expect(library.installedPacks(stickers).value, isEmpty);
          expect(library.archivedPacks(stickers).value, [dogs, cats]);
          expect(library.installStateOf(cats), PackInstallState.archived);
        });

        test('does not archive a pack that is not installed', () async {
          final applied = apply(const LibraryEdit.archivePack(cats, stickers));

          expect(await applied.outcome, EditOutcome.unchanged);
          expect(library.archivedPacks(stickers).value, isEmpty);
        });

        test('installs an archived pack out of the archive', () {
          applyAll([
            const LibraryEdit.installPack(cats, stickers),
            const LibraryEdit.archivePack(cats, stickers),
            const LibraryEdit.installPack(cats, stickers),
          ]);

          expect(library.installedPacks(stickers).value, [cats]);
          expect(library.archivedPacks(stickers).value, isEmpty);
        });

        test('removes a pack, installed or archived', () {
          applyAll([
            const LibraryEdit.installPack(cats, stickers),
            const LibraryEdit.installPack(dogs, stickers),
            const LibraryEdit.archivePack(dogs, stickers),
            const LibraryEdit.removePack(cats, stickers),
            const LibraryEdit.removePack(dogs, stickers),
          ]);

          expect(library.installedPacks(stickers).value, isEmpty);
          expect(library.archivedPacks(stickers).value, isEmpty);
          expect(library.installStateOf(cats), PackInstallState.notInstalled);
        });

        test('reorders the named packs, then the rest in their order', () {
          applyAll([
            const LibraryEdit.installPack(cats, stickers),
            const LibraryEdit.installPack(dogs, stickers),
            const LibraryEdit.installPack(owls, stickers),
            LibraryEdit.reorderPacks(stickers, const [
              cats,
              PackId('ghost'),
              owls,
            ]),
          ]);

          expect(library.installedPacks(stickers).value, [cats, owls, dogs]);
        });
      });

      group('signals', () {
        test('go out once per edit, only from the lists it changed', () {
          apply(const LibraryEdit.favouriteSticker(a));
          apply(const LibraryEdit.installPack(cats, stickers));
          apply(const LibraryEdit.archivePack(cats, stickers));

          expect(signals, {
            'favourite': 1,
            'installed.stickers': 2,
            'archived.stickers': 1,
          });
        });

        test('arrive with the edit already shown', () {
          List<ContentKey>? seen;
          library.savedGifs.addListener(() => seen = library.savedGifs.value);

          apply(const LibraryEdit.saveGif(gif));

          expect(seen, [gif]);
        });
      });

      group('undo window', () {
        const window = Duration(minutes: 1);

        test('shows the edit at once and keeps it pending', () {
          final applied = apply(
            const LibraryEdit.favouriteSticker(a),
            undoWindow: window,
          );

          expect(library.favouriteStickers.value, [a]);
          expect(applied.isPending, isTrue);
        });

        test('takes the edit back on undo, with a signal', () async {
          final applied = apply(
            const LibraryEdit.favouriteSticker(a),
            undoWindow: window,
          );
          signals.clear();

          expect(applied.undo(), isTrue);

          expect(library.favouriteStickers.value, isEmpty);
          expect(signals, {'favourite': 1});
          expect(applied.isPending, isFalse);
          expect(await applied.outcome, EditOutcome.undone);
        });

        test('brings a removed pack back to its own place', () {
          applyAll([
            const LibraryEdit.installPack(cats, stickers),
            const LibraryEdit.installPack(dogs, stickers),
            const LibraryEdit.installPack(owls, stickers),
          ]);
          final removal = apply(
            const LibraryEdit.removePack(dogs, stickers),
            undoWindow: window,
          );

          removal.undo();

          expect(library.installedPacks(stickers).value, [owls, dogs, cats]);
        });

        test('keeps the edits applied after the one taken back', () {
          final first = apply(
            const LibraryEdit.favouriteSticker(a),
            undoWindow: window,
          );
          apply(const LibraryEdit.favouriteSticker(b));

          first.undo();

          expect(library.favouriteStickers.value, [b]);
        });

        test('commits when the window ends', () async {
          final applied = apply(
            const LibraryEdit.saveGif(gif),
            undoWindow: const Duration(milliseconds: 1),
          );

          expect(await applied.outcome, EditOutcome.committed);
          expect(applied.isPending, isFalse);
          expect(applied.undo(), isFalse);
          expect(library.savedGifs.value, [gif]);
        });

        test('commits early on commit', () async {
          final applied = apply(
            const LibraryEdit.saveGif(gif),
            undoWindow: window,
          );

          applied.commit();

          expect(applied.isPending, isFalse);
          expect(applied.undo(), isFalse);
          expect(await applied.outcome, EditOutcome.committed);
        });

        test('commits at once with no window', () async {
          final applied = apply(const LibraryEdit.saveGif(gif));

          expect(applied.isPending, isFalse);
          expect(applied.undo(), isFalse);
          expect(await applied.outcome, EditOutcome.committed);
        });

        test('lets a later edit wait for an earlier one still pending', () {
          final first = apply(
            const LibraryEdit.saveGif(gif),
            undoWindow: window,
          );
          final second = apply(const LibraryEdit.favouriteSticker(a));

          expect(second.isPending, isTrue);
          first.commit();
          expect(second.isPending, isFalse);
        });
      });

      group('after dispose', () {
        test('commits what was pending', () async {
          final applied = apply(
            const LibraryEdit.saveGif(gif),
            undoWindow: const Duration(minutes: 1),
          );

          library.dispose();

          expect(await applied.outcome, EditOutcome.committed);
        });

        test('keeps its lists and ignores edits, silently', () async {
          apply(const LibraryEdit.saveGif(gif));
          library.dispose();
          signals.clear();

          final applied = apply(const LibraryEdit.unsaveGif(gif));

          expect(library.savedGifs.value, [gif]);
          expect(await applied.outcome, EditOutcome.unchanged);
          expect(signals, isEmpty);
        });

        test('can be disposed twice', () {
          library.dispose();

          expect(library.dispose, returnsNormally);
        });
      });
    });
  }
}
