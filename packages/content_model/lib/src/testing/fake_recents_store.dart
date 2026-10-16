import 'package:content_model/content_model.dart';
import 'package:content_model/src/store/recents_ledger.dart';

/// An in-memory [RecentsStore] for tests, with nothing persisted.
///
/// Follows the whole seam contract. Use it to drive a page or host without
/// storage; use the reference store over a `FakeKeyValueStore` when the test
/// is about what reaches storage.
final class FakeRecentsStore implements RecentsStore {
  /// Creates an empty store holding at most [capacity] keys per kind.
  FakeRecentsStore({int capacity = 48})
    : _ledger = RecentsLedger(capacity: capacity);

  final RecentsLedger _ledger;
  final _changes = ObservableNotifier();
  var _clock = 0;

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
    _ledger.record(kind, key, now: ++_clock);
    _changes.notify();
  }

  @override
  Future<void> clear({SemanticKind? kind}) async {
    if (_changes.isDisposed) return;
    if (_ledger.clear(kind: kind).isNotEmpty) _changes.notify();
  }

  @override
  void dispose() => _changes.dispose();
}
