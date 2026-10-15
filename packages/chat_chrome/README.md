# chat_chrome

Chat composer and keyboard-replacement emoji / sticker / GIF panel chrome.
The package owns **panel UX**; the host owns [EmojiDataSource] (catalog,
recents, search, skin tones, strip icons, titles), composer insertion, and
IME handoff.

## Roles

| Role | Responsibility |
|------|----------------|
| Host | Owns [KeyboardPanelController] lifetime; mounts [KeyboardPanel]; builds [DefaultEmojiDataSource] with localized titles + strip icons; wires insert/backspace; aggregates chrome into scroll `bottomPadding`. |
| `emoji_data` | Reactive catalog, frequency recents, keyword search, skin-tone prefs, platform glyph filter. |
| Package | Panel shell, type tabs, emoji grid, bottom bar, panel prefs store. |

Decisions: [ADR 007](../../docs/adr/007-keyboard-panel-controller.md) (the
controller as source of truth) and [ADR 006](../../docs/adr/006-panel-catalog-viewport.md)
(the catalog viewport and the baked emoji).

## Host contract

| The host provides | The host must not |
|-------------------|-------------------|
| One [KeyboardPanelController] per panel, disposed by the host | Drive the panel through a `GlobalKey` on its State, or call [ChatBottomInsetController.openPanel] as well as `open` |
| An [EmojiDataSource] (a localized catalog, recents, skin tones) that notifies its listeners when any of them change | Expect baked emoji before the source reports `isReady`: the atlas is planned from its catalogue |
| Insert and backspace effects, and the strings of [KeyboardPanelLabels] | Expect the panel to edit text or wipe recents without `request.clear()` |
| `glyphCache` with `glyphArtVersion` to keep baked emoji across launches (optional) | Give a `glyphCache` without a `glyphArtVersion`: the cache could not tell when the system art changed |
| A `glyphBakeObserver` to learn which glyphs the system cannot draw (optional) | Filter the glyph list handed to the panel by what the observer finds: the plan, and so the cache key, would change with it |

## Host entry — `KeyboardPanelController`

[KeyboardPanelController] is the chrome **source of truth**. Hosts call
`open` / `close` / `openSearch` / `closeSearch` / `selectTab` / `handleBack`
and observe typed listeners. A mounted [KeyboardPanel] **projects** that
desired state into motion and layout — GlobalKey on panel State is not the
supported control path.

**Owns:** desired open / search / type-tab state; inset slot claim/release via
[ChatBottomInsetController]; persisting the selected tab through
[KeyboardPanelStore] (`keyboard_panel_selected_page`, no legacy dual-read).

**Does not own:** inset occupancy math / IME live height; composer text;
insert / backspace / clear-recents / sticker-settings effects (widget or host
callbacks); page-local catalog extent scroll ([PanelCatalogController] on
[EmojiPage]).

Same-value commands and post-[dispose] mutations are silent no-ops. Commands
commit and notify even when no panel is bound; attach projects already-open
intent.

```dart
final store = KeyboardPanelStore();
await store.load();
final inset = ChatBottomInsetController(store: store);
final panel = KeyboardPanelController(inset: inset, store: store);

final emojiData = DefaultEmojiDataSource(
  catalog: LocaleEmojiCatalogProvider(
    locale: locale,
    categoryTitles: myL10nEmojiTitles, // host-owned
    stripIconFor: EmojiTabAssets.stripIconForId, // or custom packs
  ),
);
await emojiData.load();

KeyboardPanel(
  controller: panel,
  dataSource: emojiData,
  allow: KeyboardPanelAllow.all,
  labels: KeyboardPanelLabels(...), // host-owned chrome strings
  onEmojiSelected: insertGlyph,
  onBackspace: deleteBehindCaret,
);

// later
panel.open();
panel.selectTab(KeyboardPanelTab.gifs);
panel.close(waitForIme: true);
```

Host MUST NOT dual-call [ChatBottomInsetController.openPanel] plus panel
`open` — the controller claims the slot itself.

After locale change, rebuild the catalog provider and swap it in:

```dart
await emojiData.swapCatalog(
  LocaleEmojiCatalogProvider(
    locale: newLocale,
    categoryTitles: myL10nEmojiTitles,
    stripIconFor: EmojiTabAssets.stripIconForId,
  ),
);
```

Recents are a **frequency map** (see [EmojiRecentsStore]):

- Qualifying picks bump a per-glyph count; display order is highest first.
- Cap is 48; overflow evicts the least-used entry.
- `EmojiPickSource.search` must **not** update the map.
- Panel uses [EmojiDeferredRecents]: commit on open / leave search — do not
  reshuffle the visible row on every notify while open.

Strip icons live on [EmojiCategorySpec.stripIcon] (`EmojiStripIcon` glyph /
asset / widget). There is no parallel icon-theme API on the panel.

## Host callbacks (`KeyboardPanelCallbacks`)

```dart
KeyboardPanel(
  controller: panel,
  allow: KeyboardPanelAllow.all,
  dataSource: emojiData,
  labels: KeyboardPanelLabels.russian,
  onEmojiSelected: insertGlyph,
  onBackspace: deleteBehindCaret,
  callbacks: KeyboardPanelCallbacks(
    onStickerSettings: openStickerSettings,
    onClearRecents: EmojiClearRecents.materialConfirm,
  ),
);
```

Long-press on a frequently-used glyph fires `onClearRecents`. The panel does
**not** wipe until the host calls `request.clear()`.

## Bottom bar trailing actions

[KeyboardPanelBottomActions.standard] resolves one optional action per type tab:

| Tab | Action |
|-----|--------|
| Emoji | Backspace — tap once; hold repeats. |
| Stickers | Settings (when `onStickerSettings` is set). |
| GIFs | None. |

## Embed grid only

Use [EmojiGridView] / [EmojiPage] with an [EmojiDeferredRecents] snapshot when
you do not need the full panel shell. Unicode page / glyph / `emoji_data` APIs
stay `Emoji*`; chrome types use `KeyboardPanel*`.

## Baked emoji

On Android, iOS and desktop [KeyboardPanel] draws the emoji grid from baked
atlas pages: it owns one atlas for the life of the shell (so closing and
reopening the panel does not bake again), plans the glyphs the grid shows
(the catalogue in its own order with the user's skin tones applied, then the
recents it lacks, so the cache key does not follow the recents), bakes only
while the panel is visible and not opening or closing, and hands the atlas to
each [EmojiPage] it mounts. Until a glyph is baked its cell is a circle. On the
web, and for an [EmojiPage] embedded on its own (no `glyphAtlas`), glyphs are
drawn as text. A glyph the atlas did not plan (a skin tone chosen for the first
time) or a changed screen density makes the shell plan the atlas again; the new
atlas draws what the old one drew until its own pages are ready, then swaps
once.

## Related types

- [ChatBottomInsetController] — keyboard vs panel height arbitration
- [KeyboardPanelStore] — panel height and selected type tab prefs
- [KeyboardPanelMotion] — open/close / search curves
- [ScalePressable] — press scale for type tabs and non-repeat actions


Правильное поведение:
