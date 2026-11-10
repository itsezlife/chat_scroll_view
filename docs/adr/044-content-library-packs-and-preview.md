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
| Pack sheets | A sticker pack sheet and an emoji pack sheet (one pack, several packs) (ticket 123), shown by the host as a modal bottom sheet on touch and a centred box under a pointer. Inputs: the pack id(s), the `PackSource`, the library's read side, an optional `PackLinkBuilder` (`Uri? Function(PackId)`: no builder, no Share or Copy link), an optional send callback (present only when opened for a composer that can send), and a request callback for library edits. The sheet shows `PackSource.peek` while it looks up: loading, the pack, or not found (the sheet closes itself and the host tells the user). The grid is a `PanelCatalogViewport` (one section, or one per pack among several, whose headers the sheet draws over the grid); tap and hold open the preview, and a right-click opens its menu entries as a context menu. On touch a tall sheet opens part-way and rises with its grid to the status bar (ticket 126). |
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

