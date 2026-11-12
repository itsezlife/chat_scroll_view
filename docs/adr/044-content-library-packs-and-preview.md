# ADR 044: Content library, packs, content preview and pack sheets

A user's own sticker and GIF lists (recent stickers, favourite stickers, saved
GIFs) and the packs they installed are one **content library**: a
`content_model` seam with local-first edits, an optional undo window and a
persistence adapter seam that a key-value store fills now and a backend can
fill later. A document's descriptor names the **pack** it belongs to, and a
**pack source** resolves a pack by id. The **content preview** (press and hold
on a sticker, GIF or custom emoji) and the **pack sheets** (stickers, custom
emoji) are widgets in `panel_pages`, effect-free like the panel: they ask the
host, and the host edits the library and shows the feedback.

**Status**: Accepted  
**Date**: 2026-11-09  
**Amended**: 2026-11-09 (native-media ticket 128): a pack sheet's route is named, and a host pauses only the chat under it (section *Amendment: a pack sheet plays*); 2026-11-10 (native-media tickets 158, 161, 162): the message menu's content rows, the desktop preview sizes, a pack sheet holds the panel (section *Amendment: message menu content rows, desktop preview, panel hold*)  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 021](021-content-identity-and-collections.md), [ADR 023](023-data-layering-and-persistence.md) (amended: recents order), [ADR 024](024-panel-catalog-seams.md), [ADR 025](025-panel-shell-and-pages.md), [ADR 029](029-host-integration.md), [ADR 030](030-testing-policy.md)

## Context

The reference client keeps, per account: recent stickers (most recently used
first, 30 kept, 20 shown), favourite stickers (5 without a subscription),
saved GIFs (the GIF tab's recents: sending one saves it, 200 kept), emoji
recents (by frequency) and the installed and archived sticker and emoji packs
in the user's order. Each list changes in memory first and reaches the server
afterwards; removing a pack is held behind an Undo bulletin and sent only when
the bulletin closes. A sticker document names its pack in its attributes, and
a pack is fetched by id from memory, then a disk cache, then the network, with
concurrent requests for one pack merged and packs the user only looked at
kept. Research: `.scratch/native-media-ffi/research/content-library-datamodel.md`,
`content-preview.md`, `pack-sheet.md`.

Before this ADR the model had no pack reference on content, no favourites, no
pack lookup, no install state, and one recents ordering (frequency) for every
kind, which ADR 023 chose for emoji.

## Decided

### Model (`content_model`)

| Area | Decision |
| ---- | -------- |
| Pack | A **pack** is a published set of stickers, masks or custom emoji, by its opaque `PackId`: kind (`PackKind`: `stickers`, `masks`, `emoji`), title, items in order (descriptors), an optional cover key and whether it is official. A value; its count is its item count. Its listing is the collection `CollectionId.set(id.value)` (`Pack.collection`), so pages and sheets show a pack through the existing collection path. |
| Pack reference | `ContentDescriptor.pack`: the `PackId` of the pack the content belongs to, or null (a sticker sent without a set, a GIF, a unicode emoji). Not part of identity ([ADR 021](021-content-identity-and-collections.md)): two descriptors of one key may disagree about it and the key still names one content. Fetch credentials of a pack (an access hash) stay on the host, keyed by `PackId`, like the document's. |
| Pack source | `PackSource` seam: `lookup(id)` answers one `PackLookup` (`found(pack)`, `notFound`, `failed`) and never throws; `peek(id)` answers what is known now, without loading (`idle`, `loading`, or the last answer); `changes` signals when any answer changes. A pack found is kept for the source's lifetime whether installed or not; concurrent lookups of one id share one fetch; `failed` is retried by the next lookup, `notFound` is kept; `lookup(id, refresh: true)` fetches again and keeps answering the held pack meanwhile. The reference implementation `CachingPackSource` is the memory tier and the merging over a host `PackFetch` function; the host's function owns its disk cache and the remote. |
| Install state | A fact of the content library, not of the pack value: `ContentLibrary.installStateOf(id)` is `installed`, `archived` or `notInstalled`. A remote adapter seeds the library from the server's flags; a pack source never answers it. (the ticket listed install state under the pack source; two answers to one question would disagree after a local edit) |
| Content library | `ContentLibrary` seam. Reads: one `ValueListenable` per list: `recentStickers`, `favouriteStickers`, `savedGifs` (content keys), `installedPacks(kind)`, `archivedPacks(kind)` (pack ids), and `limits`. Write: one command, `apply(LibraryEdit edit, {undoWindow})`, where `LibraryEdit` is a sealed family: add / remove a recent sticker, favourite / unfavourite a sticker, save / unsave a GIF, install / archive / remove a pack, reorder a kind's installed packs. Edits are data so the panel and the sheets can ask for one through an event and a backend adapter can send it as is. |
| List rules | Recent stickers, favourite stickers and saved GIFs are most-recently-used lists: a key goes to the front, is never listed twice, and a key new to a full list pushes out the last one (the edit reports it as `evicted`, so the host can say the limit was reached). Installing puts a pack first in its kind and takes it out of the archive; archiving moves an installed pack to the front of the archive; removing takes it out of both; reordering lists the named installed packs in the given order, then the rest in theirs. An edit that changes nothing is `unchanged` and signals nothing. |
| Limits | `LibraryLimits`: favourite stickers and saved GIFs are the host's (required; the example: 5 and 200, the reference's values without a subscription), recent stickers default 30. A list read back longer than its limit is cut to it. |
| Local first, undo window | `apply` changes the lists and signals before it returns, and returns an `AppliedEdit`. The edit is committed (handed to storage) when its undo window ends, by `commit()`, or at `dispose`; `undo()` before that takes it back and storage never sees it. Edits commit in the order they were applied: an edit waits for an earlier one still inside its window, so the stored lists never hold an order the user did not see. The shown lists are the committed lists with the edits still in their windows replayed over them, so an undo restores a pack to its old place without an inverse edit. `AppliedEdit.outcome` completes with `committed`, `undone`, `unchanged` or `failed` and never throws; a failed commit keeps the local change (as the existing stores do) and the next commit writes the whole state again. The window is the caller's: the host passes the bulletin's 2750 ms for pack removal and archiving and none for the rest, as the reference does. |
| Persistence seam | `LibraryStorage`: `read()` the whole `LibraryState`, `commit(edit, state)` one edit with the committed state after it. A key-value adapter writes the state and ignores the edit; a backend adapter sends the edit and caches the state. `KeyValueLibraryStorage` (in `content_model`, over `KeyValueStore`, one versioned JSON record per list, writing only the lists that changed) is the one used now. Changes pushed by a server are a later addition to this seam (an incoming state stream), not built now. |
| Recents order | [ADR 023](023-data-layering-and-persistence.md) amended: the `RecentsStore` stays the frequency-ordered emoji list (unicode and custom emoji, one list for the emoji page). Recent stickers and the GIF page's recents are the content library's most-recently-used lists; a GIF page's recents *are* the saved GIFs (sending a GIF saves it, as in the reference). "Remove from recents" of a sticker is the library edit; of an emoji, `RecentsStore.remove`. |

