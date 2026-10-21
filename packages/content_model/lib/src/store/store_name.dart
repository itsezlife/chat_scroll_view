import 'package:content_model/src/data/key_value_store.dart';

/// The naming rule of a [KeyValueStore] namespace or key.
///
/// Shared by every [KeyValueStore] in this package, so the rule has one
/// implementation.
abstract final class StoreName {
  static final _valid = RegExp(r'^[A-Za-z0-9_.\-]+$');

  /// Rejects a [KeyValueStore] namespace or key that is empty or holds a
  /// character outside ASCII letters, digits, `_`, `.` and `-`.
  ///
  /// [role] names what is checked (`namespace`, `key`) for the error message.
  static void check(String name, String role) {
    if (_valid.hasMatch(name)) return;
    throw ArgumentError.value(
      name,
      role,
      'must be non-empty ASCII letters, digits, "_", "." and "-"',
    );
  }
}
