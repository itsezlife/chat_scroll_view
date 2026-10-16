import 'package:content_model/src/data/key_value_store.dart';

final _validName = RegExp(r'^[A-Za-z0-9_.\-]+$');

/// Rejects a [KeyValueStore] namespace or key that is empty or holds a
/// character outside ASCII letters, digits, `_`, `.` and `-`.
///
/// Shared by every [KeyValueStore] in this package, so the rule has one
/// implementation. [role] names what is checked (`namespace`, `key`) for the
/// error message.
void checkStoreName(String name, String role) {
  if (_validName.hasMatch(name)) return;
  throw ArgumentError.value(
    name,
    role,
    'must be non-empty ASCII letters, digits, "_", "." and "-"',
  );
}