### Surfaces (`panel_pages`)

| Area | Decision |
| ---- | -------- |
| Placement | The content preview and both pack sheets live in `panel_pages` (`src/preview/`, `src/pack_sheet/`): it already holds the long-press session plumbing they extend, the catalog viewport glue a sheet's grid reuses, and the chrome token adapter. No new package and no new dependency edge. A host with a chat and no panel still imports `panel_pages` to show a sheet. (alternative: a `content_overlays` package under `panel_pages`, kept if a host without panel pages appears) |
| Content preview | A `CatalogLongPressSession` implementation (ticket 122) reused by the sticker grid, recents and favourites, the GIF page and custom emoji cells, and by the pack sheet's grid; never a unicode emoji. It reads the library to choose its menu (favourited or not, saved or not, in recents or not, has a pack) and asks for every effect: send is `ContentPicked`, copy is `ContentCopyRequested`, the library actions are a new `PanelEvent.libraryEditRequested(edit)`, "View pack" is a new `PanelEvent.packRequested(id)`. Timings, sizes and the menu rules are the research's. |
| Pack sheets | A sticker pack sheet and an emoji pack sheet (one pack, several packs) (ticket 123), shown by the host as a modal bottom sheet on touch and a centred box under a pointer. Inputs: the pack id(s), the `PackSource`, the library's read side, an optional `PackLinkBuilder` (`Uri? Function(PackId)`: no builder, no Share or Copy link), an optional send callback (present only when opened for a composer that can send), and a request callback for library edits. The sheet shows `PackSource.peek` while it looks up: loading, the pack, or not found (the sheet closes itself and the host tells the user). The grid is a `PanelCatalogViewport` (one section, or one per pack among several, whose headers the sheet draws over the grid); on a sticker sheet tap and hold open the preview, and a right-click opens its menu entries as a context menu; on an emoji sheet or box (ticket 198) only a hold opens it, as on the panel's emoji page: the same session, from frame 0, switching under the finger or pointer, its menu Send Emoji (with a send callback) and Copy Emoji (with a copy callback), a right-click offering Copy Emoji alone (the panel's custom emoji menu), and a tap still inserts. On touch a tall sheet opens part-way and rises with its grid to the status bar (ticket 126). |
| Feedback | Bulletins (added, removed with Undo, limit reached) are the host's, as Copy feedback is ([AGENTS.md](../../AGENTS.md) invariant): the host applies the edit with the window, shows the bulletin, and calls `undo()` from it. Strings come from chrome strings. |

### Host seams (tickets 121, 124)

| Path | Decision |
| ---- | -------- |
| Panel to sheet | `PanelEvent.packRequested(id)` (pack title in the sticker page, preview "View pack"): the host opens the sheet. |
| Chat to sheet | No change to `chat_scroll_view`: on `ChatStickerActivated` (a sticker message) and `ChatInlineHit.embed` (a custom emoji in text) the host resolves the key's descriptor (`ContentResolver`), reads its pack reference, and opens the sticker or emoji sheet; no pack, nothing opens. An emoji sheet opened from a custom emoji in text shows that emoji above its card (`EmojiPackSheet.previewEmoji`, the reference's `setPreviewEmoji`; ticket 126). A lone animated emoji keeps its replay; a GIF tap stays as it is. The message menu's "contains emoji from N packs" (the several-packs sheet over the packs of a message's custom emoji, deduplicated) is the host's menu entry, in scope for ticket 124. |
| Sending from a sheet | The sheet's send callback is given only when the host can send to the chat's composer. The sheet closes itself, then hands the item over (`StickersAlert`: `onStickerSelected`, then `dismiss`); the host sends and records the use (`AddRecentSticker`). Amended in ticket 126: the host does not close the sheet. |
| Composition root | The host creates the `LibraryStorage` adapter, loads the library (`StoredContentLibrary.load`, a loaded store like the others), creates the pack source over its fetch, and disposes them after the chat screens. The example's sources give each document its pack reference. |

