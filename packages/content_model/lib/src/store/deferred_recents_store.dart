import 'package:content_model/src/data/recents_store.dart';
import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:listen/listen.dart';

/// A [RecentsStore] that shows the recents of another as of its last
/// [commit], not as of now.
///
/// A panel that lists the recents first, and that the user picks from, would
/// reorder its own grid under their finger on every pick: the emoji just
/// chosen jumps to the front and everything shifts. The host puts this view
/// between the panel's sources and the real store and decides when the panel
/// may catch up (when it opens, when search ends); picks in between are
/// recorded in the real store at once and counted the next time.
///
/// ## Behaviour
///
/// - [recents] answers from the snapshot taken at construction and at each
///   [commit]; [changes] signals when a [commit] changed a list.
/// - [record] goes to the real store and changes nothing here.
/// - [clear] goes to the real store and commits at once: what the user asked
///   to forget is not shown a moment longer.
/// - [remove] goes to the real store and takes the key out of what is shown at
///   once, and only that: other picks still wait for the next [commit], so
///   forgetting one emoji does not reorder the grid under the pointer. A pick
///   of the same key recorded earlier and not yet shown is forgotten with it
///   (the real store drops the key whole); one recorded after counts again
///   from one, shown at the next commit.
/// - The view follows the real store only through [commit]: a change made by
///   anyone else is picked up at the next one.
///
/// The view does not own the real store: [dispose] releases the view only.
final class DeferredRecentsStore with ChangeNotifier implements RecentsStore {
  /// A view of [store], showing what it holds now.
  DeferredRecentsStore(RecentsStore store) : _store = store {
    _shown = _snapshot();
  }

  final RecentsStore _store;
  late Map<SemanticKind, List<ContentKey>> _shown;
  var _disposed = false;

  @override
  Listenable get changes => this;

  @override
  List<ContentKey> recents(SemanticKind kind) => _shown[kind] ?? const [];

  /// Shows what the real store holds now; signals [changes] when that differs
  /// from what was shown.
  void commit() {
    if (_disposed) return;
    final next = _snapshot();
    var changed = false;
    for (final kind in SemanticKind.values) {
      if (!_sameKeys(_shown[kind], next[kind])) changed = true;
    }
    _shown = next;
    if (changed) notifyListeners();
  }

  @override
  Future<void> record(
    ContentKey key, {
    required SemanticKind kind,
    PickSource source = PickSource.collection,
  }) => _store.record(key, kind: kind, source: source);

  @override
  Future<void> clear({SemanticKind? kind}) async {
    await _store.clear(kind: kind);
    commit();
  }

  @override
  Future<void> remove(ContentKey key, {required SemanticKind kind}) async {
    await _store.remove(key, kind: kind);
    final shown = _shown[kind];
    if (_disposed || shown == null || !shown.contains(key)) return;
    _shown = {
      ..._shown,
      kind: List.unmodifiable([
        for (final listed in shown)
          if (listed != key) listed,
      ]),
    };
    notifyListeners();
  }

  // Idempotent: ChangeNotifier asserts on a second dispose, the seam does not.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  Map<SemanticKind, List<ContentKey>> _snapshot() => {
    for (final kind in SemanticKind.values)
      kind: List.unmodifiable(_store.recents(kind)),
  };

  static bool _sameKeys(List<ContentKey>? a, List<ContentKey>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
