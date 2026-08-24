# chat_chrome

Chat composer and keyboard-replacement emoji / sticker / GIF panel chrome.
The package owns **panel UX**; the host owns [EmojiDataSource] (catalog,
recents, search, skin tones, strip icons, titles), composer insertion, and
IME handoff.

## Roles

| Role | Responsibility |
|------|----------------|
| Host | Mounts `EmojiPanel` (or embed [EmojiGridView] alone), builds [DefaultEmojiDataSource] with localized titles + strip icons, wires insert/backspace, aggregates chrome into scroll `bottomPadding`. |
| `emoji_data` | Reactive catalog, frequency recents, keyword search, skin-tone prefs, platform glyph filter. |
| Package | Panel shell, type tabs, emoji grid, bottom bar, keyboard-height prefs. |

## Emoji data (`EmojiDataSource`)

```dart
final emojiData = DefaultEmojiDataSource(
  catalog: LocaleEmojiCatalogProvider(
    locale: locale,
    categoryTitles: myL10nEmojiTitles, // host-owned
    stripIconFor: EmojiTabAssets.stripIconForId, // or custom packs
  ),
);
await emojiData.load();

EmojiPanel(
  controller: insetController,
  store: keyboardHeightStore,
  dataSource: emojiData,
  allow: EmojiPanelAllow.all,
  labels: EmojiPanelLabels(...), // host-owned chrome strings
  onEmojiSelected: insertGlyph,
  onBackspace: deleteBehindCaret,
);
```

After locale change, rebuild the catalog provider and call
`emojiData.reloadCatalog()`.

Recents are a **frequency map** (see [EmojiRecentsStore]):

- Qualifying picks bump a per-glyph count; display order is highest first.
- Cap is 48; overflow evicts the least-used entry.
- `EmojiPickSource.search` must **not** update the map.
- Panel uses [EmojiDeferredRecents]: commit on open / leave search — do not
  reshuffle the visible row on every notify while open.

Strip icons live on [EmojiCategorySpec.stripIcon] (`EmojiStripIcon` glyph /
asset / widget). There is no parallel icon-theme API on the panel.

## Host callbacks (`EmojiPanelCallbacks`)

```dart
EmojiPanel(
  labels: EmojiPanelLabels.russian,
  callbacks: EmojiPanelCallbacks(
    onStickerSettings: openStickerSettings,
    onClearRecents: EmojiClearRecents.materialConfirm,
  ),
);
```

Long-press on a frequently-used glyph fires `onClearRecents`. The panel does
**not** wipe until the host calls `request.clear()`.

## Bottom bar trailing actions

[EmojiPanelBottomActions.standard] resolves one optional action per type tab:

| Tab | Action |
|-----|--------|
| Emoji | Backspace — tap once; hold repeats. |
| Stickers | Settings (when `onStickerSettings` is set). |
| GIFs | None. |

## Embed grid only

Use [EmojiGridView] / [EmojiPage] with an [EmojiDeferredRecents] snapshot when
you do not need the full panel shell.

## Related types

- [ChatBottomInsetController] — keyboard vs panel height arbitration
- [KeyboardHeightStore] — IME height and selected type tab
- [KeyboardPanelMotion] — open/close / search curves
- [ScalePressable] — press scale for type tabs and non-repeat actions


Правильное поведение:
