# ADR 028: Panel presentation strategies (mobile vs desktop and web)

`panel_presentation` decides where the panel appears and how it opens, closes
and takes space. A sealed set of presentation kinds is chosen by a pure-Dart
`$Mobile` / `$Desktop` policy, each kind publishes the space it occupies as a
`ValueListenable` (`package:listen`), and one controller owns visibility. This supersedes the
inset-controller parts of [ADR 007](007-keyboard-panel-controller.md).

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — occupancy and state are `package:listen` `ValueListenable`s ([ADR 023](023-data-layering-and-persistence.md) Amendment)  
**Amended**: 2026-10-16 — desktop parity of the popup: it never takes focus, the hover machine is the reference client's, the panel button docks and undocks, and `holdAutoHide` is the one hold seam (see below)  
**Amended**: 2026-10-16 — the host wires the shell's page holds to that seam ([ADR 025](025-panel-shell-and-pages.md) Amendment)  
**Amended**: 2026-10-16 — keyboard readings include the safe area; the sheet's rounded top; the host lowers a raised keyboard when the panel takes its place  
**Amended**: 2026-10-16 — the dock is a standing section with a width the user drags; the popup keeps a gap from the composer  
**Relates to**: [ADR 007](007-keyboard-panel-controller.md) (superseded in part), [ADR 012](012-cross-platform-selection-policies.md) (same policy shape), [ADR 025](025-panel-shell-and-pages.md), [host chrome insets](../architecture/14-host-chrome-insets.md) (amended by this ADR)

## Decided

