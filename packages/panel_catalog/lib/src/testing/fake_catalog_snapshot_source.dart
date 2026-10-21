import 'package:listen/listen.dart';
import 'package:panel_catalog/src/data/catalog_snapshot.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';

/// An in-memory owner of a [CatalogSnapshot] for harnesses, demos and widget
/// tests: a `ValueListenable<CatalogSnapshot>` the test publishes into by
/// hand.
///
/// A `ChangeNotifier` from `package:listen`, so listeners behave as that
/// package documents. It fetches nothing: tests push sections in with
/// [replaceSections], one call per snapshot they want listeners, the viewport
/// included, to hear.
final class FakeCatalogSnapshotSource
    with ChangeNotifier
    implements ValueListenable<CatalogSnapshot> {
  /// Creates a source holding [sections] as its first snapshot.
  ///
  /// Listeners added later get no synthetic signal for this initial value.
  FakeCatalogSnapshotSource({List<CatalogSection> sections = const []})
    : _value = CatalogSnapshot(sections);

  CatalogSnapshot _value;
  bool _disposed = false;

  @override
  CatalogSnapshot get value => _value;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Publishes a new snapshot of [sections].
  ///
  /// Always a new snapshot, so listeners are always told, even for equal
  /// sections. A no-op after [dispose], which keeps the last snapshot.
  void replaceSections(List<CatalogSection> sections) {
    if (_disposed) return;
    _value = CatalogSnapshot(sections);
    notifyListeners();
  }

  /// Drops every listener for good. Idempotent.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
