# ADR 046: Media picker

A host lets the user pick photos, videos and files to send. The chat side is
two portable packages. `attach_model`, a pure-Dart leaf over `content_model`,
holds the **attach selection**, the **attach limits**, the **edited item**
reservation, the **send options**, the **send plan** (a pure function) and
the per-platform rules. `attach_sheet` is the UI: on Android and iOS a sheet
with pages (Gallery, Files and host pages) and a panel with the caption and
the counter send button; on desktop and web a **confirm box** that every
intake route leads to. Everything that is media rather than chat is mpx's
([mpx ADR 0011](https://github.com/itsezlife/mpx/blob/main/docs/adr/0011-library-and-picking.md)):
the device library and the file intake (`mpx_library`), preparation before
upload and the live camera (`mpx_capture`), and the library grid with its
selection, camera slot, album switcher, access states and picker-mode viewer
(`mpx_ui`). The host turns a send plan into messages; no picker package knows
what a message is.

**Status**: Accepted (decided with the maintainer 2026-11-20; package split
revised the same day, see *Resolved questions*)  
**Date**: 2026-11-20  
**Relates to**: [ADR 012](012-cross-platform-selection-policies.md) (policy shape),
[ADR 020](020-package-topology.md) (two packages added, below),
[ADR 023](023-data-layering-and-persistence.md) (`KeyValueStore` for send
options), [ADR 026](026-composer-model.md) (caption input),
[ADR 027](027-foundation-theme-glass-motion.md) (token groups, motion roles),
[ADR 031](031-localization-accessibility-and-input.md) (strings, semantics, shortcuts),
[ADR 032](032-rich-clipboard.md) (pasted media), [ADR 034](034-rich-text-wire-and-persistence.md)
(the caption is a `RichText`), mpx ADR 0006 (viewer pieces), mpx ADR 0007
(capture), mpx ADR 0011 (library, intake, preparation, grid)

## Context

The workspace has a composer and a chat list but no way to attach media. The
reference clients (teardown with file and line in
`.scratch/media-picker/research/`) split the work the same way on every
platform: a container (sheet or modal) owns the window, caption, send button
and dismissal; pages implement one contract; data loaders are separate and
cached; the selection is an ordered list with per-item state; a send plan
cuts it into groups of ten and places the caption; rights are injected, not
looked up. The mobile references pick from an in-app grid over the photo
library with a live camera cell; the desktop and web references have no grid:
the file dialog, drag and drop and paste each open one confirm box. The
platforms differ in values (sheet geometry, gestures, grouping and caption
rules, encoder settings, what is remembered), not in mechanism.

The loaders, the grid and the encoders know nothing of a chat, so they live
in mpx where other hosts can take them. The container, the caption, the send
plan and the rights are a chat's, so they live here.

## Decided

### Scope of v1

| In v1 | Later (the contracts leave room) |
| ----- | -------------------------------- |
| Gallery and Files pages on Android and iOS | Music, location, contact, poll, checklist pages; bot pages (all host-registered pages under the page contract) |
| The grid's camera cell (1 column x 2 rows) and a minimal full-screen capture surface; system camera on long-press (Android) and as the fallback | Camera modes, zoom dial, dual camera |
| Confirm box on desktop and web, fed by file dialog, drop and paste; reorder by drag in the box (desktop) | Folder and archive sending |
| Send plan with grouping, caption placement, timer, spoiler, silent, schedule, send as file, high quality | Paid media, message effects, send preview with a rendered message |
| Picker-mode viewer with the caption and Send in its bottom slot | Editor (crop, paint, adjust, video trim, mute, cover); the **edited item** contract is reserved now |
| Paged library, Android partial access, iOS limited access (mpx) | Pinch zoom levels, fast-scroll date thumb, launch cache, selected-items preview with reorder on mobile |
| | The album mosaic in message rendering (a chat-side follow-up, below) |

### Packages and dependency direction

Arrows point at the dependency. `(git)` is mpx, pinned to one commit in every
pubspec as [ADR 020](020-package-topology.md) states.

```
attach_model   -> content_model
attach_sheet   -> attach_model, chat_composer, chrome_foundation,
                  content_model, viewport_scroll,
                  mpx_library, mpx_capture, mpx_ui, mpx_core (git)
example (host) -> all of the above
```

`attach_sheet` takes `mpx_core` for `MediaKey` and `ContentView`, which the
three mpx packages expose in their API; hosts import what they use.

| Package | Kind | Owns | Never |
| ------- | ---- | ---- | ----- |
| `attach_model` | Pure Dart (`meta`, `listen` and `content_model` only) | **Attach item** (source, kind, facts, per-item state, the edited-item slot), **attach selection** (ordered, capped per policy, kind-gated, ranged toggles, reorder, snapshot for undo), **attach limits** (injected rights and numbers), **send options**, the **send plan** function, **attach policy** (`$Android` / `$IOS` / `$Desktop` / `$Web`), the **send option store** over `KeyValueStore`; fakes and contract suites in `testing.dart` | Flutter, platform code, mpx, message types, layout geometry |
| `attach_sheet` | Flutter | **Attach sheet** (container), **attach panel** (tabs, caption from the composer, counter send button, send menu), the **attach page** contract and host registration, the Gallery page (hosts `mpx_ui`'s library grid, adapts its picker selection to the attach selection, fills its camera slot and the picker-mode viewer's bottom slot), the Files page, the **confirm box** and its **drop zones**; the sheet's token group and strings adapters | Messages, upload, encoding, rights lookup, library or intake code of its own, feedback UI (it raises **attach interactions**; the host shows bulletins) |

Why `attach_model` takes `content_model`: the caption is the composer's
`RichText` value ([ADR 034](034-rich-text-wire-and-persistence.md)) and the
send option store is a `KeyValueStore` client
([ADR 023](023-data-layering-and-persistence.md)); both are already in the
pure-Dart leaf, and nothing else is taken from it.

Why `attach_model` takes no mpx: a pure-Dart leaf cannot depend on a Flutter
plugin. An attach item names its source by plain values (a library asset id,
a path, a blob handle, a local key's stable form); `attach_sheet` maps mpx's
types to them.

Rules added to [ADR 020](020-package-topology.md) (by convention until the
dependency lint learns them):

1. `attach_model` depends on `content_model` only; it imports no Flutter.
2. `attach_sheet` reaches the caption field through `chat_composer`'s view
   and controllers, never `composer_editable` (rule 6 stands).
3. No picker package depends on the root `chat_scroll_view`, `panel_*`,
   `bulletins`, `glyph_atlas` or `content_assets`.
4. The device library, file intake, preparation and the grid are mpx's; a
   chat package does not re-implement them.
5. Fakes only in `testing.dart`; no re-exports (rules 2 and 4 stand).

### The attach model

| Area | Decision |
| ---- | -------- |
| Item kinds | `photo`, `video`, `animation` (GIF, silent looping video), `audio`, `file`. Classification is the intake's (mpx); a picked kind can be overridden by "send as file". |
| Attach source | Sealed: library asset (its id), file (path), web blob (handle), captured (a local key), pasted (a local key). |
| Attach selection | Ordered by selection; 1-based **order numbers** re-index on removal; the first occurrence wins. The cap is the policy's: **100** on `$Android` and `$IOS`, **none** on `$Desktop` and `$Web`; 1 when the host asks for single select. Over the cap a toggle is refused and an interaction raised. A kind the limits forbid is refused the same way. Range toggles take the state of the first item for every item crossed. Reorder keeps per-item state. |
| Attach limits | Injected by the host per open: allowed kinds, single select, caption length, file size limit, timer allowed, schedule allowed, grouping allowed (slow mode), spoiler allowed, send as file allowed. The picker never looks rights up. |
| Edited item | An attach item carries an optional `edits` (an opaque recipe an editor owns, versioned) and an optional `derived` output (a local key, dimensions, duration, `muted`, `animated`). The plan and preparation read `derived` in place of the source when present; "edited" counts in option visibility. v1 writes neither. |
| Send options | `grouped`, `asFiles`, `highQuality`, `silent`, `schedule` (a time or "when online"), `captionAbove`, per-item `spoiler` and `timer`, video preset choice. |
| Send option store | Per-platform persistence through `KeyValueStore`: Android keeps the high-quality default and the video preset per offered count; iOS keeps high quality and the preferred video preset; desktop keeps group and as-files (and large photos) only when the user ticks "Remember", app-wide; web keeps nothing. |

### The send plan

`planSend(request, policy, limits) -> SendPlan` is a pure function. A request
is the ordered items, the caption and the options. A plan is an ordered list
of **planned sends**: `single(item, caption?)`, `group(items, captionIndex?)`
or `text(caption)`, or a typed rejection. Every item appears once, in
selection order.

| Rule | Value |
| ---- | ----- |
| Group size | At most 10 per **send group** on every platform, whatever the selection cap; a group of one is a single. |
| What shares a group | Photos and videos together; files with files; audio with audio; with "send as file", photos and videos group as files. A type change starts a new group. |
| Grouping off | One single per item. |
| Breaking groups | An item with a timer is never grouped (every platform). Android: only that item leaves its group. Desktop: any timer turns grouping off for the batch. iOS: any timer, animation or muted item turns grouping off for the batch. Web: any animation turns grouping off for the batch. An animation is never grouped. |
| Spoiler | Never breaks a group on any platform; it is a per-item flag inside a group. |
| Caption placement | Android: first item of the first group. iOS: first item if grouped, last if not. Desktop: first item of the last group when it is a photo/video group, else the last item. Web: first send; with more than one group the caption is a `text` send ahead of the groups. |
| Timer and schedule | An item with a timer cannot be scheduled; the plan rejects the pair. Timers clear under "send as file". |
| Over-limit caption | The plan rejects it; the panel signals per policy before asking. |
| Preparation | Not the plan's. The host prepares each planned item through `mpx_capture`'s `MediaPreparer` with `PreparationPolicy.forPlatform` (mpx ADR 0011 holds the values), reading `highQuality`, `asFiles` and the video preset from the options. |

### Presentation

| Area | Decision |
| ---- | -------- |
| Mobile | An **attach sheet** with pages and a bottom panel. The panel is the container's: the tab bar, and once anything is selected, the caption field and a counter send button in its place. The page owns its content and tells the container its offsets, header items and whether it may be dismissed. |
| Desktop and web | No grid. The attach button opens the file dialog (a menu when the host registers more pages); Ctrl/Cmd+O, drop and paste lead to the same **confirm box**; every route adds to the box when one is open. Drop and paste come from `mpx_library`'s intake (over `super_drag_and_drop` on desktop, DOM events on the web); a paste in the composer arrives through `ComposerController.onPastedMedia` ([ADR 032](032-rich-clipboard.md)) and is mapped to intake files. |
| Confirm box previews | A run of photos and videos is drawn by a host-supplied group preview builder; without one the box draws a plain thumbnail strip. The mosaic is the chat's message album layout (out of scope here). |
| Policy | `AttachSheetPolicy.$Android` / `$IOS` / `$Desktop` / `$Web`: pure values for geometry, motion, gestures, thresholds, discard rule, caption counter threshold and over-limit feedback, menu visibility. `forPlatform` maps the OS; a browser is `$Web` on every device. A host may pick any. |
| Composer text | Moves into the caption on open, back to the composer on cancel or when the last item is removed, cleared on send. The same on every platform. |
| Discard | Android and iOS: a non-empty selection asks before dismissing. Desktop: click outside does nothing; Escape and Cancel close and return the caption. Web: Escape closes and returns the caption. |
| Keyboard | The host is told on open and close (`AttachSheetHost`), so it can park its IME and panel presentation and raise the keyboard again after close where the policy says. |

### The attach page contract

A page is an `AttachPage`: an id, a tab label and icon, a builder, and a kind.

| Kind | Contract |
| ---- | -------- |
| Selection page | Adds items to the sheet's one attach selection (Gallery, Files). The panel and send menu work for it. |
| Host page | Builds its own content and finishes with an `AttachOutcome.custom(payload)` the host reads (location, contact, poll, bots). It may ask for the main button and hide the panel. |

Page hooks, through `AttachPageScope`: request expansion, scroll to top on a
re-tap, the container's pan enable, the top offset and header items, a
dismiss guard, visibility (`onShow` / `onHide`), and whether the page is
active (the camera slot pauses when not). The host builds the page list per
open from its rights; the package registers Gallery and Files as stock pages.

### The Gallery and Files pages

| Page | Decision |
| ---- | -------- |
| Gallery | Hosts `mpx_ui`'s library grid with `LibraryGridPolicy.forPlatform`. Implements the grid's picker selection seam over the attach selection, so library picks, captures and files share one order; the gate refuses by the attach limits and the policy's cap and raises attach interactions. Fills the camera slot with `mpx_capture`'s session preview; a tap opens the capture surface, a long-press (Android) or an unavailable session opens the system camera through `mpx_library`; captured items join the selection first. Fills the picker-mode viewer's bottom slot with the panel's caption and send button; Send with nothing checked sends the current item. |
| Files | Rows "Choose from gallery" (the Gallery page in file mode: picks send as files) and "Choose from files" (`mpx_library`'s file dialog, multi-select unless single select); a recent-files section from a host `RecentFilesSource`, which the example leaves empty. |

### What stays in the host

Rights and limits, the page list, mapping a plan to messages (ids, reply,
send-as, upload), running preparation, schedule and timer pickers, feedback
(bulletins for refusals and undo), the composer bridge, the recent-files
source, the group preview builder, and where captured media is saved.

### Keyboard, composer and back between the chat and the sheet

One owner at a time for each of the text, focus, the soft keyboard, the
panel and back.

| While | Text | Focus and keyboard | Panel | Back (pre-IME claims) |
| --- | --- | --- | --- | --- |
| The chat alone | the composer's | the composer | the chat's (keyboard replacement, popup, docked) | the chat panel's claim while it is up |
| The sheet opening | the caption starts as the composer's text; the composer keeps it | the composer lets go; a raised keyboard's place goes to the chat's panel at its height, so the chat does not move | the chat's, in the keyboard's place, under the sheet | the sheet pushes its claim over the panel's (again, after the panel came up) |
| The sheet up | the caption's | the caption field; raising the keyboard takes the sheet to its top (Android) and the caption bar stands on the keyboard | the caption's own (its emoji panel), never two interactive panels | the sheet's claim: keyboard first (the field lets go), then the caption's panel, then the top route (viewer, menu, alert, the sheet with its discard question) |
| The viewer over the sheet | the same caption | the viewer's caption bar (same controller); every close of the viewer lets go | none of its own | the same claim: keyboard, then the viewer |
| After a cancel | the caption, when changed, becomes the composer's text; unchanged, nothing is written | the keyboard comes back in the chat panel's place after the sheet's keyboard delay (200 ms on Android); else the composer takes focus back if it had it | the chat's goes as the keyboard rises | the sheet's claim is popped; the panel's is on top again |
| After a send | the caption went with the media: the composer empties when the caption was not empty | as after a cancel | as after a cancel | as after a cancel |

Hosts wire it through `AttachSheetHost.opened`, `closed` and
`restoreKeyboard`; the example's `ChatAttach` takes the chat's
`yieldKeyboardToPanel` and `handOffToKeyboard` and holds the sheet's claim.
The packages keep no global state for it: the sheet's own rules
(`expandsOnCaptionFocus`, the bar on the keyboard, every close letting go
of focus) are its policy's, the stacking of claims is the host's.

### Resolved questions (maintainer, 2026-11-20)

| # | Question | Answer |
| - | -------- | ------ |
| 1 | Android's 432 px video step vs mpx's 480 | mpx adds a 432 preset; no 480 substitute (mpx ADR 0011) |
| 2 | iOS photo JPEG quality | 0.6 at 1280 and at 2560, thumbnail 320 px at 0.4, traced in upstream Telegram-iOS (`.scratch/media-picker/research/ios-jpeg-quality.md`) |
| 3 | Capture surface scope | Minimal: shutter (tap photo, hold video), switch, flash, close |
| 4 | Selection cap | 100 on mobile, none on desktop and web; send groups stay at 10 |
| 5 | Spoiler and groups | A spoiler never breaks a group |
| 6 | Desktop drag and drop and paste | `super_drag_and_drop` (and its clipboard reader), inside `mpx_library` |
| 7 | Album mosaic home | The chat's message rendering, a follow-up outside the picker |
| 8 | Recent files on the Files page | A host source, empty in the example |
| - | Package split | Library, intake, grid, preparation and camera in mpx (`mpx_library`, `mpx_ui`, `mpx_capture`); the chat keeps `attach_model` and `attach_sheet` |

## Why

- The split (container, pages, loaders, ordered selection, pure plan,
  injected rights) is the one both mobile references use and the desktop and
  web references reduce to, so one model serves two front-ends.
- What a messenger alone needs (caption, plan, grouping, rights) stays in the
  chat; what any picking app needs moves to mpx, where it sits beside the
  encoders and the viewer it builds on.
- A pure plan with policies makes every grouping and caption rule a unit test
  and keeps platform differences in values, as [ADR 012](012-cross-platform-selection-policies.md) asks.
- An attach model without Flutter can be tested and reused by a non-UI host.
- Implementing the grid's selection seam over the attach selection gives one
  set of order numbers across library picks, captures and files.
- The caps follow each platform's reference: mobile clients stop at 100,
  desktop and web clients take any number and cut groups of 10.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| One `media_picker` package | Puts native plugins and Flutter in front of the pure plan |
| The library, intake and grid in the chat (`media_library` and a grid in `attach_sheet`) | Nothing in them is a chat's; other mpx hosts would rebuild them |
| A grid on desktop and web | Neither reference has one; browsers have no library access |
| Grid on `panel_catalog` | Its leaves are content keys in sections; library assets are not |
| The sheet building messages | Ties a portable package to one host's message model |
| One selection cap on every platform | Desktop and web users of the references pick any number |
| One caption and grouping rule for all | Each platform's users expect their reference's result |
| A spoiler breaking a group | No reference does; a spoiler is per item inside an album |
| The album mosaic in `attach_model` | It is message layout; the box borrows it from the host instead |

## Consequences

- Two workspace members join the root `workspace:` list; ADR 020 gains
  their rows and the rules above when they land.
- The chat moves its mpx pin in every pubspec once mpx ADR 0011's work lands,
  and takes `mpx_library`, `mpx_capture` and `mpx_ui` where `attach_sheet`
  and the example need them.
- `chrome_foundation` gains an attach token group and motion roles;
  `ChromeStrings` gains an attach strings group; the grid's and viewer's
  strings and tokens are adapted from them.
- Glossary: a new Attach glossary ([CONTEXT-MAP.md](../../CONTEXT-MAP.md)
  gains it); the Content and Assets glossary points at mpx's library terms.
- The album mosaic is a chat-side follow-up in message rendering; when it
  lands, the example passes it to the confirm box as the group preview.
- The edited-item slot is in the model from v1, so an editor adds a writer
  and no model change.