| Area | Decision |
| ---- | -------- |
| Kinds and policy | Sealed `PanelPresentation`: `KeyboardReplacement` (in-flow, takes the bottom slot), `AnchoredPopup`, `Docked`. A pure-Dart policy in the [ADR 012](012-cross-platform-selection-policies.md) shape (`$Mobile`, `$Desktop`, no `_vm` / `_js` forks) owns open triggers, dismissal, sizing and animation roles. The default follows OS family (iOS and Android: `$Mobile`; desktop and web: `$Desktop`) and an adaptive window class; the host may override per call. A sheet or modal kind can be added later. |
| Occupancy | Each presentation publishes a `ValueListenable` occupancy (bottom extent, inline-end extent). `KeyboardReplacement`: animated `max(IME, panel)`. `AnchoredPopup`: zero. `Docked`: inline-end width. The host adds composer extent and `occupancy.bottom` into the viewport `bottomPadding` and applies `inlineEnd` in layout. |
| IME input | The host feeds raw IME samples (height, animating, safe area) through one input port, from `MediaQuery` or a keyboard-insets package. The mobile strategy applies filtering, hold and hand-off internally. Foundation reads no platform insets. |
| Controller | One `PanelPresentationController`: sealed visibility state (`hidden`, `showing`, `shown`, `hiding`, plus the active kind), `show`, `hide`, `toggle`, `handleBack`, and strategy-aware intents (`waitForIme`, anchor, dock and undock). Commands commit when unbound. It wraps the `PanelShellController` and reacts to `SearchOpened`, `SearchClosed` and `PageChanged`. |
| Switching | Selected page, search state, per-page scroll offsets and loaded collections live in controllers (shell and per-page), not widget state. A switch rebuilds the shell subtree and restores everything. No `GlobalKey` reparenting. The transition is a motion role. |
| AnchoredPopup | Copied from Desktop `TabbedPanel`. It anchors bottom-end of the composer rect, which the host supplies. Height is 0.75 times the window height clamped to 278..640. It scales and fades from the bottom-end origin (`popupShow` / `popupHide` roles, 200 ms each). Hover-open applies to mouse only; touch is click only. The pointer rules, holds, dismissal and focus have their own rows below. |
| Popup pointer machine | Hover over the toggle opens it at once. Leaving the toggle hides it at the next event pass (a 0 ms timer), which entering the popup cancels: the popup's hover area is its card plus a transparent gutter (`AnchoredPopupStyle.hoverGutter`) plus a bridge down to the registered toggle's top edge, so the pointer is never over neither. Leaving the popup hides after 300 ms, or at the next pass while it is still appearing. Entering the popup or the toggle while it fades out shows it again. A leave under a hold is dropped; once the last hold is released with the pointer away, it hides after 3 s. There is no other idle timer: an interaction in the panel arms nothing, a popup nobody left and nothing holds stays until dismissed. Flags are cleared with the state: the popup flag and the touch flag when it is hidden, the toggle flag when the toggle leaves the tree under the pointer. A popup last pressed by touch or stylus has no leave or after-hold delay. |
| Holds | `PanelPresentationController.holdAutoHide()` is the one seam through which anything keeps a popup open; the guard is true exactly while a hold is unreleased. Holds are counted and independent (any release order, idempotent release, notification on the first hold and the last release only, inert after dispose). Taken by the popup itself for a catalogue drag or fling and for a pointer button pressed inside it (a scrollbar drag, a selection) until it is released, wherever the pointer ends up. A menu or variant picker takes one through the host: pages hold through `PanelPageHost.holdAutoHide()`, the shell publishes the count (`PanelShellController.autoHideHolds`), and the host keeps one hold here while the count is above zero, because pages and the shell cannot depend on this package. Search focus is not a hold. |
| Dismissal | Esc steps back (search first, then the popup). A press outside dismisses at once, except on the toggle, on the popup's own hover area, and on any `AnchoredPopupExemptRegion` the host registers (the composer: a click back into it keeps the popup). `AnchoredPopupToggleRegion` is exempt by itself. |
| Focus | The popup never takes focus when it opens, by hover or by click: the composer keeps the caret, the search field is focused only by the user clicking into it, and the panel stays reachable by Tab. A pick keeps focus in the composer and the popup stays open. Closing with the search field focused hands focus back to the composer (the reference client drops it to the window; this is deliberate). |
| Docked | Copied from Desktop `TabbedSection`. A persisted `PreferenceStore` choice. Occupancy is the inline-end width. The popup does not take focus from the composer, and neither does the section. |
| Arrangement | A kind chooses the shell's `PanelArrangement` ([ADR 025](025-panel-shell-and-pages.md)) and nothing else decides it. `KeyboardReplacement` is `touch`: the sticky header, the inline search field and the bar that slides away, as the amendment below keeps them on the sheet. `AnchoredPopup` and `Docked` are `pointer`: tabs on top, the strip pinned at the bottom, nothing that slides away. A popup docked in place changes arrangement under a mounted page, which takes the other layout without losing its scroll or search. |
| Toggle click | On a desktop kind the panel button is also the dock control: hidden or hiding shows (docked if the saved choice is docked and the window can dock, else a popup); a popup in a window that can dock docks, the same panel moving with its page, scroll and search; a popup in a window that cannot dock hides; a docked panel undocks, and the popup does not appear until the pointer re-enters the toggle. The glyph is the same in every state; docked is drawn as the active state. Only the mobile keyboard-replacement kind shows the keyboard glyph. |
| KeyboardReplacement | Android `WindowInsetsStateHolder` and the iOS height table are the references. Occupancy animates with the `listTransition` role. Panel height comes from the measured IME height persisted per orientation (sanity floor, device-class default). Explicit IME and panel hand-off states have a fallback timeout (Android: 1 s). `SearchOpened` grows the panel to an expanded height. Safe area and navigation bar are added inside the strategy. `handleBack` closes search first, then the panel. The host sets the composer's `softKeyboard` from presentation visibility. |

## Amendment: what the host owes the keyboard strategy

Device checks of the first cut found things the decisions above left to
the host without saying so.

