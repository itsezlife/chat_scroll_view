import 'package:content_model/src/data/content_library.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/pack/pack.dart';
import 'package:content_model/src/value_equality.dart';
import 'package:meta/meta.dart';

/// Every list of a [ContentLibrary] at one moment.
///
/// A value: lists are copied and unmodifiable, and a pack kind with no packs
/// equals one that was never mentioned.
@immutable
final class LibraryState {
  /// Creates a state; every list defaults to empty.
  LibraryState({
    List<ContentKey> recentStickers = const [],
    List<ContentKey> favouriteStickers = const [],
    List<ContentKey> savedGifs = const [],
    Map<PackKind, List<PackId>> installedPacks = const {},
    Map<PackKind, List<PackId>> archivedPacks = const {},
  }) : recentStickers = List.unmodifiable(recentStickers),
       favouriteStickers = List.unmodifiable(favouriteStickers),
       savedGifs = List.unmodifiable(savedGifs),
       _installed = _packLists(installedPacks),
       _archived = _packLists(archivedPacks);

  /// The library with nothing in it.
  static final LibraryState empty = LibraryState();

  /// The recent stickers, most recent first.
  final List<ContentKey> recentStickers;

  /// The favourite stickers, most recently marked first.
  final List<ContentKey> favouriteStickers;

  /// The saved GIFs, most recent first.
  final List<ContentKey> savedGifs;

  final Map<PackKind, List<PackId>> _installed;
  final Map<PackKind, List<PackId>> _archived;

  /// The installed packs of [kind], in the user's order.
  List<PackId> installedPacks(PackKind kind) => _installed[kind] ?? const [];

  /// The archived packs of [kind], most recently archived first.
  List<PackId> archivedPacks(PackKind kind) => _archived[kind] ?? const [];

  /// This state with the lists given replaced.
  LibraryState copyWith({
    List<ContentKey>? recentStickers,
    List<ContentKey>? favouriteStickers,
    List<ContentKey>? savedGifs,
    Map<PackKind, List<PackId>>? installedPacks,
    Map<PackKind, List<PackId>>? archivedPacks,
  }) => LibraryState(
    recentStickers: recentStickers ?? this.recentStickers,
    favouriteStickers: favouriteStickers ?? this.favouriteStickers,
    savedGifs: savedGifs ?? this.savedGifs,
    installedPacks: {..._installed, ...?installedPacks},
    archivedPacks: {..._archived, ...?archivedPacks},
  );

  static Map<PackKind, List<PackId>> _packLists(
    Map<PackKind, List<PackId>> lists,
  ) => Map.unmodifiable({
    for (final MapEntry(:key, :value) in lists.entries)
      if (value.isNotEmpty) key: List<PackId>.unmodifiable(value),
  });

  @override
  bool operator ==(Object other) {
    if (other is! LibraryState) return false;
    if (!ValueEquality.lists(other.recentStickers, recentStickers) ||
        !ValueEquality.lists(other.favouriteStickers, favouriteStickers) ||
        !ValueEquality.lists(other.savedGifs, savedGifs)) {
      return false;
    }
    for (final kind in PackKind.values) {
      if (!ValueEquality.lists(
            other.installedPacks(kind),
            installedPacks(kind),
          ) ||
          !ValueEquality.lists(
            other.archivedPacks(kind),
            archivedPacks(kind),
          )) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(recentStickers),
    Object.hashAll(favouriteStickers),
    Object.hashAll(savedGifs),
    Object.hashAll([
      for (final kind in PackKind.values) ...[
        Object.hashAll(installedPacks(kind)),
        Object.hashAll(archivedPacks(kind)),
      ],
    ]),
  );

  @override
  String toString() =>
      'LibraryState(${recentStickers.length} recent, '
      '${favouriteStickers.length} favourite, ${savedGifs.length} saved, '
      '${[for (final kind in PackKind.values) installedPacks(kind).length].reduce((a, b) => a + b)} packs)';
}

/// Where a [ContentLibrary] keeps its lists: the persistence adapter seam.
///
/// The library hands every committed [LibraryEdit] over together with the
/// whole committed [LibraryState] after it, in the order the edits were
/// applied. An adapter over a local store keeps the state and may ignore the
/// edit; an adapter over a backend sends the edit and may keep the state as
/// its cache.
///
/// ## Failure
///
/// [read] fails when the storage cannot be reached; a record it cannot
/// understand is read as empty, never as an error. A failed [commit] left
/// what is stored as it was, and the next successful [commit] stores the whole
/// state it is given, so a lost write is repaired by the next one.
abstract interface class LibraryStorage {
  /// The library as last committed; [LibraryState.empty] when nothing was.
  Future<LibraryState> read();

  /// Stores [state], the committed library after [edit].
  Future<void> commit(LibraryEdit edit, LibraryState state);
}
