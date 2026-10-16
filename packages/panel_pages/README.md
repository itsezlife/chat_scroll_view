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
(strings, semantics, input).

## Types

| Type | Role |
| --- | --- |
| `CatalogPage` | The widget. Hosts the viewport on a `CatalogPageModel`, reports picks and scroll activity to its `PanelPageHost`, forwards motion and the visible band to the bake, scrolls to the start on a re-selected tab, restores the browse offset when search results go, builds the policy's top strip and binds the roving-focus keys. Scopes the catalogue theme from the chrome theme. |
| `CatalogPagePolicy`, `CatalogPick`, `CatalogLongPressSession` | What depends on the kind of content: declared capabilities and bottom actions, which collections show, section id, title, geometry, content box, stand-in, skeleton count, empty copy, header action, leaf facts and tag, what a tap picks, long press (eligibility and a session that receives the rest of the gesture), header action handling, top strip. Every method has a default for a plain grid of described content. |
| `CatalogPageModel` | The state behind a page, without a widget: the snapshot the viewport shows, the loads that near-viewport events cause, search results, progress and result count. Source, search source, policy and strings can be replaced while it lives. |
| `CatalogSnapshotBuilder` | Collections to `CatalogSnapshot`: one section per collection, state mirrored (`idle` and `loading` are a loading section of skeletons, `failed` is the same without an error UI, `loaded` shows leaves or the empty copy). |
| `CatalogPageController` | What a page keeps across being unmounted (catalogue controller, browse offset), held in the shell's per-page registry. |
| `CatalogStripHandle`, `CatalogStripEntry` | A page's top strip's whole connection to the page: the sections to show, the catalogue's scroll events and the jump to a section. |
| `PageScrollReporter` | Catalogue scroll events to the shell's `PageScrollActivity`: drag and fling deltas, one jump per programmatic motion, idle at rest (with whether it rests at an end). |
| `BakeActivityPort`, `CatalogBakeForwarder`, `GlyphAtlasBakePort` | The narrow seam to a glyph bake. The forwarder reports the catalogue's motion as one reporter (a shared baker is held back until every surface rests), hands over the visible band when it settles, and re-reports both to a baker that replaces the first. `GlyphAtlasBakePort` is the one-to-one adapter for a `GlyphAtlas`. |
| `ChromeCatalogTheme` | The one place that knows both the chrome tokens and `PanelCatalogThemeData`: maps colours, leaves geometry and text metrics to the viewport. |
| `PageAssets` | Builds the `AssetCacheScope` a page draws through: baked sprites where a glyph source is registered, text (`TextGlyphProducer`) where none is. |
| `CatalogKeyboardFocus`, `CatalogMoveFocusIntent` | The key bindings of roving focus: arrows, Home, End, Enter, Space. |
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
| An `AssetCacheScope` per page, built with `PageAssets.createScope` (or equivalent): a glyph source where glyphs are baked, none where they are drawn as text. The host owns and disposes it. | Expect the page to decide how glyphs are drawn, to plan an atlas or to dispose the scope. |
| Sources (`CollectionSource`, optionally `SearchSource`) that own their data and loading; a replacement source may be passed at any time. | Pass a source that publishes in place; every publication is a new list. Expect a failed load to be retried in a loop. |
| A `BakeActivityPort` for the atlas that draws the page's glyphs, replaced when the atlas is. | Report the page's scrolling to the atlas as well; the page is already one reporter. |
| One `PanelEvent` handler on the shell that inserts picked content and records recents. | Expect the page to insert content or write recents. |
| Strings: `PanelStrings` titles for recents, search results and empty search. | Pass raw ids as titles; the page does not own language. |

## Not in this package

The shell (pager, tabs, bottom bar, search field), the catalogue viewport and
its layout maths, asset fetch and decode, the glyph atlas and its planning, the
emoji page, variant picker and category strip, and every data source.
