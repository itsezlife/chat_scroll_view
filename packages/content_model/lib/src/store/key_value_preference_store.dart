import 'dart:convert';

import 'package:content_model/src/data/key_value_store.dart';
import 'package:content_model/src/data/preference_store.dart';
import 'package:content_model/src/emoji/emoji_entry.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/store/store_name.dart';
import 'package:listen/listen.dart';

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
/// {"variants": {"unicode:1F44D": "unicode:1F44D-1F3FF"}, "defaultVariant": ["dark"], "selectedPageId": "emoji", "dockPreferred": true}
/// ```
///
/// `defaultVariant` is the default's tones by [SkinTone] name (an empty list
/// for the emoji as it is); a name that cannot be read drops the default.
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
final class KeyValuePreferenceStore
    with ChangeNotifier
    implements PreferenceStore {
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
  var _disposed = false;
  final _variants = <ContentKey$Unicode, ContentKey$Unicode>{};
  EmojiModifiers? _defaultVariant;
  String? _selectedPageId;
  var _dockPreferred = false;

  @override
  Listenable get changes => this;

  @override
  ContentKey$Unicode? preferredVariant(ContentKey$Unicode base) =>
      _variants[base];

  @override
  Future<void> setPreferredVariant(
    ContentKey$Unicode base,
    ContentKey$Unicode? variant,
  ) async {
    if (_disposed || _variants[base] == variant) return;
    if (variant == null) {
      _variants.remove(base);
    } else {
      _variants[base] = variant;
    }
    notifyListeners();
    await _persist();
  }

  @override
  EmojiModifiers? get defaultVariant => _defaultVariant;

  @override
  Future<void> setDefaultVariant(EmojiModifiers modifiers) async {
    if (_disposed || (_defaultVariant == modifiers && _variants.isEmpty)) {
      return;
    }
    _defaultVariant = modifiers;
    _variants.clear();
    notifyListeners();
    await _persist();
  }

  @override
  String? get selectedPageId => _selectedPageId;

  @override
  Future<void> setSelectedPageId(String? id) async {
    if (_disposed || _selectedPageId == id) return;
    _selectedPageId = id;
    notifyListeners();
    await _persist();
  }

  @override
  bool get dockPreferred => _dockPreferred;

  @override
  Future<void> setDockPreferred({required bool preferred}) async {
    if (_disposed || _dockPreferred == preferred) return;
    _dockPreferred = preferred;
    notifyListeners();
    await _persist();
  }

  // Idempotent: ChangeNotifier asserts on a second dispose, the seam does not.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  // Reads the state after the signal, so a listener that sets again inside it
  // is written once with the final state rather than overtaken.
  Future<void> _persist() {
    if (_variants.isEmpty &&
        _defaultVariant == null &&
        _selectedPageId == null &&
        !_dockPreferred) {
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
          if (_defaultVariant case final variant?)
            'defaultVariant': [for (final tone in variant.tones) tone.name],
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
    if (json case final Map<String, Object?> record) _restoreRecord(record);
  }

  void _restoreRecord(Map<String, Object?> json) {
    if (json['variants'] case final Map<String, Object?> variants) {
      for (final MapEntry(:key, :value) in variants.entries) {
        final base = ContentKey.tryParse(key);
        final variant = ContentKey.tryParse(switch (value) {
          final String encoded => encoded,
          _ => null,
        });
        if ((base, variant) case (
          final ContentKey$Unicode from,
          final ContentKey$Unicode to,
        )) {
          _variants[from] = to;
        }
      }
    }
    if (json['defaultVariant'] case final List<Object?> names) {
      final tones = [
        for (final name in names)
          for (final tone in SkinTone.values)
            if (tone.name == name) tone,
      ];
      if (tones.length == names.length) {
        _defaultVariant = EmojiModifiers(tones: tones);
      }
    }
    if (json['selectedPageId'] case final String id) _selectedPageId = id;
    if (json['dockPreferred'] case true) _dockPreferred = true;
  }
}
