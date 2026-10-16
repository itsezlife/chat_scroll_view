# panel_pages

The shared page scaffold of the panel. A **catalog page** shows the
collections of one kind of content (emoji, stickers, GIFs) in a
`panel_catalog` viewport, loads them as the user scrolls, searches them for
the shell's query, and tells the shell what happened. The kind-specific
decisions are a **page policy**, so a page is a thin composition of a data
source and a policy.

Depends on `panel_shell`, `panel_catalog`, `catalog_assets`, `content_model`
and `chrome_foundation` (`scripts/check` enforces the direction): never on a
data payload, codec or fetcher. Decisions: [ADR 025](../../docs/adr/025-panel-shell-and-pages.md)
(shell and pages), [ADR 024](../../docs/adr/024-panel-catalog-seams.md)
(catalogue seams), [ADR 022](../../docs/adr/022-asset-cache-and-media-pipeline.md)
(asset cache), [ADR 031](../../docs/adr/031-localization-accessibility-and-input.md)
(strings, semantics, input). Glossary: [Chat chrome](../../docs/chrome/CONTEXT.md),
[Panel Catalog](../../docs/panel-catalog/CONTEXT.md). Constructor requirements:
`CatalogPage` takes `host`, `source`, `policy` and `assets`; `EmojiPage` takes
`host`, `source`, `searchSource`, `preferences`, `entryOf` and `assets`.

## Types

| Type | Role |
| --- | --- |
| `CatalogPage` | The widget. Hosts the viewport on a `CatalogPageModel`, reports picks and scroll activity to its `PanelPageHost`, forwards motion and the visible band to the bake, scrolls to the start on a re-selected tab, restores the browse offset when search results go, builds the policy's top strip and binds the roving-focus keys. Scopes the catalogue theme from the chrome theme. |
| `CatalogPagePolicy`, `CatalogPick`, `CatalogLongPressSession` | What depends on the kind of content: declared capabilities and bottom actions, which collections show, section id, title, geometry, content box, stand-in, skeleton count, empty copy, header action, leaf facts and tag, what a tap picks, long press (eligibility and a session that receives the rest of the gesture), header action handling, top strip. Every method has a default for a plain grid of described content. |
| `CatalogPageModel` | The state behind a page, without a widget: the snapshot the viewport shows, the loads that near-viewport events cause, search results, progress and result count. Source, search source, policy and strings can be replaced while it lives. |
| `CatalogSnapshotBuilder` | Collections to `CatalogSnapshot`: one section per collection, state mirrored (`idle` and `loading` are a loading section of skeletons, `failed` is the same without an error UI, `loaded` shows leaves or the empty copy). |
| `CatalogPageController` | What a page keeps across being unmounted (catalogue controller, browse offset), held in the shell's per-page registry. |
| `CatalogStickyHeader`, `CatalogScrollMetrics` | The geometry of the page's sticky header, as a pure class fed by the catalogue's scroll: the strip slides up as the user reads on and returns as they read back; an inline search field is the first thing in the content, scrolls away with it and pins when search opens; the two hairlines show while content passes under them. `CatalogPage` paints what it publishes and pads the catalogue by the strip's and the field's extent (the policy's `stripExtent`). |
| `CatalogStripHandle`, `CatalogStripEntry` | A page's top strip's whole connection to the page: the sections to show, the catalogue's scroll events and the jump to a section. |
| `PageScrollReporter` | Catalogue scroll events to the shell's `PageScrollActivity`: drag and fling deltas, one jump per programmatic motion, idle at rest (with whether it rests at an end). |
| `BakeActivityPort`, `CatalogBakeForwarder`, `GlyphAtlasBakePort` | The narrow seam to a glyph bake. The forwarder reports the catalogue's motion as one reporter (a shared baker is held back until every surface rests), hands over the visible band when it settles, and re-reports both to a baker that replaces the first. `GlyphAtlasBakePort` is the one-to-one adapter for a `GlyphAtlas`. |
| `ChromeCatalogTheme` | The one place that knows both the chrome tokens and `PanelCatalogThemeData`: maps colours, leaves geometry and text metrics to the viewport. |
| `PageAssets` | Builds the `AssetCacheScope` a page draws through: baked sprites where a glyph source is registered, text (`TextGlyphProducer`) where none is. |
| `CatalogKeyboardFocus`, `CatalogMoveFocusIntent` | The key bindings of roving focus: arrows, Home, End, Enter, Space. |
| `EmojiPage`, `EmojiPagePolicy`, `EmojiPageController`, `EmojiEntryOf` | The emoji page: the policy of eight columns, category titles, recents (only while there are some, alone for an empty search) with a header action that asks the host to clear them, and the variant picker; the widget loads every collection at once, plans the atlas, wires it and paces its mount; the controller keeps the atlas host across the widget. |
| `EmojiCategoryStrip`, `EmojiCategories`, `EmojiCategoryTab` | The page's top strip: one tab per category (people folded into smileys), the active tab following the catalogue, a tap landing on the category's first section and staying active after the jump. |
| `EmojiVariantPicker`, `EmojiVariantSession`, `emojiVariantOptions` | The popup of an emoji's base and variants and the long press that drives it: slide and release, or tap an option (a screen reader's long press has no release). |
| `EmojiTabIconScope`, `EmojiTabIcons` | The strip's art (bundled webp) registered as `ChromeIcon` painters; decoded once per process. |
| `GlyphAtlasHost`, `GlyphPlan`, `GlyphAtlasHostFactory`, `GlyphPlanner` | The atlas of a page that shows baked glyphs: what is planned (the glyphs the collections show, chosen variants only, recents last and sorted), replanning behind the old art, density, the panel's visible and opening listenables as the bake's pause signals, persistence, residency. |
| `package:panel_pages/testing.dart` | `FakePanelPageHost`, `FakeBakeActivityPort`, `runBakeActivityPortContract`. Tests only. |

