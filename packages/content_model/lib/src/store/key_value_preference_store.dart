import 'dart:convert';

import 'package:content_model/src/data/key_value_store.dart';
import 'package:content_model/src/data/preference_store.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/observable/observable.dart';
import 'package:content_model/src/observable/observable_notifier.dart';
import 'package:content_model/src/store/store_name.dart';

/// The reference [PreferenceStore]: keeps the choices in memory and persists
/// them through a [KeyValueStore].
///
/// Obtained only through [load], which reads what was persisted before
/// returning, so there is no unloaded store whose first choices could be lost.
/// The constructor is private for that reason.
///
/// ## Record
///
/// One record, stored under the key `preferences` in the namespace given to
/// [load]. The value is JSON, written at schema version [recordVersion]:
///
/// ```json
/// {"variants": {"unicode:1F44D": "unicode:1F44D-1F3FF"}, "selectedPageId": "emoji", "dockPreferred": true}
/// ```
///
/// Keys are written as [ContentKey.encoded] and read back with
/// [ContentKey.tryParse]. A record of another version, or one that is not the
/// shape above, reads as no choices and is replaced by the next write; a
/// variants entry that cannot be read is skipped and the rest is kept. Once
/// no choice is left the record is removed. The store never migrates an older
/// version: it has none. The dock preference is written only while it is on and
/// read only from a boolean `true`, so a record from before it existed reads
/// as off.
///
/// ## Persisting
///
/// A setter that changes a choice changes memory, signals, and writes the
/// whole record, all before its future completes; the future then completes
/// when the write has (and fails if it failed, keeping the in-memory change,
/// as the contract says). A later successful write persists the whole record
/// again, so a lost write is repaired by the next one.
final class KeyValuePreferenceStore implements PreferenceStore {
  KeyValuePreferenceStore._(this._storage, this._namespace);

  /// The schema version of the record this store writes and reads.
  static const int recordVersion = 1;

  static const _recordKey = 'preferences';

  /// Creates the store over [storage], reading what is persisted under
  /// [namespace] first.
  ///
  /// [namespace] is the one the owning package keeps for itself (see
  /// [KeyValueStore]); an invalid one throws an [ArgumentError]. The returned
  /// future fails if [storage] cannot be read.
  static Future<KeyValuePreferenceStore> load(
    KeyValueStore storage, {
    required String namespace,
  }) async {
    checkStoreName(namespace, 'namespace');
    final store = KeyValuePreferenceStore._(storage, namespace);
    final stored = await storage.read(namespace, _recordKey);
    if (stored != null) store._restore(stored);
    return store;
  }

  final KeyValueStore _storage;
  final String _namespace;
  final _changes = ObservableNotifier();
  final _variants = <ContentKey$Unicode, ContentKey$Unicode>{};
  String? _selectedPageId;
  var _dockPreferred = false;

  @override
  Observable get changes => _changes;

  @override
  ContentKey$Unicode? preferredVariant(ContentKey$Unicode base) =>
      _variants[base];

  @override
  Future<void> setPreferredVariant(
    ContentKey$Unicode base,
    ContentKey$Unicode? variant,
  ) async {
    if (_changes.isDisposed || _variants[base] == variant) return;
    if (variant == null) {
      _variants.remove(base);
    } else {
      _variants[base] = variant;
    }
    _changes.notify();
    await _persist();
  }

  @override
  String? get selectedPageId => _selectedPageId;

  @override
  Future<void> setSelectedPageId(String? id) async {
    if (_changes.isDisposed || _selectedPageId == id) return;
    _selectedPageId = id;
    _changes.notify();
    await _persist();
  }

  @override
  bool get dockPreferred => _dockPreferred;

  @override
  Future<void> setDockPreferred({required bool preferred}) async {
    if (_changes.isDisposed || _dockPreferred == preferred) return;
    _dockPreferred = preferred;
    _changes.notify();
    await _persist();
  }

  @override
  void dispose() => _changes.dispose();

  // Reads the state after the signal, so a listener that sets again inside it
  // is written once with the final state rather than overtaken.
  Future<void> _persist() {
    if (_variants.isEmpty && _selectedPageId == null && !_dockPreferred) {
      return _storage.remove(_namespace, _recordKey);
    }
    return _storage.write(
      _namespace,
      _recordKey,
      StoredValue(
        jsonEncode({
          if (_variants.isNotEmpty)
            'variants': {
              for (final entry in _variants.entries)
                entry.key.encoded: entry.value.encoded,
            },
          'selectedPageId': ?_selectedPageId,
          if (_dockPreferred) 'dockPreferred': true,
        }),
        version: recordVersion,
      ),
    );
  }

  void _restore(StoredValue stored) {
    if (stored.version != recordVersion) return;
    final Object? json;
    try {
      json = jsonDecode(stored.value);
    } on FormatException {
      return;
    }
    if (json is! Map<String, Object?>) return;
    if (json['variants'] case final Map<String, Object?> variants) {
      for (final MapEntry(:key, :value) in variants.entries) {
        final base = ContentKey.tryParse(key);
        final variant = ContentKey.tryParse(value is String ? value : null);
        if (base is ContentKey$Unicode && variant is ContentKey$Unicode) {
          _variants[base] = variant;
        }
      }
    }
    if (json['selectedPageId'] case final String id) _selectedPageId = id;
    if (json['dockPreferred'] case true) _dockPreferred = true;
  }
}
