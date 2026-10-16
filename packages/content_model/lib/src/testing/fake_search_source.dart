import 'package:content_model/content_model.dart';
import 'package:content_model/src/testing/fake_gate.dart';
import 'package:content_model/src/testing/fake_pages.dart';

/// An in-memory [SearchSource] for tests, serving scripted pages per query.
///
/// Follows the whole seam contract. A query with no scripted pages finds
/// nothing: loaded, empty. A test steers it with [failSearches], [failPages],
/// [pause] and [resume], as for `FakeCollectionSource`.
final class FakeSearchSource implements SearchSource {
  /// Creates a source answering the queries in [results], by exact text.
  FakeSearchSource(Map<String, FakePages> results) : _results = Map.of(results);

  final Map<String, FakePages> _results;
  final _gate = FakeGate();
  final _current = ObservableValue(
    const Collection(id: CollectionId.query('')),
  );
  var _generation = 0;
  var _paging = false;
  var _disposed = false;

  /// While true, a first page ends in a failed state.
  bool failSearches = false;

  /// While true, fetching a later page fails and changes nothing.
  bool failPages = false;

  /// Holds all work in flight, and work started later, until [resume].
  void pause() => _gate.pause();

  /// Lets the work held by [pause] finish.
  void resume() => _gate.resume();

  @override
  ValueObservable<Collection> get results => _current;

  @override
  Future<void> search(String query) async {
    final id = CollectionId.query(query);
    if (_disposed || _current.value.id == id) return;
    final generation = ++_generation;
    if (query.trim().isEmpty) {
      _current.value = Collection(id: id);
      return;
    }
    _current.value = Collection(id: id, contents: CollectionContents.loading);
    await _gate.turn();
    if (_disposed || generation != _generation) return;
    _current.value = Collection(
      id: id,
      contents: failSearches
          ? const CollectionContents.failed('fake search failure')
          : (_results[query] ?? FakePages.none).first(),
    );
  }

  @override
  Future<void> loadMore() async {
    final current = _current.value;
    final contents = current.contents;
    if (_disposed ||
        _paging ||
        contents is! CollectionContents$Loaded ||
        contents.nextPageToken == null) {
      return;
    }
    final generation = _generation;
    _paging = true;
    await _gate.turn();
    _paging = false;
    if (_disposed || generation != _generation || failPages) return;
    final query = (current.id as CollectionId$Query).text;
    final next = (_results[query] ?? FakePages.none).more(contents);
    if (next != null) {
      _current.value = Collection(id: current.id, contents: next);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _current.dispose();
  }
}
