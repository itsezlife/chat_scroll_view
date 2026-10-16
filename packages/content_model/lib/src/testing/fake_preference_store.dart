import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';

/// An in-memory [PreferenceStore] for tests, with nothing persisted.
///
/// Follows the whole seam contract.
final class FakePreferenceStore with ChangeNotifier implements PreferenceStore {
  final _variants = <ContentKey$Unicode, ContentKey$Unicode>{};
  var _disposed = false;
  String? _selectedPageId;
  var _dockPreferred = false;

  @override
  Listenable get changes => this;

  @override
  ContentKey$Unicode? preferredVariant(ContentKey$Unicode base) =>
      _variants[base];

  @override
  Future<void> setPreferredVariant(
    ContentKey$Unicode base,
    ContentKey$Unicode? variant,
  ) async {
    if (_disposed || _variants[base] == variant) return;
    if (variant == null) {
      _variants.remove(base);
    } else {
      _variants[base] = variant;
    }
    notifyListeners();
  }

  @override
  String? get selectedPageId => _selectedPageId;

  @override
  Future<void> setSelectedPageId(String? id) async {
    if (_disposed || _selectedPageId == id) return;
    _selectedPageId = id;
    notifyListeners();
  }

  @override
  bool get dockPreferred => _dockPreferred;

  @override
  Future<void> setDockPreferred({required bool preferred}) async {
    if (_disposed || _dockPreferred == preferred) return;
    _dockPreferred = preferred;
    notifyListeners();
  }

  // Idempotent: ChangeNotifier asserts on a second dispose, the seam does not.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