## Why

- Favourites, saved GIFs and recent stickers are one mechanism (an ordered,
  capped, most-recently-used list with explicit add and remove) three times;
  packs add install state and order. One library with one edit family and one
  persistence seam is cheaper than a store per list, and the edit as data is
  what a backend adapter, the panel's events and the undo replay all need.
- Committing edits in order and replaying the pending ones keeps undo exact
  (the old index comes back) without writing an inverse for every edit, and
  keeps storage from ever holding a state the user did not see.
- Install state belongs to the user's library: a pack value fetched before an
  install would otherwise say "not installed" next to a library that says
  "installed".
- The reference keeps emoji recents by frequency and sticker and GIF recents
  by recency; one ordering for all was a simplification ADR 023 made for
  emoji only.
- The preview extends a seam `panel_pages` already owns, and the pack sheet's
  grid is a catalog section; a new package would hold two widgets that depend
  on everything `panel_pages` depends on.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| A store per list (favourites store, saved GIFs store, packs store) | Three copies of one most-recently-used mechanism, three persistence seams for one backend, and no shared order for undo |
| Sticker and GIF recents as `RecentsStore` lists with a per-kind ordering policy | The GIF recents are the saved GIFs: a second list of the same thing would disagree after a save or unsave |
| Verbs per command on the library (`favouriteSticker`, `saveGif`, ...) without an edit value | The panel and the sheets would need one event per verb, and a backend adapter one method per verb |
| An inverse edit per command for undo | Wrong once another edit lands in between (an index that moved, an eviction that changed) |
| Committing each edit when its own window ends | An edit applied later could be stored before an earlier one, in an order the user never saw |
| Install state on the pack value | Two answers to one question |
| The pack reference as a `CollectionId` | A collection id is scoped to its source; a pack id is the content's, the same in every source |
| The library or the sheet performing feedback (bulletins, toasts) | Feedback UI is the host's |

## Consequences

- `ContentDescriptor` gains a field: every equality and hash includes it.
- The example's sticker and GIF recents move from the `RecentsStore` to the
  library (ticket 121); the old sticker and GIF records in the recents
  namespace are left unread.
- `panel_shell` gains two additive `PanelEvent`s (`libraryEditRequested`,
  `packRequested`) with ticket 122; host switches over the sealed family must
  add them.
- Short-name lookups (pack links opened from text) are the host's: it maps a
  short name to a `PackId` before it asks the pack source.

## Amendment: a pack sheet plays (2026-11-09)

Native-media ticket 128. The example paused the shared clock under every modal route but the message menu, so a pack sheet's stickers, and a preview opened from it, stood still. The reference mobile client pauses what is under its sheets and lets them play: `StickersAlert` and `EmojiPacksAlert` post `stopAllHeavyOperations` for layer 4 while shown, which stops the chat's image receivers (layer below 4) and not the sheet's cells (layer 7) or the preview (above every layer); `BottomSheet` posts it for layer 512, which stops the sheet's cells as well, only while the sheet opens or closes.

| Area | Decision |
| ---- | -------- |
| Route | `PackSheet.show` pushes its route under `PackSheet.routeName`, in both arrangements, as the message menu names its own. |
| Host | A host that pauses its animations under modal routes holds the clock for a pack sheet only while the route's transition runs (from push until open, from pop until gone), and holds the chat on its own while the sheet is open: one clock serves the chat and the sheet, so the chat is held as a surface (`ContentEmbed.held`, the path a popup panel already takes), not by a pause layer. The example's route observer and `PanelPlaybackHold.holdChat` do this. |

## Amendment: one haptic for a tapped sticker (2026-11-10)

Native-media ticket 153. A tap on a sticker in a pack sheet opens the preview
with its menu at once, and both the opening and the menu played a haptic. The
reference's `ContentPreviewViewer.showMenuFor` opens without one; only
`showSheetRunnable`, which brings the menu 16 ms later, performs
`LONG_PRESS`. A preview opened with its menu (`openMenu`) is felt once, by the
menu; one opened by a hold keeps both (the hold's and, later, the menu's).

