import 'package:content_model/content_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _validName = RegExp(r'^[A-Za-z0-9_.\-]+$');

/// A [KeyValueStore] over the platform's preferences: `shared_preferences` on
/// Android, iOS, macOS, Linux, Windows and the web.
///
/// Obtained from the async [open], which proves the storage can be reached
/// before the host starts relying on it, so no instance exists that has not
/// been checked and a later failure is a real write or read failure.
///
/// ## Layout
///
/// Each value is one platform string under the key `namespace:key` (the seam
/// excludes `:` from names, so the join is unambiguous), holding the schema
/// version and the text as `version:text`. Version and text are written in a
/// single call, so a reader never sees the pair torn. The store uses the
/// async preferences API, which reads the platform on every call and keeps
/// no copy: a failed [write] or [remove] has changed nothing, and what
/// [read] returns is what the platform holds.
///
/// ## Namespace and migration
///
/// The store picks no namespace: each consuming package passes its own to
/// every call, as the seam requires. There is no migration: keys written by
/// other code (including the legacy `flutter.`-prefixed keys of the older
/// API) are neither read nor deleted, and an entry whose text is not
/// `version:text` reads as missing.
final class SharedPreferencesKeyValueStore implements KeyValueStore {
  SharedPreferencesKeyValueStore._(this._preferences);

  /// Opens the store over the platform's preferences.
  ///
  /// Fails with the platform's error when the storage cannot be reached
  /// (a missing plugin registration, an unavailable web storage).
  static Future<SharedPreferencesKeyValueStore> open() async {
    final preferences = SharedPreferencesAsync();
    // The plugin is bound lazily, so a store that never touched it could
    // only report a broken platform at its first write, far from startup.
    await preferences.containsKey(_probeKey);
    return SharedPreferencesKeyValueStore._(preferences);
  }

  // Not a valid `namespace:key` (no key part), so it names no stored value.
  static const String _probeKey = 'kv_shared_preferences';

  final SharedPreferencesAsync _preferences;

  @override
  Future<StoredValue?> read(String namespace, String key) async {
    final raw = await _preferences.getString(_address(namespace, key));
    if (raw == null) return null;
    final at = raw.indexOf(':');
    final version = at < 0 ? null : int.tryParse(raw.substring(0, at));
    if (version == null) return null;
    return StoredValue(raw.substring(at + 1), version: version);
  }

  @override
  Future<void> write(String namespace, String key, StoredValue value) async {
    await _preferences.setString(
      _address(namespace, key),
      '${value.version}:${value.value}',
    );
  }

  @override
  Future<void> remove(String namespace, String key) async {
    await _preferences.remove(_address(namespace, key));
  }

  // Throws, which inside the async callers above fails the returned future
  // before the platform is called.
  static String _address(String namespace, String key) {
    _checkName(namespace, 'namespace');
    _checkName(key, 'key');
    return '$namespace:$key';
  }

  static void _checkName(String name, String role) {
    if (_validName.hasMatch(name)) return;
    throw ArgumentError.value(
      name,
      role,
      'must be non-empty ASCII letters, digits, "_", "." and "-"',
    );
  }
}
