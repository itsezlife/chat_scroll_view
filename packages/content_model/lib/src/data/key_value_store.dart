import 'package:meta/meta.dart';

/// A string a [KeyValueStore] holds and the schema version it was written
/// under.
@immutable
final class StoredValue {
  /// Creates a stored value written under schema [version].
  const StoredValue(this.value, {required this.version});

  /// The text as written. The store does not interpret it.
  final String value;

  /// The version of the layout of [value], chosen by the writer.
  final int version;

  @override
  bool operator ==(Object other) =>
      other is StoredValue && other.value == value && other.version == version;

  @override
  int get hashCode => Object.hash(value, version);

  @override
  String toString() => 'StoredValue(v$version)';
}

/// Asynchronous persistence for the model's stores: strings in namespaces,
/// each stamped with a schema version.
///
/// The only way logic packages reach durable storage; adapters to a platform
/// store live in their own packages. One package owns one [namespace], so
/// packages cannot overwrite each other's keys.
///
/// ## Names
///
/// A namespace or key is a non-empty string of ASCII letters, digits, `_`,
/// `.` and `-`; anything else is a programming error, rejected with an
/// [ArgumentError] (the returned future fails with it). In particular `:` is
/// excluded, so an adapter may join the two with it without ambiguity.
///
/// ## Values
///
/// The store keeps the text and the version and nothing more: it neither
/// parses nor migrates. A reader that finds a [StoredValue.version] it does
/// not know discards the value or migrates it itself. Missing data is null,
/// never an error.
///
/// ## Failure
///
/// A future fails when the underlying storage cannot be reached or written.
/// A failed [write] or [remove] left the stored value as it was, so the
/// caller may keep working from memory and try again.
abstract interface class KeyValueStore {
  /// The value stored under [namespace] and [key], or null when there is
  /// none.
  Future<StoredValue?> read(String namespace, String key);

  /// Stores [value] under [namespace] and [key], replacing any earlier one.
  /// The next [read] returns it.
  Future<void> write(String namespace, String key, StoredValue value);

  /// Deletes the value under [namespace] and [key]. Deleting a missing value
  /// is not an error.
  Future<void> remove(String namespace, String key);
}
