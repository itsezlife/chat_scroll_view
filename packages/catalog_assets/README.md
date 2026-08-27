# catalog_assets

Process-wide global catalog asset cache for catalog and conversation leaves.

## Contract

- Bind by key + cache-type / size class
- Observe leaf readiness: `loading` / `ready` / `failed` (`readinessOf`)
- Attach / detach: `isRetained` while a surface is bound; ready/failed entries
  survive the last detach (pager leave/return); loading-only orphans drop
- Fetch/decode stays outside this package; `MemoryCatalogAssetCache` /
  `FakeCatalogAssetCache` drive readiness for hosts and deterministic tests
- Explicit `evict` / `clear` for memory pressure (no LRU yet)

No scroll-viewport RenderObject dependency.
