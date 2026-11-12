import 'dart:convert';

import 'package:content_model/src/data/content_library.dart';
import 'package:content_model/src/data/key_value_store.dart';
import 'package:content_model/src/data/library_storage.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/pack/pack.dart';
import 'package:content_model/src/store/store_name.dart';

/// The [LibraryStorage] over a [KeyValueStore]: keeps the committed state and
/// ignores the edit, as a local store has nobody to send it to.
///
/// ## Records
///
/// One record per list that holds something, in the namespace given:
/// `recent_stickers`, `favourite_stickers`, `saved_gifs`,
/// `installed_packs.<kind>` and `archived_packs.<kind>` (the kind's
/// [PackKind.value]). The value is JSON at schema version [recordVersion]:
///
/// ```json
/// {"items": ["document:5368", "unicode:1F44D"]}
/// ```
///
/// Content keys are written as [ContentKey.encoded], pack ids as their text.
/// A list that empties loses its record. A record of another version or of
/// another shape reads as an empty list, an item that cannot be read is
/// skipped; the next commit of that list replaces the record.
///
/// ## Writing
///
/// A commit writes only the records whose list differs from what this
/// storage last read or wrote, all of them when it knows neither. A record
/// that failed to write is written again at the next commit.
final class KeyValueLibraryStorage implements LibraryStorage {
  /// Creates the storage over [store], in [namespace], which must be a valid
  /// [KeyValueStore] name (an [ArgumentError] otherwise).
  KeyValueLibraryStorage(KeyValueStore store, {required String namespace})
    : _store = store,
      _namespace = namespace {
    StoreName.check(namespace, 'namespace');
  }

  /// The schema version of the records this storage writes and reads.
  static const int recordVersion = 1;

  final KeyValueStore _store;
  final String _namespace;

  // What each record holds as far as this storage knows: read or written.
  final _$known = <String, List<String>>{};

  @override
  Future<LibraryState> read() async {
    final lists = await Future.wait([
      for (final name in _names) _readList(name),
    ]);
    final byName = {
      for (var i = 0; i < _names.length; i++) _names[i]: lists[i],
    };
    return LibraryState(
      recentStickers: _keys(byName[_recentStickers]!),
      favouriteStickers: _keys(byName[_favouriteStickers]!),
      savedGifs: _keys(byName[_savedGifs]!),
      installedPacks: {
        for (final kind in PackKind.values)
          kind: [for (final id in byName[_installed(kind)]!) PackId(id)],
      },
      archivedPacks: {
        for (final kind in PackKind.values)
          kind: [for (final id in byName[_archived(kind)]!) PackId(id)],
      },
    );
  }

  @override
  Future<void> commit(LibraryEdit edit, LibraryState state) async {
    final lists = _listsOf(state);
    await Future.wait([
      for (final MapEntry(key: name, value: items) in lists.entries)
        if (!_same(_$known[name], items)) _writeList(name, items),
    ]);
  }

  Future<List<String>> _readList(String name) async {
    final stored = await _store.read(_namespace, name);
    final items = _decode(stored);
    _$known[name] = items;
    return items;
  }

  Future<void> _writeList(String name, List<String> items) async {
    // Forgotten first: a write that fails leaves the record unknown, so the
    // next commit writes it again whatever it holds.
    _$known.remove(name);
    if (items.isEmpty) {
      await _store.remove(_namespace, name);
    } else {
      await _store.write(
        _namespace,
        name,
        StoredValue(jsonEncode({'items': items}), version: recordVersion),
      );
    }
    _$known[name] = items;
  }

  static const _recentStickers = 'recent_stickers';
  static const _favouriteStickers = 'favourite_stickers';
  static const _savedGifs = 'saved_gifs';
  static String _installed(PackKind kind) => 'installed_packs.${kind.value}';
  static String _archived(PackKind kind) => 'archived_packs.${kind.value}';

  static final List<String> _names = [
    _recentStickers,
    _favouriteStickers,
    _savedGifs,
    for (final kind in PackKind.values) ...[_installed(kind), _archived(kind)],
  ];

  static Map<String, List<String>> _listsOf(LibraryState state) => {
    _recentStickers: [for (final key in state.recentStickers) key.encoded],
    _favouriteStickers: [
      for (final key in state.favouriteStickers) key.encoded,
    ],
    _savedGifs: [for (final key in state.savedGifs) key.encoded],
    for (final kind in PackKind.values) ...{
      _installed(kind): [for (final id in state.installedPacks(kind)) id.value],
      _archived(kind): [for (final id in state.archivedPacks(kind)) id.value],
    },
  };

  static List<ContentKey> _keys(List<String> encoded) => [
    for (final text in encoded) ?ContentKey.tryParse(text),
  ];

  static List<String> _decode(StoredValue? stored) {
    if (stored == null || stored.version != recordVersion) return const [];
    final Object? json;
    try {
      json = jsonDecode(stored.value);
    } on FormatException {
      return const [];
    }
    if (json case {'items': final List<Object?> items}) {
      return [
        for (final item in items)
          if (item case final String text when text.isNotEmpty) text,
      ];
    }
    return const [];
  }

  static bool _same(List<String>? known, List<String> items) {
    if (known == null || known.length != items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (known[i] != items[i]) return false;
    }
    return true;
  }
}
