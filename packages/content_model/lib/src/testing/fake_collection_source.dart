import 'package:content_model/content_model.dart';
import 'package:content_model/src/testing/fake_gate.dart';
import 'package:content_model/src/testing/fake_pages.dart';

/// A collection a [FakeCollectionSource] lists, with the pages its contents
/// are served in.
final class FakeCollectionSpec {
  /// Creates a collection [id] whose contents load as [pages].
  const FakeCollectionSpec(
    this.id, {
    this.metadata = CollectionMetadata.empty,
    this.pages = FakePages.none,
  });

  /// The id the collection is listed under.
  final CollectionId id;

  /// What the source states about the collection from the start.
  final CollectionMetadata metadata;

  /// The pages served by `load` and `loadMore`.
  final FakePages pages;
}

/// An in-memory [CollectionSource] for tests, serving scripted pages.
///
/// Follows the whole seam contract. A test steers it with [failLoads],
/// [failPages], [pause] and [resume] to reach the states that are hard to
/// reach with a real backend: failure, in-flight work, disposal mid-load.
final class FakeCollectionSource implements CollectionSource {
  /// Creates a source listing [collections] in order, all idle.
  FakeCollectionSource(Iterable<FakeCollectionSpec> collections)
    : _specs = {for (final spec in collections) spec.id: spec} {
    _collections = ObservableValue(
      [
        for (final spec in _specs.values)
          Collection(id: spec.id, metadata: spec.metadata),
      ].asUnmodifiable,
    );
  }

  final Map<CollectionId, FakeCollectionSpec> _specs;
  final _gate = FakeGate();
  final _loading = <CollectionId>{};
  final _paging = <CollectionId>{};
  late final ObservableValue<List<Collection>> _collections;
  var _disposed = false;

  /// While true, a first load ends in a failed state.
  bool failLoads = false;

  /// While true, fetching a later page fails and changes nothing.
  bool failPages = false;

  /// Holds all work in flight, and work started later, until [resume].
  void pause() => _gate.pause();

  /// Lets the work held by [pause] finish.
  void resume() => _gate.resume();

  @override
  ValueObservable<List<Collection>> get collections => _collections;

  @override
  Future<void> load(CollectionId id) async {
    final spec = _specs[id];
    if (_disposed || spec == null) return;
    final contents = _contentsOf(id);
    if (contents is CollectionContents$Loaded ||
        contents is CollectionContents$Loading) {
      return;
    }
    _loading.add(id);
    _replace(id, CollectionContents.loading);
    await _gate.turn();
    _loading.remove(id);
    if (_disposed) return;
    _replace(
      id,
      failLoads
          ? const CollectionContents.failed('fake load failure')
          : spec.pages.first(),
    );
  }

  @override
  Future<void> loadMore(CollectionId id) async {
    final spec = _specs[id];
    if (_disposed || spec == null || _paging.contains(id)) return;
    final contents = _contentsOf(id);
    if (contents is! CollectionContents$Loaded ||
        contents.nextPageToken == null) {
      return;
    }
    _paging.add(id);
    await _gate.turn();
    _paging.remove(id);
    if (_disposed || failPages) return;
    final next = spec.pages.more(contents);
    if (next != null) _replace(id, next);
  }

  @override
  void dispose() {
    _disposed = true;
    _collections.dispose();
  }

  CollectionContents? _contentsOf(CollectionId id) {
    for (final collection in _collections.value) {
      if (collection.id == id) return collection.contents;
    }
    return null;
  }

  void _replace(CollectionId id, CollectionContents contents) {
    _collections.value = [
      for (final collection in _collections.value)
        if (collection.id == id)
          Collection(id: id, metadata: collection.metadata, contents: contents)
        else
          collection,
    ].asUnmodifiable;
  }
}

extension on List<Collection> {
  List<Collection> get asUnmodifiable => List.unmodifiable(this);
}
