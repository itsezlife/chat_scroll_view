# catalog_assets

Process-wide global catalog asset cache for catalog and conversation leaves.

## Contract

- Bind by key + cache-type / size class
- Observe leaf readiness: `loading` / `ready` / `failed`
- Attach / detach refcount retains entries while a surface is bound
- Fetch/decode stays outside this package; `MemoryCatalogAssetCache` /
  `FakeCatalogAssetCache` drive readiness for hosts and deterministic tests

No scroll-viewport RenderObject dependency.
