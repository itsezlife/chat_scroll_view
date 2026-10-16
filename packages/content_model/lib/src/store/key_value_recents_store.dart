import 'dart:convert';

import 'package:content_model/src/data/key_value_store.dart';
import 'package:content_model/src/data/recents_store.dart';
import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/observable/observable.dart';
import 'package:content_model/src/observable/observable_notifier.dart';
import 'package:content_model/src/store/recents_ledger.dart';
import 'package:content_model/src/store/store_name.dart';

/// The reference [RecentsStore]: ranks picks in memory and persists them
/// through a [KeyValueStore].
///
/// Obtained only through [load], which reads what was persisted before
/// returning, so there is no unloaded store whose first picks could be lost.
/// The constructor is private for that reason.
///
/// ## Records
///
/// One record per [SemanticKind], stored under the key `recents.<kind>` (the
/// kind's [SemanticKind.value]) in the namespace given to [load]. The value is
/// JSON, written at schema version [recordVersion]:
///
/// ```json
/// {"entries": [{"key": "unicode:1F44D", "count": 3, "lastUsed": 1700000000000}]}
/// ```
///
/// A key is written as [ContentKey.encoded] and read back with
/// [ContentKey.tryParse], so unicode, document and external keys all
/// round-trip. A record of another version, or one that is not the shape
/// above, is treated as empty and replaced by the next write; an entry that
/// cannot be read is skipped and the rest of the record is kept. The store
/// never migrates an older version: it has none.
///
/// The ranking rules are the [RecentsStore] contract's; `lastUsed` is the
/// pick time in milliseconds from the clock given to [load], nudged forward
/// when needed so two picks never tie.
///
/// ## Persisting
///
/// A pick or clear changes memory, signals, and writes the records of the
/// kinds it touched, all before its future completes; the future then
/// completes when the write has (and fails if it failed, keeping the
/// in-memory change, as the contract says). A later successful write persists
/// the whole record again, so a lost write is repaired by the next one.
final class KeyValueRecentsStore implements RecentsStore {
  KeyValueRecentsStore._(
    this._storage,
    this._namespace,
    this._ledger,
    this._clock,
  );

  /// The most keys per kind a store holds unless told otherwise.
  static const int defaultCapacity = 48;

  /// The schema version of the records this store writes and reads.
  static const int recordVersion = 1;

  /// Creates the store over [storage], reading what is persisted under
  /// [namespace] first.
  ///
  /// [namespace] is the one the owning package keeps for itself (see
  /// [KeyValueStore]); an invalid one throws an [ArgumentError], as does a
  /// [capacity] below 1. The returned future fails if [storage] cannot be
  /// read. [clock] tells the time of a pick and exists for tests.
  static Future<KeyValueRecentsStore> load(
    KeyValueStore storage, {
    required String namespace,
    int capacity = defaultCapacity,
    DateTime Function() clock = DateTime.now,
  }) async {
    checkStoreName(namespace, 'namespace');
    final ledger = RecentsLedger(capacity: capacity);
    const kinds = SemanticKind.values;
    final stored = await Future.wait([
      for (final kind in kinds) storage.read(namespace, _nameOf(kind)),
    ]);
    for (var i = 0; i < kinds.length; i++) {
      final value = stored[i];
      if (value == null) continue;
      ledger.restore(kinds[i], _decode(value));
    }
    return KeyValueRecentsStore._(storage, namespace, ledger, clock);
  }

  final KeyValueStore _storage;
  final String _namespace;
  final RecentsLedger _ledger;
  final DateTime Function() _clock;
  final _changes = ObservableNotifier();

  @override
  Observable get changes => _changes;

  @override
  List<ContentKey> recents(SemanticKind kind) => _ledger.keysOf(kind);

  @override
  Future<void> record(
    ContentKey key, {
    required SemanticKind kind,
    PickSource source = PickSource.collection,
  }) async {
    if (_changes.isDisposed || source == PickSource.search) return;
    _ledger.record(kind, key, now: _clock().millisecondsSinceEpoch);
    _changes.notify();
    await _persist(kind);
  }

  @override
  Future<void> clear({SemanticKind? kind}) async {
    if (_changes.isDisposed) return;
    final cleared = _ledger.clear(kind: kind);
    if (cleared.isEmpty) return;
    _changes.notify();
    await Future.wait([for (final kind in cleared) _persist(kind)]);
  }

  @override
  void dispose() => _changes.dispose();

  // Reads the ledger after the signal, so a listener that picks again inside
  // it is written once with the final state rather than overtaken.
  Future<void> _persist(SemanticKind kind) {
    final entries = _ledger.entriesOf(kind);
    final name = _nameOf(kind);
    if (entries.isEmpty) return _storage.remove(_namespace, name);
    return _storage.write(
      _namespace,
      name,
      StoredValue(_encode(entries), version: recordVersion),
    );
  }

  static String _nameOf(SemanticKind kind) => 'recents.${kind.value}';

  static String _encode(List<RecentsEntry> entries) => jsonEncode({
    'entries': [
      for (final entry in entries)
        {
          'key': entry.key.encoded,
          'count': entry.count,
          'lastUsed': entry.lastUsed,
        },
    ],
  });

  static List<RecentsEntry> _decode(StoredValue stored) {
    if (stored.version != recordVersion) return const [];
    final Object? json;
    try {
      json = jsonDecode(stored.value);
    } on FormatException {
      return const [];
    }
    if (json is! Map<String, Object?>) return const [];
    final entries = json['entries'];
    if (entries is! List<Object?>) return const [];
    return [for (final raw in entries) ?_decodeEntry(raw)];
  }

  static RecentsEntry? _decodeEntry(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final key = ContentKey.tryParse(switch (raw['key']) {
      final String encoded => encoded,
      _ => null,
    });
    final count = raw['count'];
    final lastUsed = raw['lastUsed'];
    if (key == null || count is! int || count < 1 || lastUsed is! int) {
      return null;
    }
    return RecentsEntry(key, count: count, lastUsed: lastUsed);
  }
}
