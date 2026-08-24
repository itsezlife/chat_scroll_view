# Changelog

All notable changes to `catalog_assets` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

## [0.1.0] - 2026-08-25

### Added

- **`CatalogAssetCache`** — process-wide attach/refcount contract for catalog and
  conversation leaves (key + cache-type / size class + readiness).
- **`CatalogAssetKey`** — sealed unicode / document identity for cache lookup.
- **`CatalogAssetCacheType`** — size-class attach hint (e.g. keyboard vs inline).
- **`CatalogAssetReadiness`** — `loading` / `ready` / `failed` observation.
- **`CatalogAssetBinding`** — surface bind handle with readiness listener.
- **`MemoryCatalogAssetCache`** — in-memory implementation for hosts and tests.
- **`FakeCatalogAssetCache`** — deterministic readiness for widget tests.
- **Unit tests** at the public cache API.

### Non-goals

- No RenderObject dependency; fetch/decode orchestration stays in hosts.