| Area | Decision |
| ---- | -------- |
| Keyboard readings | `ImeSample.height` counts the bottom safe area as part of the keyboard. iOS reports it that way; the Android inset plugin reports the IME without the system bars. A host whose platform does not count the band adds it back while the keyboard shows any height (a height of nothing stays nothing). Without it the slot measures the keyboard too short by the band, and the composer sinks behind a keyboard that stands that much higher. |
| Lowering the keyboard | Declaring no soft keyboard does not lower one that is showing. When a keyboard-replacement panel opens the host asks the keyboard to hide, keeping focus. |
| Raising it again | Android keeps the input type a field attached with. A composer that took focus while suppressed (a panel opened from idle, then left for the keyboard) never raised a keyboard, and the hand-off waited out its one-second fallback before closing cold. The hand-off now asks for the keyboard (`ComposerController.requestKeyboard`): the field focuses, or attaches again with the type the mode declares, and that raises it. Lifting the suppression alone raises nothing, so a panel closed with back leaves focus in the field and the keyboard down, as the panel always did; a tap on such a field attaches it again too. A first cut that attached again on every change of mode raised the keyboard on back. |
| Leaving search | Leaving a panel whose search is open (by the panel button or a tap on the field, with the search field focused or not, the keyboard up or down) is three steps in order: ask for the keyboard, so the composer takes focus from the search field and the keyboard never drops; once the composer holds focus, close search and wait for the slot to settle (`KeyboardReplacementStrategy.animating`) at the panel's height; then `hide(waitForIme: true)`. The first cut did all three at once: the hand-off ran from the expanded height, so the panel vanished in one frame, and the search field let go of focus before the composer took it, so the keyboard dropped and rose again. A tap on the field lifts the suppression on the press (`ComposerView.onFieldPointerDown`), so the tap's focus attaches with the keyboard allowed; a press that is no tap puts it back. |
| Presses in quick succession | The panel button acts on what the previous press asked for, as the reference client and the pre-refactor panel do, not on how far the motion has come. A press while the panel leaves for the keyboard and is still on screen (search shrinking back) stops the hand-off and keeps the panel; one while it hides brings it back. In both cases the keyboard is asked down again, which the first cut did only for a panel that was hidden: a panel turned back mid-hand-off sat over a keyboard still rising. The toggle's glyph follows the press, not the phase. |
| Confirmed keyboard | Device traces (Android) of presses 40–100 ms apart show a hide and a show that cross reporting one settled reading at the keyboard's full height between zeros. The slot took it at its word, handed over, and then followed the keyboard to zero and back up: the composer dropped by the keyboard's height and rose again. The pre-refactor inset controller guarded this with a streak of two samples. The slot now takes the keyboard to be up once a settled reading has stood for `KeyboardReplacementTuning.settleConfirmation` (80 ms on the presentation clock) with no other reading after it, both before a close and during the hold. A panel that replaces the keyboard drops the confirmation, since it asks that keyboard down. A hand-off that times out over a keyboard still reading settled up hands over instead of closing cold. This replaces the earlier "no sample counters, no wall-clock windows" rule; the window is on the presentation clock, so tests still run time by hand. |
| Bottom band | The composer's extent leaves out its bottom safe-area pad, and the host adds `max(safe area, occupancy)`. The extent is measured after layout and arrives a frame late; a sum that waited for the composer's pad to grow back while the slot shrank under the safe area dipped by up to the band at the end of every close. |
| Sheet | The keyboard-replacement sheet is the slot: while the slot grows or shrinks the sheet's top edge (rounded, `KeyboardReplacementTuning.sheetCornerRadius`, 29) rides it and the strip and the search field stay under the composer, and the bottom bar stays on the bottom edge. The first cut laid the sheet out at its final height and let the slot clip it, so the content stood still and was uncovered from the bottom; the panel it replaced moved with its top edge, and that is the motion kept. A slot shorter than the shortest sheet (96) shows the top of a shell laid out at 96 instead of overflowing. `KeyboardSlot.layoutHeight` stays for a presentation that wants the still content; this strategy does not read it. |

## Why

- Desktop (`tdesktop` tabbed panel and compose controls): the toggle is an event filter on the popup with hover open, click toggles, hide timers of 300 and 3000 ms, `preventAutoHide` from the selector, bottom-right anchoring and ratio sizing. The third-section docked mode is a persisted setting when it fits and the layout is not one column. The selector is borrowed between host and panel.
- Android arbitrates `max(system, ime, inApp)` with one animator, persists the keyboard height and has explicit hand-off states. iOS uses a per-device height table and no measured height.
- The old inset controller was 412 lines of heuristic IME filtering, and panel state sat in four holders with `adopt*` back-doors.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Two fixed platform presentations; an open registry of presentations | A fixed pair cannot add a sheet; an open registry cannot be switched on exhaustively |
| A focus request on open that only a hover open skips; search focus as a hold; an idle timer restarted by every interaction | The reference client does none of these: its panel keeps the caret on every open, hides on the pointer leaving whether or not search is focused, and times out only after a hold ends |
| Presentation owning the whole bottom stack (composer, panel, IME, viewport link); a shared inset service every presentation reports into | The host already aggregates; desktop popups have no inset |
| One controller class per presentation kind; merging visibility back into the shell controller | The host would hold one controller per kind; visibility and page selection change for different reasons |
| `GlobalKey` reparenting; switching that resets the panel | Loses scroll offsets, search and loaded collections |

