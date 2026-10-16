# ADR 028: Panel presentation strategies (mobile vs desktop and web)

`panel_presentation` decides where the panel appears and how it opens, closes
and takes space. A sealed set of presentation kinds is chosen by a pure-Dart
`$Mobile` / `$Desktop` policy, each kind publishes the space it occupies as a
`ValueListenable` (`package:listen`), and one controller owns visibility. This supersedes the
inset-controller parts of [ADR 007](007-keyboard-panel-controller.md).

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — occupancy and state are `package:listen` `ValueListenable`s ([ADR 023](023-data-layering-and-persistence.md) Amendment)  
**Amended**: 2026-10-16 — keyboard readings include the safe area; the sheet's rounded top; the host lowers a raised keyboard when the panel takes its place  
**Relates to**: [ADR 007](007-keyboard-panel-controller.md) (superseded in part), [ADR 012](012-cross-platform-selection-policies.md) (same policy shape), [ADR 025](025-panel-shell-and-pages.md), [host chrome insets](../architecture/14-host-chrome-insets.md) (amended by this ADR)

## Decided

| Area | Decision |
| ---- | -------- |
| Kinds and policy | Sealed `PanelPresentation`: `KeyboardReplacement` (in-flow, takes the bottom slot), `AnchoredPopup`, `Docked`. A pure-Dart policy in the [ADR 012](012-cross-platform-selection-policies.md) shape (`$Mobile`, `$Desktop`, no `_vm` / `_js` forks) owns open triggers, dismissal, sizing and animation roles. The default follows OS family (iOS and Android: `$Mobile`; desktop and web: `$Desktop`) and an adaptive window class; the host may override per call. A sheet or modal kind can be added later. |
| Occupancy | Each presentation publishes a `ValueListenable` occupancy (bottom extent, inline-end extent). `KeyboardReplacement`: animated `max(IME, panel)`. `AnchoredPopup`: zero. `Docked`: inline-end width. The host adds composer extent and `occupancy.bottom` into the viewport `bottomPadding` and applies `inlineEnd` in layout. |
| IME input | The host feeds raw IME samples (height, animating, safe area) through one input port, from `MediaQuery` or a keyboard-insets package. The mobile strategy applies filtering, hold and hand-off internally. Foundation reads no platform insets. |
| Controller | One `PanelPresentationController`: sealed visibility state (`hidden`, `showing`, `shown`, `hiding`, plus the active kind), `show`, `hide`, `toggle`, `handleBack`, and strategy-aware intents (`waitForIme`, anchor, dock and undock). Commands commit when unbound. It wraps the `PanelShellController` and reacts to `SearchOpened`, `SearchClosed` and `PageChanged`. |
| Switching | Selected page, search state, per-page scroll offsets and loaded collections live in controllers (shell and per-page), not widget state. A switch rebuilds the shell subtree and restores everything. No `GlobalKey` reparenting. The transition is a motion role. |
| AnchoredPopup | Copied from Desktop `TabbedPanel`. Hover over the toggle opens it; a click toggles. Leaving hides after 300 ms and a 3 s idle delays a hide. The shell reports `preventAutoHide` while the variant picker is open, search is focused or a drag is in progress. Esc and outside click dismiss. It anchors bottom-end of the composer rect, which the host supplies. Height is 0.75 times the window height clamped to 278..640. It scales and fades from the bottom-end origin (`popupShow` / `popupHide` roles). Hover-open applies to mouse only; touch is click only. |
| Docked | Copied from Desktop `TabbedSection`. A persisted `PreferenceStore` choice. The toggle moves a popup to docked when the window class is wide, and undock closes it. Occupancy is the inline-end width. |
| KeyboardReplacement | Android `WindowInsetsStateHolder` and the iOS height table are the references. Occupancy animates with the `listTransition` role. Panel height comes from the measured IME height persisted per orientation (sanity floor, device-class default). Explicit IME and panel hand-off states have a fallback timeout (Android: 1 s). `SearchOpened` grows the panel to an expanded height. Safe area and navigation bar are added inside the strategy. `handleBack` closes search first, then the panel. The host sets the composer's `softKeyboard` from presentation visibility. |

## Amendment: what the host owes the keyboard strategy

Device checks of the first cut found three things the decisions above left to
the host without saying so.

| Area | Decision |
| ---- | -------- |
| Keyboard readings | `ImeSample.height` counts the bottom safe area as part of the keyboard. iOS reports it that way; the Android inset plugin reports the IME without the system bars. A host whose platform does not count the band adds it back while the keyboard shows any height (a height of nothing stays nothing). Without it the slot measures the keyboard too short by the band, and the composer sinks behind a keyboard that stands that much higher. |
| Lowering the keyboard | Declaring no soft keyboard does not lower one that is showing. When a keyboard-replacement panel opens the host asks the keyboard to hide, keeping focus. |
| Sheet | The keyboard-replacement sheet is the slot: while the slot grows or shrinks the sheet's top edge (rounded, `KeyboardReplacementTuning.sheetCornerRadius`, 29) rides it and the strip and the search field stay under the composer, and the bottom bar stays on the bottom edge. The first cut laid the sheet out at its final height and let the slot clip it, so the content stood still and was uncovered from the bottom; the panel it replaced moved with its top edge, and that is the motion kept. A slot shorter than the shortest sheet (96) shows the top of a shell laid out at 96 instead of overflowing. `KeyboardSlot.layoutHeight` stays for a presentation that wants the still content; this strategy does not read it. |

## Why

- Desktop (`tdesktop` tabbed panel and compose controls): the toggle is an event filter on the popup with hover open, click toggles, hide timers of 300 and 3000 ms, `preventAutoHide` from the selector, bottom-right anchoring and ratio sizing. The third-section docked mode is a persisted setting when it fits and the layout is not one column. The selector is borrowed between host and panel.
- Android arbitrates `max(system, ime, inApp)` with one animator, persists the keyboard height and has explicit hand-off states. iOS uses a per-device height table and no measured height.
- The old inset controller was 412 lines of heuristic IME filtering, and panel state sat in four holders with `adopt*` back-doors.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Two fixed platform presentations; an open registry of presentations | A fixed pair cannot add a sheet; an open registry cannot be switched on exhaustively |
| Presentation owning the whole bottom stack (composer, panel, IME, viewport link); a shared inset service every presentation reports into | The host already aggregates; desktop popups have no inset |
| One controller class per presentation kind; merging visibility back into the shell controller | The host would hold one controller per kind; visibility and page selection change for different reasons |
| `GlobalKey` reparenting; switching that resets the panel | Loses scroll offsets, search and loaded collections |

## Related

- Glossary: [Chat chrome](../chrome/CONTEXT.md)
