import 'package:content_model/content_model.dart';
import 'package:content_model/src/testing/fake_gate.dart';
import 'package:listen/listen.dart';

/// An in-memory [PackSource] for tests, serving a fixed set of packs.
///
/// Follows the whole seam contract (it is the reference memory tier over a
/// scripted backend). [failure] makes every fetch fail, [gate] holds fetches
/// until the test releases them, [publish] changes what a later fetch serves,
/// and [fetches] counts what reached the backend.
final class FakePackSource implements PackSource {
  /// Creates a source that finds [packs] and answers any other id as not
  /// found.
  FakePackSource([Iterable<Pack> packs = const []])
    : _served = {for (final pack in packs) pack.id: pack} {
    _source = CachingPackSource(_fetch);
  }

  final Map<PackId, Pack> _served;
  final _fetches = <PackId, int>{};
  late final CachingPackSource _source;

  /// Holds every fetch while paused.
  final gate = FakeGate();

  /// When non-null, every fetch fails with it.
  Exception? failure;

  /// Serves [pack] for its id from the next fetch on.
  void publish(Pack pack) => _served[pack.id] = pack;

  /// How many fetches of [id] reached the backend.
  int fetches(PackId id) => _fetches[id] ?? 0;

  Future<Pack?> _fetch(PackId id) async {
    _fetches[id] = fetches(id) + 1;
    await gate.turn();
    if (failure case final failure?) throw failure;
    return _served[id];
  }

  @override
  Listenable get changes => _source.changes;

  @override
  PackLookup peek(PackId id) => _source.peek(id);

  @override
  Future<PackLookup> lookup(PackId id, {bool refresh = false}) =>
      _source.lookup(id, refresh: refresh);

  @override
  void dispose() => _source.dispose();
}
