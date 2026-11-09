import 'package:content_model/src/data/content_library.dart';
import 'package:content_model/src/data/library_storage.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/pack/pack.dart';

/// The rules of [LibraryEdit] as a pure function over [LibraryState]: what
/// each edit does to the lists, and how lists are held to [LibraryLimits].
///
/// One implementation for every library, and for replaying the edits still
/// inside their undo window over the committed state.
abstract final class LibraryRules {
  /// [state] after [edit], held to [limits].
  static LibraryState apply(
    LibraryState state,
    LibraryEdit edit,
    LibraryLimits limits,
  ) => switch (edit) {
    LibraryEdit$AddRecentSticker(:final key) => state.copyWith(
      recentStickers: _front(state.recentStickers, key, limits.recentStickers),
    ),
    LibraryEdit$RemoveRecentSticker(:final key) => state.copyWith(
      recentStickers: _without(state.recentStickers, key),
    ),
    LibraryEdit$FavouriteSticker(:final key) => state.copyWith(
      favouriteStickers: _front(
        state.favouriteStickers,
        key,
        limits.favouriteStickers,
      ),
    ),
    LibraryEdit$UnfavouriteSticker(:final key) => state.copyWith(
      favouriteStickers: _without(state.favouriteStickers, key),
    ),
    LibraryEdit$SaveGif(:final key) => state.copyWith(
      savedGifs: _front(state.savedGifs, key, limits.savedGifs),
    ),
    LibraryEdit$UnsaveGif(:final key) => state.copyWith(
      savedGifs: _without(state.savedGifs, key),
    ),
    LibraryEdit$InstallPack(:final id, :final kind) => state.copyWith(
      installedPacks: {kind: _front(state.installedPacks(kind), id, null)},
      archivedPacks: {kind: _without(state.archivedPacks(kind), id)},
    ),
    LibraryEdit$ArchivePack(:final id, :final kind)
        when state.installedPacks(kind).contains(id) =>
      state.copyWith(
        installedPacks: {kind: _without(state.installedPacks(kind), id)},
        archivedPacks: {kind: _front(state.archivedPacks(kind), id, null)},
      ),
    LibraryEdit$ArchivePack() => state,
    LibraryEdit$RemovePack(:final id, :final kind) => state.copyWith(
      installedPacks: {kind: _without(state.installedPacks(kind), id)},
      archivedPacks: {kind: _without(state.archivedPacks(kind), id)},
    ),
    LibraryEdit$ReorderPacks(:final kind, :final order) => state.copyWith(
      installedPacks: {kind: _reorder(state.installedPacks(kind), order)},
    ),
  };

  /// [state] with every most-recently-used list cut to [limits].
  static LibraryState fit(LibraryState state, LibraryLimits limits) =>
      state.copyWith(
        recentStickers: _cut(state.recentStickers, limits.recentStickers),
        favouriteStickers: _cut(
          state.favouriteStickers,
          limits.favouriteStickers,
        ),
        savedGifs: _cut(state.savedGifs, limits.savedGifs),
      );

  /// The key [edit] pushed out of a full list in going from [before] to
  /// [after], or null.
  static ContentKey? evicted(
    LibraryState before,
    LibraryState after,
    LibraryEdit edit,
  ) {
    final (was, now) = switch (edit) {
      LibraryEdit$AddRecentSticker() => (
        before.recentStickers,
        after.recentStickers,
      ),
      LibraryEdit$FavouriteSticker() => (
        before.favouriteStickers,
        after.favouriteStickers,
      ),
      LibraryEdit$SaveGif() => (before.savedGifs, after.savedGifs),
      _ => (const <ContentKey>[], const <ContentKey>[]),
    };
    for (final key in was) {
      if (!now.contains(key)) return key;
    }
    return null;
  }

  static List<T> _front<T>(List<T> list, T item, int? capacity) {
    final next = [
      item,
      for (final listed in list)
        if (listed != item) listed,
    ];
    return capacity == null ? next : _cut(next, capacity);
  }

  static List<T> _without<T>(List<T> list, T item) => [
    for (final listed in list)
      if (listed != item) listed,
  ];

  static List<T> _cut<T>(List<T> list, int capacity) =>
      list.length > capacity ? list.sublist(0, capacity) : list;

  static List<PackId> _reorder(List<PackId> installed, List<PackId> order) {
    final named = [
      for (final id in order.toSet())
        if (installed.contains(id)) id,
    ];
    return [
      ...named,
      for (final id in installed)
        if (!named.contains(id)) id,
    ];
  }
}