## Related

- Glossary: [Content and Assets](../content/CONTEXT.md) (*Pack*, *Pack reference*, *Pack source*, *Content library*, *Library edit*, *Undo window*, *Install state*, *Favourite sticker*, *Saved GIF*, *Content preview*, *Pack sheet*)
- Tickets: `.scratch/native-media-ffi/issues/120` to `124`

## Amendment: message menu content rows, desktop preview, panel hold

| Area | Decision |
| ---- | -------- |
| Message menu content rows | The host's message menu offers rows for a message that is one sticker or one GIF, on the message alone (not over a selection), from the content library and the pack source, in each platform's order. Android (`ChatActivity.createMenu`, message types 7 and 4): after Copy, "Add to Stickers" (opens the pack sheet; only for a sticker with a pack) then "Add to Favorites" / "Delete from Favorites"; for a GIF, "Save to GIFs". iOS (`ChatInterfaceStateContextMenus`): "Add to Favorites" / "Remove from Favorites" first (`Stickers_AddToFavorites` / `Stickers_RemoveFromFavorites`), and after Pin "View Pack" (`StickerPack_ViewPack`, **label UNVERIFIED**: no strings file is checked out) or "Save GIF" (`Conversation_SaveGif`). Desktop (`history_view_context_menu.cpp`, `AddDocumentActions` after `AddTopMessageActions`): after Pin, "Save GIF" (`lng_context_save_gif`), "View sticker set" or "Add stickers" when the pack is not installed (`lng_context_pack_info` / `lng_context_pack_add`), "Add to Favorites" / "Remove from Favorites" (`lng_faved_stickers_add` / `_remove`). Downloads, Share, Show in Folder and the other document rows are left out: the demo has no files. The rows are the example host's (`MessageMenuCatalog`); the viewport menu only shows them. |
| Desktop preview | A preview a mouse opens takes the desktop client's `MediaPreviewWidget` sizes: a sticker or custom emoji fits a 224 box (`maxStickerSize`), a GIF fits 448 (twice it), scaled up or down to its proportions, in the middle of the window; it fades in and out over 150 ms (`stickerPreviewDuration`) with no scale (the scale code is commented out there). A window smaller than the box takes it down. |
| Panel hold | A pack sheet opened from the panel holds the hover panel up whatever the pointer does (the desktop client's `TabbedSelector::Inner::preventHideWithBox`); when it closes with the pointer away, the presentation's after-hold delay runs (3 s, `kDelayedHideTimeoutMs`, which `afterHoldDelay` already was) before the panel hides. The example host takes `PanelPresentationController.holdAutoHide` while the sheet's future is pending. |


## Amendment: the message menu's place and width, the preview menu's exit (native-media 165, 167)

| Area | Decision |
| ---- | -------- |
| Sheet placement | The mobile sheet menu hangs left of the press, as `ChatActivity.createMenu` places the popup container: `popupX = v.getLeft() + x - width + backgroundPaddings.left - dp(28)`, so the container ends 20 left of the touch, clamped `dp(6)` inside the list. The container holds the popup (its 9-patch shadow inset 8 around the card) and, with reactions, the popup's margins in `ChatScrimPopupContainerLayout` (`createLinearRelatively(..., 16, 0, 36, 0)`): the card ends 28 left of the press without reactions and 64 with them. Y keeps its rule (the touch, raised by `240 - height` past 240, clamped 24 below the top and 8 above the bottom). |
| Menu width | The card is as wide as its widest row (`ActionBarPopupWindowLayout.setFitItems(true)` over `WRAP_CONTENT` rows), at least 200 (`setMinimumWidth(dp(200))`), up to the screen (the popup is measured `AT_MOST dp(1000)` and clipped to the window); a label longer than that ellipsizes (`TruncateAt.END`). The package card had a fixed 200 and the column a 272 cap, so a slightly longer label ellipsized. |
| Outside press | Any press outside the menu dismisses it, beside the card included. The appear motion's shadow painter answered hit tests over its whole box (a `CustomPainter.hitTest` of null is a hit), so the transparent overhangs of the menu column swallowed presses; it now takes none. |
| Preview menu exit | The preview's menu hides with the preview, from the same frame: its `ChromeAppear` follows the session's open state, and the overlay goes once the preview's fade (120 ms) and the menu's hide (150 ms, the unfold's) are both over. Before, the menu was never told to hide: it stood until the overlay was removed at the end of the preview's fade, then vanished. The menu keeps the shared appear motion (ticket 164), as the ticket asks. Recorded for a later choice: the reference's `ContentPreviewViewer.dismissPopupWindow` either dismisses an `ActionBarPopupWindow` (its own 150 ms exit) or, for the `ItemOptions` layout on the scrim glass, animates it to alpha 0, scale 0.8 and -12 dp over 320 ms on `EASE_OUT_QUINT`. |

## Amendment: desktop message menu, row width, one surface (native-media 181, 184, 185, 186)

| Area | Decision |
| ---- | -------- |
| Desktop placement (181) | A popup message menu is placed as the desktop client's `Ui::PopupMenu::popup` places a menu, the rule the pointer menu already ports (`PointerMenuPlacements.of`): its top left 5 right of the pointer (`PointerMenuMetrics.pointerOffset`) at the pointer's height; left of the pointer when it would pass the right edge, above it (its bottom at the pointer) when it would pass the bottom; then kept inside the window, its safe insets and the IME. Its appear motion (the grow, `PanelAnimation`) plays from the corner at the pointer (`ChatMessageMenuPlacement.origin`). A menu without a reaction strip is its card alone: the strip's overhangs no longer pad it. |
| Desktop look (186) | The maintainer reports the desktop client's message menu reads as the mobile one but for its motion and its solid surface, so the desktop menu takes the mobile rows (`MessageMenuRow`: 48, 18, 24 icon, 43 label inset, 16 regular) in the pointer menu's colours (`PointerMenuTokens`: text, hint for the icons, ripple, background-over for hover) on the pointer menu's card: its background, 8 corners, 8 above and below the rows, its shadow (25% of the shadow colour, blur 5, offset (0, 1)), all already verified for `PointerMenuMetrics`. The `st::popupMenuWithIcons` row metrics (height, icon position, font) are not traced: `lib_ui` is not in the reference checkout, so the rows keep the mobile numbers until it is. |
| Row width (184) | The rows fill the card whatever constraints the host's surface hands them: a glass is a `Stack`, which lays its child out loosely, so with short labels each row was as wide as its own label and its ink stopped there. The card's width is measured around the surface. |
| One surface (185) | The reaction strip takes the host's surface as the action card does (`ChatMessageMenuSurfaceBuilder` now gets the surface's corner radius: the card's 12, the strip's half height), so on Android both are the scrim menu glass, as the reference draws both on it. |

## Amendment: the desktop message menu as the desktop client draws it (native-media 190, supersedes the 186 row metrics)

The desktop client opens the message context menu with `st::popupMenuWithIcons` (`HistoryInner::showContextMenu`, `history_inner_widget.cpp`; `history_view_context_menu.cpp` for the other views), traced in `lib_ui` (`ui/widgets/widgets.style`, `ui/widgets/menu/menu.cpp`, `menu_action.cpp`, `ui/colors.palette`, `ui/basic.style`):

| Area | Decision |
| ---- | -------- |
| Rows | `menuWithIcons` (`Menu(defaultMenu)`): `itemPadding` margins (54, 8, 17, 8) around the label, so a row is the font's height and 16 more (`Action::_height`); the icon at `itemIconPosition` (15, 5), the 24 px `menu/` icons, in `menuIconColor` (`windowBoldFg`, the pointer menu's `arrow`); `itemStyle` `defaultTextStyle` (`normalFont`, 13 px regular, the pointer menu's face). Text `itemFg` / `itemFgOver` / `itemFgDisabled` (`windowFg`, `windowFgOver`, `menuFgDisabled`): the pointer menu's text, text over and disabled. Fill `itemBg` / `itemBgOver` (`windowBg`, `windowBgOver`) on hover; press `defaultRippleAnimation` (`windowBgRipple`, 650 ms in, 200 ms out). An attention row (`menuWithIconsAttention`, `menuIconAttentionColor`) takes `attentionButtonFg` for text and icon: the palette's destructive colour. `MessageMenuPointerRow` in the example. |
| Width | `Action::setMarkedText`: a row wants 54 + its label + 17, clamped to `widthMin` 156 and `widthMax` 300; `Menu::recountWidth` takes the widest, in the same bounds. A popup's card is 156 to 300 (`ChatMessageMenuCard.popupMinWidth` / `popupMaxWidth`). |
| Card | `popupMenuWithIcons` (`PopupMenu(defaultPopupMenu)`): `scrollPadding` 5 above and below the rows (not the plain menu's 8), `radius` 8, `menuBg` fill, `defaultBoxShadow` (blur 5, offset (0, 1), opacity 0.25). |
| Separator | `defaultMenuSeparator`: 1 px of `menuSeparatorFg` with 5 above and below. The message menu's catalog has none on desktop; the package divider stays. |
| Motion | `defaultPanelAnimation` over `showDuration` 200, out by opacity over `duration` 150: `AppearMotion.grow` from the corner at the pointer (the 181 placement). |

## Amendment: the emoji-pack entry in the desktop card, hover under the label (native-media 194)

| Area | Decision |
| ---- | -------- |
| Entry | The desktop client adds the "contains emoji from …" entry to the message menu itself (`AddEmojiPacksAction`, `history_view_context_menu.cpp`): `menu->addSeparator()` when the menu has rows, then a `Ui::Menu::MultilineAction` with `st::historyHasCustomEmoji` (`FlatLabel(defaultFlatLabel)`, 11 px `defaultTextStyle`, `textFg` `windowFg`) at `st::historyHasCustomEmojiPosition` (12, 4); the row is the label's height and 4 above and below (`MultilineAction::contentHeight`), its right skip the same 12 (no icon). Ours drew the entry as a card of its own under the menu. The example's `MessageContainsEmojiLook.pointerRow` is that row (the pointer menu's text colour, the name bold in it), under `MessageMenuPointerSeparator` (`defaultMenuSeparator`: 1 px `menuSeparatorFg`, 5 above and below); the card's own 5 below the rows follows it. |
| Hover | `MultilineAction::paintEvent` and `Action::paint` fill `itemBgOver`, then paint the ripple, then the text: the fill and the ripple are under the label. `ChromeInk` painted its hover fill and ripple as a foreground, so the opaque `backgroundOver` (night `#232E3C`) and `ripple` hid the label of the hovered row. `ChromeInk.behindChild` paints them behind the child; the desktop rows and the entry take it. The label keeps `itemFgOver` (`windowFgOver`, the pointer menu's `textOver`). |

## Amendment: sticker cell hover, press and preview per platform (native-media 195, 197)

| Area | Decision |
| ---- | -------- |
| Panel sticker hover (195) | `StickersListWidget::paintSticker` fills `_overBg` (`Ui::RoundRect(st::roundRadiusLarge, st().overBg)`: radius 6, `emojiPanHover` = `windowBgOver`) over `QRect(tl, _singleSize)`, the whole cell, before the sticker. Ours used the emoji's 34 x 32 box (`emojiPanArea`, radius `emojiPanRadius` 8) for every cell, so on a sticker it was a small square hidden behind the sticker. `CatalogCellFeedback` (panel_pages) names the hover per kind of content: `emoji` keeps 34 x 32 at 8, `sticker` is the whole cell at 6; the page policy says which (`CatalogPagePolicy.cellFeedback`). The colour stays the chrome's hover wash. |
| Pack box hover | `StickerSetBox::Inner::paintSticker` fills the whole `_singleSize` cell with `Ui::StickerHoverCorners` (`st::roundRadiusSmall`, 3): the box's cells (177's cell sizes) take radius 3. |
| GIF and emoji | The GIF list (`GifsListWidget`, `inline_bot_layout_internal.cpp`) paints no hover square, only the remove badge on hover: unchanged (the GIF page draws no fill). Emoji cells unchanged. |
| Desktop preview (197) | Under a pointer an open preview no longer shrinks the previewed cell (154's 0.8 is the touch grid's): `CatalogPreviewFeedback.hover` keeps the hover box on the cell the preview shows, at full size, and moves it with the preview; the mouse marks no other cell. |
| Touch sticker press (197) | The mobile reference shows no highlight on a sticker cell on a tap or a hold, only the preview's scale: sticker cells on touch take `CatalogPressFeedback.none` (no wash, no press scale) and the previewed cell scales from 1, not from a press scale it never showed. Emoji cells keep their press; the GIF page is its own grid and is unchanged. |

## Amendment: layered boxes (native-media 196, supersedes 174's box swap)

The desktop client shows boxes on one layer stack (`lib_ui/ui/layers/layer_widget.cpp`, `LayerStackWidget`): `Show::showBox` defaults to `LayerOption::KeepOther`, which `appendLayer`s the box: `pushLayer` hides the shown layer and shows the new one with no animation when another is up (`_layers.size() > 1`); only the first box runs the background's show animation and only the last one's close runs the hide. `closeLayer` on the shown box pops it and shows the one under it at once; on a box under it, it is erased silently. `BoxLayerWidget::keyPressEvent` closes the focused (shown) box on Escape; a press on the background (`backgroundClicked` → `hideCurrent` → `hideLayers` → `clearLayers`) closes every box. `LayerOption::CloseOther` (`replaceLayer`) pushes the box and drops every box under it; `ShowAfterOther` (`prependLayer`) inserts it hidden at the bottom. The sticker set box's Remove (`sticker_set_box.cpp`) shows `MakeConfirmRemoveSetBox` with the default `KeepOther`; its Cancel closes the confirmation only and the pack box comes back; the maintainer observes the client closing everything once the removal is confirmed (the pack box is not shown again). 174 swapped the box with `Navigator.pushReplacement` and a 200 ms fade: the pack box was gone for good, and the swap animated.

`ChromeBoxLayer` (chrome_foundation) is that layer:

```dart
final layer = ChromeBoxLayer.open<T>(context, builder: …, barrierColor: …, transitionDuration: …); // first box
ChromeBoxLayer.of(boxContext).show<R>((_) => box);   // keep other: at once, the shown box kept
Navigator.pop(boxContext, result);                  // the shown box; Escape and back do the same
ChromeBoxLayer.closeBox(boxContext, result);         // that box, shown or not
ChromeBoxLayer.isShown(boxContext);                  // false once another box covers it
layer.closeAll(result);                              // every box, the shown one with result; a tap on the barrier
```

The pack box opens on a layer (`PackSheet.show` under a pointer); Remove shows the confirmation box (`ChatConfirmBox`) on it; Cancel (or Escape) closes the confirmation and brings the pack box back; Remove removes the pack and closes the layer with both boxes (`closeAll(true)`: the confirmation fades out with the layer, the pack box is not shown again); a tap on the dim closes both. A pack sheet's button asks its host first and closes only if it is still the shown box. The panel's own removal and the clear-recents question open a layer with the confirmation alone (the clear-recents one under a pointer; touch keeps the platform dialog).

| Facet | |
| ----- | - |
| Philosophy | A box answered by another box is one modal moment, not two: one dim, one route, and the first box survives the second. |
| Thinking | What it is: a state (a stack of boxes) owned by a boundary (one modal route). Who knows: the host shows boxes; a box knows only its layer through its context; the navigator knows one route. Repeating: the reference reaches for box-over-box everywhere a box asks (remove, rename, report, inform after error); here today the pack box Remove, the panel removal and clear recents. Tool: the navigator's internal pop (`Route.willHandlePopInternally` / `didPop`, the mechanism `LocalHistoryRoute` uses) gives Escape, back and `maybePop` closing the shown box for free; `Visibility(maintainState: true)` keeps a covered box's state without ticking or taking focus. What can go wrong: a pop that should close one box closing the layer (guarded by `didPop`); a barrier that pops only the shown box (the barrier is overridden to close all); a host showing a box after the sheet closed itself (the sheet asks first, then closes only if still shown). |
| Style | The route is the layer (`ChromeBoxLayer extends PopupRoute`), so `Navigator.push` / `pop` read as everywhere else; boxes are plain widgets; results are the box's own future. |
| Design | In chrome_foundation, the leaf that holds the chrome's surfaces and motion: panel_pages (pack box) and the host (confirmations) both depend on it already; no dependency direction of ADR 020 changes. Durations come from the caller (motion roles), not from the layer. |
| Criticality | Justified: three real call sites now, and the reference's box flows are the model for more. Not added: `CloseOther` and `ShowAfterOther` (no call site yet; `CloseOther` is `closeBox` of each box under, `ShowAfterOther` is a later need), per-box outside-click and Escape opt-outs (`setCloseByOutsideClick`, `setCloseByEscape`). |
| Application | `packages/chrome_foundation/lib/src/box/chrome_box_layer.dart`; `PackSheet.show` (pointer); `ChatConfirmBox` and `ChatPackSheets` in the example. |
| Exceptions | The touch pack sheet stays a bottom-sheet route (a drag owner, not a box). The confirmation on touch for clear recents stays the platform dialog. The layer centres its box; a box that needs another placement is not a box of this layer. |

## Amendment: the blur under the preview's menu is one still (native-media 206); the text actions query once for every field (207)

Device session pv1 (`.scratch/native-media-ffi/research/pv1-preview-open.md`): the menu's full-window `BackdropFilter`, sigma animated 0 to 12, cost a 50-59 ms first raster frame on every open (49 of 488 refreshes missed over 8 opens, 0 of 480 before), new offscreen targets on every ramp and close frame, and a live full-resolution blur of a background the session already holds.

The reference (`ContentPreviewViewer.onDraw` → `prepareBlurBitmap` → `ScrimOptions.makeGlobalBlurBitmaps` → `AndroidUtilities.makeGlobalBlurBitmap(…, 15)`) draws every window once into a software bitmap at 1/15 of the display, stack-blurs it once (radius `max(15, max(w, h) / 180)`, so 15 at that size), applies a colour matrix (`adjustSaturationColorMatrix` and `adjustBrightnessColorMatrix`: dark +0.04 saturation, -0.04 brightness; light +0.25, -0.07; luminance weights 0.3086, 0.6094, 0.0820; brightness as an offset of 255), and draws it as a `BitmapShader` scaled x15 with linear filtering. It is taken the first time the menu is visible and recycled on close; only its alpha animates (`blurProgress` 16/120 a frame, in and out), over a `windowBackgroundGray` wash scaled by the same progress.

| Area | Decision |
| ---- | -------- |
| Primitive | `BackdropSnapshotSource` / `BackdropSnapshot` / `BackdropSnapshotView` in chrome_foundation: a scrim backdrop is chrome, and the leaf every surface package already depends on. The source is a repaint boundary the host places once above its navigator; `capture` reads its layer from the last frame (`OffsetLayer.toImageSync` at `devicePixelRatio / downscale`), blurs and tones it once into a second small image, and drops the raw one. The view is a `RawImage` with `BoxFit.fill`, bilinear, its opacity the paint's alpha: no layer, no offscreen. |
| When | At the preview's open, not the menu's: the window is held from then on (`holdBackground`), and the capture lands 1.3 s before the menu, inside a smooth window, instead of in the menu's first frame. `toImageSync` runs on the raster thread off the frame (FrameTiming does not show it): judged on the device by total span. Not taken for a mouse preview, which has no menu. Disposed as the overlay goes. One still per session: a menu that goes and comes back as the finger slides shows the same one. |
| Values | Downscale 15. Blur sigma 6.5 in the still's pixels, the Gaussian of the reference's radius-15 stack blur (its triangular kernel's deviation, about (r + 1) / sqrt(6)). Tone as the reference's, by the chrome's brightness. Fade: the menu's `showDuration` (120 ms) on the opacity alone. |
| Not ported | The `windowBackgroundGray` wash under the fading still. The reference's still includes the preview window's own dim (its bitmap is drawn from every window, the preview's included, with the preview image hidden), so its dim is applied twice; ours is captured before the preview paints and the dim is drawn once over it. |
| Off | `ContentPreviewController.blursBackground` (on by default), read as each preview opens; without a source the menu is over the dim alone. The example's scroll lab switch `preview_blur` drives it: the dim-only ceiling the still is measured against. |

| Facet | |
| ----- | - |
| Philosophy | A blur over a frozen background is an image, not a filter: compute it once. |
| Thinking | What it is: a one-shot resource with a lifecycle (capture, show, dispose) owned by the session. Who knows: the host places the source; the session decides when and with what tone; the primitive knows nothing of previews. Repeating: one scrim today; any scrim over a held window can take it. Tool: the layer's own `toImageSync` and one `ImageFilter.blur` pass, no shader, no native code. What can go wrong: a host without a source (dim only, said in the host guide), a capture that includes what the caller is about to show (taken between frames, before it paints), a leaked image (disposed with the overlay). |
| Criticality | A live `BackdropFilter` stays right for a background that moves under the scrim; this one does not. |
| Exceptions | The glass capture (`GlassSource`) stays separate: it re-captures as its region changes, every frame if needed, and samples regions; the snapshot is whole-window, once. |

**207.** Each mount of `PanelSearchField` (a stock `EditableText`, after a page switch) ran the Android `PROCESS_TEXT` query (`flutter/processtext` `queryTextActions`) synchronously on the platform thread, which is the UI thread: 176 ms cold, 51 ms warm, 21 and 13 of 48 refreshes missed. Only the composer's forked field cached it (`prefetchProcessTextActions`). Flutter 3.41's `EditableText` has no hook for the service (`_processTextService` is a private `DefaultProcessTextService`), so the shared answer sits where every field's query passes: the binding's messenger. `ProcessTextQueryCache` (composer_editable, which owns the once-per-run query, divergence L) answers `ProcessText.queryTextActions` from the first reply (calls in flight share it, a failed call is asked again, everything else passes through); hosts reach it through `ComposerView.shareTextActions` (ADR 020 rule 6) and return it from their binding's `createBinaryMessenger` (the example's `AppBinding`). The composer's prefetch after the first frame is then the only query the platform sees. The fork's own static cache stays: it serves hosts without the binding.

## Amendment: the still is blurred on the CPU (native-media 209, 210, 211; supersedes the 206 "Tool" and "Values" blur)

On an Android device (Impeller, Vulkan) the GPU-made still went wrong twice. First its edges faded to clear and the sharp window showed through, although its `ImageFilter.blur` asked for `TileMode.clamp` (209; fixed by padding the blur's input with the capture's clamped edge pixels over an opaque fill). Then it showed a grid of blocks, one per captured pixel, both when stretched 15 times (210) and when made at 1/3 through an image shader enlargement and a 5 x sigma blur (211). The host engines (Skia and Impeller on Metal under `flutter test`) reproduce neither, so a GPU-side fix cannot be verified off the device.

| Facet | Decision |
| ----- | -------- |
| Primitive | `BackdropSnapshot.capture` still takes the layer at `devicePixelRatio / downscale` between frames, synchronously; it then reads its pixels (`toByteData`), and on the CPU lays them over an opaque `background`, stack-blurs them and applies the tone in one pass (`stackBlurRgba`, run through `compute`, so off the UI isolate where there is one), and decodes the result (`decodeImageFromPixels`). The snapshot is a `Listenable`: `image` is null until the still is made, `ready` completes then. The view draws nothing until then, and then the still stretched with bilinear sampling (`FilterQuality.low`). No image filter, shader or upscale is left in the path. |
| Values | Downscale 15; stack blur radius 15 (`ContentPreviewSession.backdropBlurRadius`), the reference's `max(15, max(w, h) / 180)` at a phone's size; the blur repeats the edge pixels as the reference's does, truncating each pass. Tone and dim unchanged. |
| Timing | The still is asked for as the preview opens and is made within a few frames, long before a sticker's menu (1300 ms). The menu never waits: until the still is made, it is over the dim alone, and the still fades in with whatever opacity the menu's fade has reached. |
| Cost | `stackBlurRgba` on 96 x 208 pixels (a 1440 x 3120 window at 1/15), radius 15, toned: about 1.1 ms on the development Mac under `flutter test` (JIT), measured by the package's test. |
| What can go wrong | A still that never comes (the capture cannot be read): the menu stays over the dim alone. A snapshot disposed before its still is made: the still is disposed as it arrives. |
