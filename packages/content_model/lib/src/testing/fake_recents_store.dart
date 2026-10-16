import 'package:content_model/content_model.dart';
import 'package:content_model/src/store/recents_ledger.dart';
import 'package:listen/listen.dart';

/// An in-memory [RecentsStore] for tests, with nothing persisted.
///
/// Follows the whole seam contract. Use it to drive a page or host without
/// storage; use the reference store over a `FakeKeyValueStore` when the test
/// is about what reaches storage.
final class FakeRecentsStore with ChangeNotifier implements RecentsStore {
  /// Creates an empty store holding at most [capacity] keys per kind.
  FakeRecentsStore({int capacity = 48})
    : _ledger = RecentsLedger(capacity: capacity);

  final RecentsLedger _ledger;
  var _disposed = false;
  var _clock = 0;

  @override
  Listenable get changes => this;

  @override
  List<ContentKey> recents(SemanticKind kind) => _ledger.keysOf(kind);

  @override
  Future<void> record(
    ContentKey key, {
    required SemanticKind kind,
    PickSource source = PickSource.collection,
  }) async {
    if (_disposed || source == PickSource.search) return;
    _ledger.record(kind, key, now: ++_clock);
    notifyListeners();
  }

  @override
  Future<void> remove(ContentKey key, {required SemanticKind kind}) async {
    if (_disposed) return;
    if (_ledger.remove(kind, key)) notifyListeners();
  }

  @override
  Future<void> clear({SemanticKind? kind}) async {
    if (_disposed) return;
    if (_ledger.clear(kind: kind).isNotEmpty) notifyListeners();
  }

  // Idempotent: ChangeNotifier asserts on a second dispose, the seam does not.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
