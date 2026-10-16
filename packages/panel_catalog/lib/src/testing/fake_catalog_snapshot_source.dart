import 'package:content_model/content_model.dart';
import 'package:panel_catalog/src/data/catalog_snapshot.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';

/// An in-memory owner of a [CatalogSnapshot] for harnesses, demos and widget
/// tests: a `ValueObservable<CatalogSnapshot>` the test publishes into by
/// hand.
///
/// Follows the whole `Observable` listener contract (dedup-on-add, snapshot
/// dispatch, silence after [dispose]). It fetches nothing: tests push
/// sections in with [replaceSections] and group related pushes in [batch] so
/// listeners, the viewport included, hear one change.
final class FakeCatalogSnapshotSource
    implements ValueObservable<CatalogSnapshot> {
  /// Creates a source holding [sections] as its first snapshot.
  ///
  /// Listeners added later get no synthetic signal for this initial value.
  FakeCatalogSnapshotSource({List<CatalogSection> sections = const []})
    : _value = ObservableValue(CatalogSnapshot(sections));

  final ObservableValue<CatalogSnapshot> _value;

  @override
  CatalogSnapshot get value => _value.value;

  /// Whether [dispose] has been called.
  bool get isDisposed => _value.isDisposed;

  /// Publishes a new snapshot of [sections].
  ///
  /// Always a new snapshot, so listeners are always told, even for equal
  /// sections. A no-op after [dispose], which keeps the last snapshot.
  void replaceSections(List<CatalogSection> sections) {
    if (_value.isDisposed) return;
    _value.value = CatalogSnapshot(sections);
  }

  /// Runs [mutation], which may [replaceSections] several times, and
  /// notifies once afterwards with the last snapshot.
  void batch(void Function() mutation) => _value.batch(mutation);

  @override
  void addListener(ObservableListener listener) => _value.addListener(listener);

  @override
  void removeListener(ObservableListener listener) =>
      _value.removeListener(listener);

  /// Drops every listener for good. Idempotent.
  void dispose() => _value.dispose();
}