## Using it

```dart
class StickerPolicy extends CatalogPagePolicy {
  const StickerPolicy();

  @override
  SectionLayout? layoutOf(Collection collection) =>
      const SectionLayout.grid(spanCount: 5, cellAspect: 1);

  @override
  bool hasLongPress(CatalogLeafHit hit, Collection collection) => true;

  @override
  CatalogLongPressSession? beginLongPress(
    BuildContext context,
    CatalogLeafHit hit,
    Collection collection,
    LongPressStartDetails details,
  ) => StickerPreview.show(context, hit.leaf.key);
}

final page = PanelPage(
  id: 'stickers',
  tab: const PanelTab(icon: ChromeIconId.stickers, labelKey: 'stickers'),
  capabilities: const StickerPolicy().capabilities,
  builder: (context, host) => CatalogPage(
    host: host,
    source: stickerSource,
    searchSource: stickerSearch,
    policy: const StickerPolicy(),
    assets: assetScope,
  ),
);
```

- **Loading.** Nothing loads up front. A section announces an edge coming near
  the viewport and the page answers: an idle or failed collection is loaded (a
  failed one is retried when the user scrolls back to it, never in a loop), a
  loaded one with a next page is paged at its trailing edge.
- **Search.** The page maps the shell's query to its `SearchSource` through
  `DebouncedSearch`. While search is open with a query the catalogue is one
  section of results (earlier results stay up while the next query is
  searched); open with no query, it still browses and the policy may narrow
  what shows. The browse offset comes back, one frame after the collections
  are laid out, when the results go.
- **Bake.** Hand the page a `BakeActivityPort` where glyphs are baked. Swap it
  when the atlas is replanned. Where nothing is baked pass none and build the
  scope with `PageAssets.createScope` without a glyph source: glyphs are drawn
  as text.
- **Scroll.** The page reports `PageScrollDrag` / `PageScrollFling` deltas,
  `PageScrollJump` for programmatic motion and `PageScrollIdle` at rest; the
  shell's bottom bar follows. Reports of a page that is not selected are
  dropped by the shell.

## Host contract

| The host provides | The host must not |
| --- | --- |
| A `ChromeThemeScope` and a `ChromeStringsScope` above every page (both required). | Expect a default theme or language; mount a page without them. |
| The `AssetCacheScope` the page draws through (`assets:`, required), usually the app-wide one, built with `PageAssets.createScope` so unicode keys fall back to text where no atlas is registered. The host owns and disposes it. | Dispose the scope while a page is mounted, or register an atlas on it by hand while an `EmojiPage` is mounted: the page sets `assets.glyphSource` to its own atlas on mount, keeps it when it unmounts (surfaces outside the panel draw through the same scope) and its controller clears it when the shell disposes it. |
| Sources (`CollectionSource`, optionally `SearchSource`) that own their data and loading; a replacement source may be passed at any time. | Pass a source that publishes in place; every publication is a new list. Expect a failed load to be retried in a loop. |
| A `BakeActivityPort` for the atlas that draws the page's glyphs, replaced when the atlas is. | Report the page's scrolling to the atlas as well; the page is already one reporter. |
| For the emoji page: a `GlyphAtlasHostFactory` that builds a `GlyphAtlasHost` from the bake parts only the host has (frame source, page cache and art version, the glyph probe's observer, memory pressure), or none where nothing is baked; an `EmojiEntryOf` (the data layer's `entryOf`); the `PreferenceStore`. | Plan the atlas itself, or build it before the density of the view is known; hand the page a source that loads slowly and expect baked glyphs for the first leaves (see below). |
| For a cold mount: `EmojiPage.deferChrome` and `PanelShell.deferSearchField` set together while the panel opens with an animation, and left off when it replaces the keyboard. | Defer over content already on screen, or the chrome pops in. |
| One `PanelEvent` handler on the shell that inserts picked content and records recents. | Expect the page to insert content or write recents. |
| Strings: `PanelStrings` titles for recents, search results and empty search. | Pass raw ids as titles; the page does not own language. |

## Not in this package

The shell (pager, tabs, bottom bar, search field), the catalogue viewport and
its layout maths, asset fetch and decode, the glyph atlas itself (this package
plans and keeps one; `catalog_assets` bakes it), the emoji catalogue, its
keywords and the glyph-support probe (the emoji data layer: this package never
depends on it or on a payload), and every data source.

## The emoji page

- **Loading.** An atlas has to be planned for every emoji before the first glyph
  is drawn, since a glyph attached while none exists is drawn as text. So the
  page asks every collection to load as soon as it is listed (and pages to the
  end). The emoji source answers within one microtask, before the next frame;
  a slow source shows its first leaves as text.
- **Unfiltered plan.** A glyph the glyph-support probe hides leaves the
  collections, and with them the plan, so the cache key would change once the
  probe finishes. The atlas keeps a glyph it planned (a plan that only lost
  glyphs changes nothing), but the next launch plans from the filtered
  collections: a host that wants the unfiltered plan passes a `planner` that
  adds the catalogue's glyphs.
- **Search focus.** Dragging the catalogue releases the search field's focus
  and keeps search open; the field is the shell's.
- **Sizes.** Emoji are baked for `EmojiPagePolicy.glyphBoxExtent` (the glyph box
  of a 45 px cell, one size per atlas, capped at 72 px); wider cells upscale.
