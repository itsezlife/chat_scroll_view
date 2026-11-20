# attach_sheet

The **attach sheet**: the mobile container a user picks media and files to
send from. It owns the window (scrim, geometry, open and close, drag, expand,
collapse, dismiss), the **discard guard** and the keyboard hand-off, each by
a per-platform policy; the content is a page that scrolls on the sheet's
scroll controller, so one drag moves the sheet and then scrolls the page.
On desktop and web the same model goes through the **confirm box**. Depends on `attach_model`, `chat_composer` (the caption field), `chrome_foundation`, `content_model`, `viewport_scroll` (the page's fling the sheet carries) and mpx's `mpx_core`, `mpx_library` (library, file intake, drop), `mpx_ui` (library grid) and `mpx_capture`.

Decisions: [ADR 046](../../docs/adr/046-media-picker.md).

## Types

| Type | Role |
| --- | --- |
| `AttachSheet` | The container. `AttachSheet.show(context, policy:, selection:, pages:, host:, opening:)` pushes it with its pages and tab bar and completes with an `AttachOutcome`; `AttachSheet.showContent(builder:, header:, bottomBar:)` pushes it around any content, whose `builder` gets the sheet's scroll controller (also the `PrimaryScrollController` below the sheet). |
| `AttachPage`, `AttachPageId`, `AttachPageKind` | One page: id, tab label and icon, builder, kind (`selection` adds to the attach selection; `host` finishes with its own payload), an optional `AttachPagePermission`. `AttachPageId.gallery` and `.files` are the stock ids. |
| `AttachPageRegistry` | The pages of one open, in tab order, and the one it opens on; built by the host from its rights. |
| `AttachPageScope` | A page's hooks: `isActive` (its `onShow` / `onHide`), `scrollController`, `requestExpansion`, `panEnabled`, `topOffset`, `headerItems`, `dismissGuard`, `onScrollToTop`, `mainButton` (`AttachMainButton`), `panelHidden`, `finish(payload)`. |
| `AttachTabBarStyle`, `AttachTabStyle`, `AttachTabColors`, `AttachTabIndicator`, `AttachTabPopIn`, `AttachTabSwitch` | The tab bar's geometry, glass, colours (the theme's `AttachTokens` by default), tab layout and mark, hide motion, pop-in and badge rule, and the page switch motion, per policy; a policy subclass restyles it with `super.tabBar.copyWith(...)`. A page's `selectedIcon` is worn while it is shown. |
| `AttachSheetController` | `AttachSheetController.of(context)` below the sheet: `top`, `isExpanded`, `expand`, `collapse`, `requestDismiss` (asks first with a selection), `close`, `dismissesOnTapAbove`, `panEnabled`. |
| `AttachSheetPolicy` (`$Android`, `$IOS`) | Geometry, motion, release rule, snap, discard wording, keyboard rules; `forPlatform` / `current`. Not sealed: extend a stock family to change a value. `release` is a pure function of `AttachSheetReleaseInput`. |
| `AttachSheetMotion`, `AttachSheetMorph` | `spring(SpringDescription)` or `timed(MotionSpec)`; the morph's channels out of and back into the attach button. |
| `AttachSheetHost`, `AttachSheetOpening` | What the sheet tells its host (`opened`, `closed`, `restoreKeyboard`) and asks (`confirmDiscard`); the opening carries whether the keyboard was up and the attach button's rect. |
| `AttachDiscardQuestion` | The stock question in the policy's `AttachDiscardWording`. |
| `AttachSendController` | The **attach panel**'s state, one per open: the caption (`ComposerController`, the host's composer text at open), the `SendOptions` (restored from a `SendOptionStore`, saved on send), the send and overflow entries that show (`sendMenu`, `overflow`), `send`, `runSendMenu`, `runOverflow`. A page reaches it as `AttachPageScope.panel`. |
| `AttachCaptionBar`, `AttachSendButton`, `AttachPanelReveal`, `AttachOverflowButton`, `AttachMenu` | The caption field with its counter and the counter send button (tap sends, long press opens the send menu); the panel taking the tab bar's place while something is selected; the header's overflow button; the small menu both open. |
| `AttachPanelStyle`, `AttachCountBounce`, `AttachSendMenuItem`, `AttachOverflowItem`, `AttachHaptic` | The panel's values per policy. |
| `AttachInteraction` | `captionTooLong(over:)`, `refused(reason)`: what the host gives feedback for. |
| `AttachOutcome` | `cancelled(caption)`, `send(request)`, `custom(page, payload)`. |
| `GalleryPage`, `GalleryView`, `AttachPickerSelection` | The stock Gallery page: `mpx_ui`'s `LibraryGrid` over the device library, its picker selection over the attach selection (shared order numbers, the cap and kind gate, refusals raised as attach interactions), the overflow menu in the header, the host's camera slot, a fast scroll thumb with the month in view. |
| `FilesPage`, `RecentFilesSource`, `IntakeItems` | The stock Files page: the gallery as files, the file dialog (`FileIntake.pickFiles`), the host's recent files (placeholder rows while loading); intake files as attach items. |
| `ConfirmBox`, `ConfirmBoxController`, `ConfirmBoxView`, `GroupPreviewBuilder`, `ItemThumbnailBuilder` | The desktop and web modal: title, previews from the send plan (the host's group layout, else a strip; single media; file rows), options (desktop checkboxes with Remember, web More menu), reorder (desktop), per-item actions, the panel, the send menu, keys. `addFiles` / `pickAndAdd` / `paste` add to the open box. |
| `AttachDropOverlay` | The drop zones over the chat region on `mpx_library`'s `IntakeDropRegion`. |
| `ConfirmBoxStyle`, `ConfirmBoxReorder` | The box's values per family (`AttachSheetPolicy.$Desktop`, `$Web`). |

## Host contract

| Step | What the host does |
| --- | --- |
| Scopes | A `ChromeThemeScope` (the `attach` token group), a `ChromeStringsScope` (`ChromeStrings.attach`) above the navigator; a `ChromeMotionScope` with `ChromeMotionSpeed.instant` for reduce motion. |
| Open | Parks its keyboard and panel, then `AttachSheet.show` with `AttachSheetOpening(keyboardWasUp:, anchor:)` and the open's `AttachSelection`. |
| Keyboard | Raises the keyboard in `restoreKeyboard` when the policy brings it back. |
| Pages | Builds an `AttachPageRegistry` per open from its rights; each page builds a vertical scrollable on `scope.scrollController`. Pages are built the first time their tab shows and kept for the open. |
| Caption move | Passes its composer text as `initialCaption`; on `cancelled(caption)` puts the caption back in the composer; on `send(request)` clears the composer and plans the request (`planSend`). |
| Options | Passes a `SendOptionStore` built for the selection's attach policy. |
| Feedback | `AttachSheetHost.interaction` (a caption over the limit, a refused item), `pickSchedule`, `pickTimer`, `openExternalPicker`. |
| Library | An `AssetCacheProvider` above the sheet whose fetcher sends library keys to `LibraryFetcher(library)`; the `MediaLibrary` and `FileIntake` for the stock pages. |
| Confirm box | One `ConfirmBoxController` per box; while `isOpen`, every route (dialog, drop, paste) goes to it. |
| Outcome | Reads `AttachOutcome.custom(page, payload)` from a host page. |

## Rules and values

| Rule | Android | iOS |
| --- | --- | --- |
| Rest | top at 2/5 of the height under the status bar (1/3.5 landscape) + 39 | top at `floor(max(w, h) * 0.2488)`, 0.15 at width ≤ 320, 0 in landscape |
| Top | under the status bar, header fades in over 380 ms, corners square off | under the status bar |
| Corners, grabber | 12; 36 x 4 at 20, fades with the header | 38 (0 in landscape); 36 x 5 at 5 |
| Scrim | 51/255, in 400 ms overshoot (0.7) after 20 ms, out 250 ms | 25 %, in 0.3 s linear, out 0.25 s ease in out |
| Open, close | slides up on a spring of damping ratio 0.75, stiffness 350; close 250 ms ease out | grows out of the attach button (`AttachSheetOpening.anchor`): position on a spring of damping 110 from 1.1, bounds damping 110, corners 0.2 s, content in over 0.2 s; back in: position 110, bounds and corners 124, content out over 0.12 s. Without a button rect: a slide on damping 110. Springs are mass 5, stiffness 900 |
| Drag | rises with the page's scroll; pulled down at the page's start | the same hand-off; off while the keyboard is up |
| Release | below rest: dismiss past 0.8 cm or at 3500 physical px/s, else back over 250 ms per 0.8 cm; between rest and top: fling with the page, snap to the top inside 56 | from rest: dismiss past 60 or down at 300 pt/s, expand up at 300 pt/s or past half the inset, else back over 0.3 s; from the top: dismiss at 1800 pt/s, collapse at 300 pt/s or past half the inset; springs of damping 124 (dismiss 180) |
| Tap above | dismisses (a page can turn it off) | dismisses |
| Discard guard | "Discard selection?" on any dismiss with a selection | "Cancel selection?"; a pan past 40 is cancelled into it |
| Keyboard | back 200 ms after close when it was up | not brought back; caption focus expands |
| Wide screen | none | a 390 x min(670, available) card above the attach button, scrim 10 % |
| Tab bar | `tabs` glass stadium 56 tall, 7 from the sides and above the bottom inset; tabs 48 tall 4 inside it, clipped to the stadium: a 24 icon 4 from the top, an 11 label from 28.33 (medium, extra bold when shown); the shown tab in the accent on a 9 % accent stadium growing from 0.6 over 320 ms, the others in the text colour; a held tab washed at 6 %; tab = label + 16 a side (8 from a 56 label), at most 84, spare room shared; 8 edge fade; a tapped tab scrolled 70 clear | glass capsule 62; 160 / 240 / 300 wide for 2 / 3 / 4 tabs, else the screen less 22 a side; a glass lens 3 inside the shown tab (radius 28) slides between tabs on a spring of damping 88 and follows a drag across them |
| Tab pop-in | staggered 32 ms (the fourth tab first), 0 to 1.1 in 200 ms, 1.1 to 1 in 100 ms, after 20 ms | none |
| With a selection | the bar drops 36 and fades over 180 ms (44 over 380 ms while the sheet is at its top) | fades over 0.1 s and shrinks to 0.85; back over 0.25 s |
| Tab switch | old page drops 78 and fades over 180 ms, then the new one springs up from 78 (ratio 0.75, stiffness 500); taps wait | 0.23 s cross-fade, the new page rising 10 on a spring of damping 70 |
| Re-tap, single tab | scrolls the page to the top and expands; one tab collapses the bar | same |
| Permission badge | "!" on a tab whose page lacks its permission; a tap asks for it | none |
| Panel swap | the caption fades in and Send grows from 0.2 over 180 ms (decelerate) | the panel rises 44 and fades in over 0.25 s |
| Caption counter | at 100 left | under 5 left |
| Over the limit | shake, key-tap haptic, `captionTooLong`, nothing sent | shake, error haptic, `captionTooLong`, nothing sent |
| Count bounce | from 0.9 over 180 ms (overshoot) | to 1.2 (up) or 0.8 (down) over 0.1 s, back over 0.1 s |
| Send menu (long press) | without sound, schedule, caption above | without sound, schedule, when online, caption above |
| Overflow | open in external app (nothing selected), send as file(s), without grouping, spoiler, high / standard quality, caption above | send as file(s) (no spoiler), send in HD, without grouping, caption up / down, spoiler |
| Hidden | schedule with any timer or without the right; caption above without a caption or with a file | same |
| Confirm box | desktop: 364 wide, previews 308, blocks 10 apart, at most 1280 tall, click outside inert, 200 ms; web: 420 wide, radius 40, previews 384, 30 % overlay, a 48 rise over 0.15 s | |
| Box options | desktop: Group items, Send as documents, Remember (after a change, app-wide); web: More menu (Add, as media / as files, group / ungroup all, spoilers, caption) | |
| Box keys | Enter sends (not while composing), Escape cancels with the caption, Ctrl / Cmd+O adds; web: a printable key focuses the caption | |
