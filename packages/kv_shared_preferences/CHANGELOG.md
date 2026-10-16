# Changelog

All notable changes to `kv_shared_preferences` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `SharedPreferencesKeyValueStore`, the `shared_preferences`-backed
  `KeyValueStore` of `content_model`, created only by its async `open`. One
  platform string per value under `namespace:key`, written as `version:text` in
  one call. No migration of earlier key families.
- The package is the only member of the workspace that depends on
  `shared_preferences` (`scripts/check` enforces it); it passes
  `runKeyValueStoreContract` against the plugin's in-memory test double.
