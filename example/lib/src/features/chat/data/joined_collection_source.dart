import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// One [CollectionSource] over several: the collections of each part, in the
/// order of the parts, as one list.
///
/// It is how the emoji page lists the emoji catalogue and, after its
/// categories, the packs of custom emoji, as the reference clients do: the
/// page takes one source, and neither source should know the other.
///
/// Every change of a part publishes one new joined list. A command goes to the
/// part that lists the collection, and does nothing for an id no part lists.
/// The parts must list disjoint ids (the seam allows one collection per id).
///
/// It owns no part: [dispose] stops listening and publishing, and the parts
/// stay their owner's to dispose.
final class JoinedCollectionSource implements CollectionSource {
  /// Joins [parts], in order.
  JoinedCollectionSource(List<CollectionSource> parts)
    : _parts = List.unmodifiable(parts) {
    _collections = listen.ValueNotifier(_join());
    for (final part in _parts) {
      part.collections.addListener(_republish);
    }
  }

  final List<CollectionSource> _parts;
  late final listen.ValueNotifier<List<Collection>> _collections;
  var _disposed = false;

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  @override
  Future<void> load(CollectionId id) async => _partOf(id)?.load(id);

  @override
  Future<void> loadMore(CollectionId id) async => _partOf(id)?.loadMore(id);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final part in _parts) {
      part.collections.removeListener(_republish);
    }
    _collections.dispose();
  }

  CollectionSource? _partOf(CollectionId id) {
    if (_disposed) return null;
    for (final part in _parts) {
      if (part.collections.value.any((collection) => collection.id == id)) {
        return part;
      }
    }
    return null;
  }

  void _republish() {
    if (!_disposed) _collections.value = _join();
  }

  List<Collection> _join() {
    final joined = [for (final part in _parts) ...part.collections.value];
    assert(
      joined.map((collection) => collection.id).toSet().length == joined.length,
      'The parts of a JoinedCollectionSource list the same collection id.',
    );
    return List.unmodifiable(joined);
  }
}
