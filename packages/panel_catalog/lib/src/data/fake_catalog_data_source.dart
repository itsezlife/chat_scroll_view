import 'package:panel_catalog/src/data/catalog_data_source.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';

/// In-memory [CatalogDataSource] for harnesses, demos, and widget tests.
///
/// Owns a replaceable [sections] list. Does **not** fetch; hosts / tests
/// push catalog snapshots in. [replaceSections] writes and notifies once;
/// [setSections] is a silent write — pair it with [notifyDataChanged] when
/// the signal must follow separately.
///
/// ## Dispose
///
/// After [dispose], [replaceSections] / [setSections] are silent no-ops and
/// listeners are cleared via the base class. Safe to dispose more than once.
///
/// ## Immutability
///
/// Stored lists are wrapped with [List.unmodifiable] — mutating the list
/// returned from [sections] throws.
final class FakeCatalogDataSource extends CatalogDataSource {
  /// Creates a fake with optional initial [sections] (no notify on construct).
  ///
  /// Pass the catalog the first frame should project; listeners added later
  /// do not get a synthetic notify for this initial value.
  FakeCatalogDataSource({List<CatalogSection> sections = const []})
    : _sections = List<CatalogSection>.unmodifiable(sections);

  List<CatalogSection> _sections;
  var _disposed = false;

  @override
  List<CatalogSection> get sections => _sections;

  /// Replaces catalog contents and notifies listeners once.
  ///
  /// No-op after [dispose]. Equivalent to [setSections] + [notifyDataChanged]
  /// when both should happen atomically from the caller's perspective.
  void replaceSections(List<CatalogSection> sections) {
    if (_disposed) return;
    _sections = List<CatalogSection>.unmodifiable(sections);
    notifyDataChanged();
  }

  /// Silent replace — does **not** notify.
  ///
  /// Call [notifyDataChanged] afterward when listeners should run. Use this
  /// when the write and the signal must be separated (listener not yet
  /// attached, or batching with other setup). No-op after [dispose].
  void setSections(List<CatalogSection> sections) {
    if (_disposed) return;
    _sections = List<CatalogSection>.unmodifiable(sections);
  }

  /// Public notify for the silent-write-then-signal pattern.
  ///
  /// Overrides the protected base member so harnesses can call it without a
  /// subclass. Still iterates a snapshot; listeners MAY add/remove during
  /// dispatch.
  @override
  void notifyDataChanged() => super.notifyDataChanged();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
