import 'package:content_model/content_model.dart';
import 'package:content_model/src/store/store_name.dart';

/// An in-memory [KeyValueStore] for tests, with a switch that makes storage
/// fail.
///
/// Honours the whole seam contract (names are validated, missing data is
/// null), so a store under test sees what an adapter would give it. Set
/// [failure] to simulate unreachable storage: every call then fails with it
/// and leaves the stored values as they were.
final class FakeKeyValueStore implements KeyValueStore {
  final _values = <String, StoredValue>{};

  /// When non-null, every call fails with this exception and changes nothing.
  Exception? failure;

  /// How many [write] calls succeeded.
  int writeCount = 0;

  /// The stored values by `namespace:key`, for assertions. A copy.
  Map<String, StoredValue> get entries => Map.of(_values);

  @override
  Future<StoredValue?> read(String namespace, String key) async =>
      _values[_address(namespace, key)];

  @override
  Future<void> write(String namespace, String key, StoredValue value) async {
    _values[_address(namespace, key)] = value;
    writeCount++;
  }

  @override
  Future<void> remove(String namespace, String key) async {
    _values.remove(_address(namespace, key));
  }

  String _address(String namespace, String key) {
    checkStoreName(namespace, 'namespace');
    checkStoreName(key, 'key');
    final failure = this.failure;
    if (failure != null) throw failure;
    return '$namespace:$key';
  }
}
