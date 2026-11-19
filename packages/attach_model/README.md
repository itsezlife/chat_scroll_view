# attach_model

The **attach model** every picker front-end shares: what an attach item is,
the ordered **attach selection** with its cap and gates, the host's **attach
limits**, and the per-platform **attach policy**. Pure Dart: it depends on
`content_model` (the caption is its `RichText`), `listen` and `meta`, and on
no Flutter, platform code or media package.

Decisions: [ADR 046](../../docs/adr/046-media-picker.md).

## Types

| Type | Role |
| --- | --- |
| `AttachItem` | One thing picked to send: `id`, `source`, `kind`, `facts`, and per-item state (`spoiler`, `timer`, `caption`, `edits`, `derived`). `effectiveDimensions` / `effectiveDuration` / `isMuted` / `isAnimated` read the derived output when there is one. |
| `AttachSource` | Sealed, by plain values: `library(assetId)`, `file(path)`, `blob(handle)`, `captured(localKey)`, `pasted(localKey)`. |
| `AttachKind` | `photo`, `video`, `animation`, `audio`, `file`; classification is the intake's. |
| `AttachFacts`, `AttachDimensions`, `AttachTimer` | Byte size, pixel size, duration, MIME, name, modified time; a timer that is `once` or `after(duration)`. |
| `ItemEdits`, `DerivedOutput` | The **edited item** slot: an editor's opaque, versioned recipe and its rendered output. Nothing writes them yet. |
| `AttachLimits` | Injected per open: allowed kinds, single select, caption length, file size limit, timer / schedule / grouping / spoiler / send-as-file allowed. |
| `AttachSelection` | Ordered by selection: `toggle`, `toggleRange` (every item takes the state the first one takes), `remove`, `reorder`, `update`, `orderOf` (1-based, re-indexed), `snapshot` / `restore`, `changes`. A refused toggle returns `AttachToggle.refused(AttachRefusal)` and changes nothing. |
| `AttachPolicy` (`$Android`, `$IOS`, `$Desktop`, `$Web`) | The rules per platform family; `forPlatform(AttachHostPlatform, isWeb:)` picks one. Not sealed: extend a stock family to change one rule. |

`testing.dart`: `AttachItems` (an item per kind for tests) and
`AttachPolicyContract` (the suite every policy passes).

## Host contract

| Step | What the host does |
| --- | --- |
| Limits | Builds `AttachLimits` from its rights for every open; the picker never looks them up. |
| Policy | `AttachPolicy.forPlatform(platform, isWeb: kIsWeb)`, or a family it extends. |
| Selection | One `AttachSelection(policy:, limits:)` per open; every source of the open (library, camera, files, paste) toggles into it. |
| Refusals | Turns `AttachToggle.refused(reason)` into its feedback (a bulletin, a haptic). |

## Rules and values

| Rule | Android | iOS | Desktop | Web |
| --- | --- | --- | --- | --- |
| Selection cap | 100 | 100 | none | none |
| Single select | cap 1, a toggle replaces | same | same | same |