## Related

- Glossary: [Chat chrome](../chrome/CONTEXT.md)

## Amendment: the dock is a standing section

The first cut treated the dock as a panel a click or a hover brought up that
happened to sit at the end edge. The reference client's is a section of the
window: the user's saved choice and the room the window has decide whether it is
there, and it stays. This amends the *Docked*, *Dismissal*, *Toggle click* and
*Occupancy* rows above.

| Area | Decision |
| ---- | -------- |
| Whether it shows | `dockPreferred` (the saved choice) and `PanelPresentationPolicy.canDock(window)`. The window has the room when the content and a dock fit side by side: 380 and 292 logical pixels, so 672 wide. The Material window class is not read. |
| Standing | While both hold the dock is on screen with no click: the controller shows it at construction, when the preference is turned on, and when the window widens to the room. When either stops holding the panel is hidden (a window that narrows does not turn the dock into a popup, and the preference stays), and a popup open when the dock comes back gives way to it. The controller acts when the answer changes, not on every report of the window, so a dock the host hid on purpose stays hidden until the window or the choice changes. |
| Dismissal | A dock is dismissed by no gesture (`dismissalsFor(Docked)` is empty): Escape and back step out of search, and nothing else; the panel button undocks (preference off, panel hidden, no popup until the pointer re-enters the button). |
| Width | `PanelPresentationPolicy.dockWidthIn(window, wanted:)`: the wish held between `dockMinWidth` (292) and `dockMaxWidth` (392), no wider than leaves `dockMinChatWidth` (380) to the content, never under 292. A dock nobody has dragged is `DockedStyle.width` held to those bounds, or 292. |
| Resizing | A 6 px strip along the dock's start edge (`dockResizeExtent`) under the horizontal-resize cursor. The edge follows the pointer from the press, with the point grabbed under it (the reference client's press offset); `PanelPresentationController.resizeDock` takes the raw wish frame by frame and the chat narrows with it, `endDockResize` holds it to the bounds and keeps it. What is kept is the wish, in `DockWidthStore` (a sibling of `KeyboardHeightStore`: a size of the panel's own chrome, not a typed choice of the `PreferenceStore`), so a window that widens gives the dragged width back. |
| Popup gap | `AnchoredPopupStyle.edgeGap` is the room between the popup and the composer's top and end edges (the reference client's popup is a card 10 px in from the corner). The pointer's hover area still bridges it to the toggle. |
| Motion | Unchanged: the dock slides with `panelSlide`. The reference client opens and closes it instantly. |

## Amendment: the composer keeps its focus

On a desktop platform a text field gives up its focus on a mouse press outside
its tap region, so a click on an emoji took the caret from the composer. The
popup (its hover area), the dock's body, the variant picker and the context menu
are each a `TextFieldTapRegion`: a press there belongs to the composer's region
and leaves its focus and selection where they are, as in the reference client.
The composer's own buttons (the panel toggle among them) are in that region
too, so clicking one never takes the caret from the field.

## Amendment: glass, and an anchor that follows the composer

| Area | Decision |
| ---- | -------- |
| Glass | The popup, the dock and the keyboard-replacement sheet put the shell on a `GlassSurface` of the composer island's material (`GlassMaterial.composerIsland`), so the panel reads as the composer does; the shell paints no background of its own there (`PanelShell.background`). Over the chat (the popup) it blurs the messages; beside or under it (dock, sheet) it shows as the material's fill. The popup's glass takes the card's radius, the dock's is square, the sheet's clip rounds its top corners. The reference desktop client paints its panel solid: this is the product's choice. |
| Anchor | The host reports the composer's rectangle whenever it moves, not only when the composer rebuilds: a dock that comes or goes moves a composer held at its greatest width without resizing or rebuilding it, and a popup opened later anchored to where it had been. The example reads it after every frame and reports a change (the controller ignores an equal one). |
