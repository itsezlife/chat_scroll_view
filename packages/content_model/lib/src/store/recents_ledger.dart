import 'package:content_model/src/data/recents_store.dart';
import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:meta/meta.dart';

/// How often and when one key was last picked, within one kind.
@immutable
final class RecentsEntry {
  /// Creates an entry. [count] is at least 1.
  const RecentsEntry(this.key, {required this.count, required this.lastUsed})
    : assert(count > 0, 'a recorded key has been picked at least once');

  /// The picked content.
  final ContentKey key;

  /// How many counted picks the key has had.
  final int count;

  /// When the latest pick happened, in milliseconds since the epoch. Unique
  /// within a [RecentsLedger], so recency never ties.
  final int lastUsed;

  @override
  bool operator ==(Object other) =>
      other is RecentsEntry &&
      other.key == key &&
      other.count == count &&
      other.lastUsed == lastUsed;

  @override
  int get hashCode => Object.hash(key, count, lastUsed);

  @override
  String toString() => 'RecentsEntry($key, x$count, @$lastUsed)';
}

/// The ranking rules of [RecentsStore], without storage or signalling: what
/// is counted per kind, how it is ordered and what falls off at capacity.
///
/// The reference store and the fake both keep their state here, so the rules
/// have one implementation and each store adds only what it owns (persisting,
/// signalling).
final class RecentsLedger {
  /// Creates an empty ledger holding at most [capacity] keys per kind.
  RecentsLedger({required this.capacity}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
  }

  /// The most keys one kind holds.
  final int capacity;

  final _entries = <SemanticKind, List<RecentsEntry>>{};
  final _keys = <SemanticKind, List<ContentKey>>{};
  var _latest = 0;

  /// The keys of [kind], best first. Unmodifiable.
  List<ContentKey> keysOf(SemanticKind kind) =>
      _keys[kind] ?? const <ContentKey>[];

  /// The entries of [kind], best first. Unmodifiable.
  List<RecentsEntry> entriesOf(SemanticKind kind) =>
      _entries[kind] ?? const <RecentsEntry>[];

  /// Counts one pick of [key] under [kind] at time [now].
  ///
  /// A new key into a full kind pushes out the key that ranked last before it,
  /// so the pick that was just made is always listed. The time stored is
  /// [now], or one past the latest time the ledger has seen when [now] is not
  /// later, so two picks never tie on recency.
  void record(SemanticKind kind, ContentKey key, {required int now}) {
    final at = now > _latest ? now : _latest + 1;
    _latest = at;
    final entries = List.of(entriesOf(kind));
    final index = entries.indexWhere((entry) => entry.key == key);
    if (index >= 0) {
      final old = entries.removeAt(index);
      entries.add(RecentsEntry(key, count: old.count + 1, lastUsed: at));
    } else {
      if (entries.length >= capacity) entries.removeLast();
      entries.add(RecentsEntry(key, count: 1, lastUsed: at));
    }
    _set(kind, entries);
  }

  /// Forgets [kind], or every kind when it is null. Returns the kinds that
  /// held something, which are the ones that changed.
  Set<SemanticKind> clear({SemanticKind? kind}) {
    final cleared = {
      for (final held in _entries.keys)
        if ((kind == null || held == kind) && _entries[held]!.isNotEmpty) held,
    };
    for (final held in cleared) {
      _set(held, const []);
    }
    return cleared;
  }

  /// Replaces [kind] with [entries], for a store that read them back from
  /// storage. Keeps the best [capacity] of them, and the first of any key
  /// that appears twice.
  void restore(SemanticKind kind, Iterable<RecentsEntry> entries) {
    final seen = <ContentKey>{};
    for (final entry in entries) {
      if (entry.lastUsed > _latest) _latest = entry.lastUsed;
    }
    _set(kind, [
      for (final entry in entries)
        if (seen.add(entry.key)) entry,
    ]);
  }

  void _set(SemanticKind kind, List<RecentsEntry> entries) {
    final ranked = List.of(entries)..sort(_rank);
    final kept = ranked.length > capacity
        ? ranked.sublist(0, capacity)
        : ranked;
    if (kept.isEmpty) {
      _entries.remove(kind);
      _keys.remove(kind);
      return;
    }
    _entries[kind] = List<RecentsEntry>.unmodifiable(kept);
    _keys[kind] = List<ContentKey>.unmodifiable([
      for (final entry in kept) entry.key,
    ]);
  }

  // Most picked first, then latest first. The key's encoding is only a last
  // resort for stored data that repeats a time; live picks never tie.
  static int _rank(RecentsEntry a, RecentsEntry b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    final byTime = b.lastUsed.compareTo(a.lastUsed);
    if (byTime != 0) return byTime;
    return a.key.encoded.compareTo(b.key.encoded);
  }
}
