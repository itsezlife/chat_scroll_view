# kv_shared_preferences

The `shared_preferences`-backed `KeyValueStore` from `content_model`, for every
platform the plugin supports (Android, iOS, macOS, Linux, Windows, web). It is
the only package in the workspace that depends on `shared_preferences`
(`scripts/check` enforces it); logic packages depend on the seam and the host
passes them this adapter.

## Types

| Type | Role |
| --- | --- |
| `SharedPreferencesKeyValueStore` | A `KeyValueStore` over the plugin's async API, created only by its async `open`, which proves the storage is reachable before anything relies on it. |

```dart
final KeyValueStore store = await SharedPreferencesKeyValueStore.open();
final recents = await KeyValueRecentsStore.load(store, namespace: 'my_package');
```

## Storage layout

One platform string per value, under the key `namespace:key` (the seam keeps
`:` out of names, so the join is unambiguous). The string is `version:text`:
the schema version and the text, written in one call so they cannot be torn.
The async API keeps no in-memory copy, so a failed `write` or `remove` has
changed nothing and `read` returns what the platform holds.

## Host contract

| The host provides | The host must not |
| --- | --- |
| `await SharedPreferencesKeyValueStore.open()` once at startup, and the instance to every package that persists. A failure there means the platform storage is unusable. | Open a second store to "reload", or wrap the instance in a cache of its own. |
| A namespace per package, chosen by that package (this adapter picks none) and passed on every call; a version on every value. | Share a namespace between packages, or expect the adapter to parse, migrate or version values. |
| Handling of a failed future from `read`, `write` or `remove` (storage unreachable); the store left the value as it was. | Treat a missing value as an error: it reads as null. |
| Its own preference keys, which stay untouched. The adapter writes only `namespace:key` entries. | Rely on the adapter to read or delete keys it did not write, or to find the older `flutter.`-prefixed keys. |
| `runKeyValueStoreContract` (from `content_model/testing.dart`) in the test of any other platform adapter it writes. | Import this package from a logic package: depend on `KeyValueStore` instead. |

### Migration policy

None. There is no dual-read of earlier key families and no version upgrade
step: a value written under an unknown version is the reader's to discard or
migrate (the seam's rule), and an entry that is not `version:text` reads as
missing.

## Decisions

- [Data layering and persistence](../../docs/adr/023-data-layering-and-persistence.md)
- [Testing policy](../../docs/adr/030-testing-policy.md)
