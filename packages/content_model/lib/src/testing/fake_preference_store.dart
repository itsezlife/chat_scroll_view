import 'package:content_model/content_model.dart';

/// An in-memory [PreferenceStore] for tests, with nothing persisted.
///
/// Follows the whole seam contract.
final class FakePreferenceStore implements PreferenceStore {
  final _variants = <ContentKey$Unicode, ContentKey$Unicode>{};
  final _changes = ObservableNotifier();
  String? _selectedPageId;

  @override
  Observable get changes => _changes;

  @override
  ContentKey$Unicode? preferredVariant(ContentKey$Unicode base) =>
      _variants[base];

  @override
  Future<void> setPreferredVariant(
    ContentKey$Unicode base,
    ContentKey$Unicode? variant,
  ) async {
    if (_changes.isDisposed || _variants[base] == variant) return;
    if (variant == null) {
      _variants.remove(base);
    } else {
      _variants[base] = variant;
    }
    _changes.notify();
  }

  @override
  String? get selectedPageId => _selectedPageId;

  @override
  Future<void> setSelectedPageId(String? id) async {
    if (_changes.isDisposed || _selectedPageId == id) return;
    _selectedPageId = id;
    _changes.notify();
  }

  @override
  void dispose() => _changes.dispose();
}
