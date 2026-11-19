# attach_sheet

The **attach sheet**: the mobile container a user picks media and files to
send from. It owns the window (scrim, geometry, open and close, drag, expand,
collapse, dismiss), the **discard guard** and the keyboard hand-off, each by
a per-platform policy; the content is a page that scrolls on the sheet's
scroll controller, so one drag moves the sheet and then scrolls the page.
Depends on `attach_model` and `chrome_foundation`.

Decisions: [ADR 046](../../docs/adr/046-media-picker.md).

## Types

| Type | Role |
| --- | --- |
| `AttachSheet` | The container. `AttachSheet.show(context, policy:, selection:, builder:, host:, opening:, header:, bottomBar:)` pushes it and completes with an `AttachOutcome`. The `builder` gets the sheet's scroll controller (also the `PrimaryScrollController` below the sheet). |
| `AttachSheetController` | `AttachSheetController.of(context)` below the sheet: `top`, `isExpanded`, `expand`, `collapse`, `requestDismiss` (asks first with a selection), `close`, `dismissesOnTapAbove`, `panEnabled`. |
| `AttachSheetPolicy` (`$Android`, `$IOS`) | Geometry, motion, release rule, snap, discard wording, keyboard rules; `forPlatform` / `current`. Not sealed: extend a stock family to change a value. `release` is a pure function of `AttachSheetReleaseInput`. |
| `AttachSheetMotion` | `spring(SpringDescription)` or `timed(MotionSpec)`. |
| `AttachSheetHost`, `AttachSheetOpening` | What the sheet tells its host (`opened`, `closed`, `restoreKeyboard`) and asks (`confirmDiscard`); the opening carries whether the keyboard was up and the attach button's rect. |
| `AttachDiscardQuestion` | The stock question in the policy's `AttachDiscardWording`. |
| `AttachOutcome` | `cancelled`. |

## Host contract

| Step | What the host does |
| --- | --- |
| Scopes | A `ChromeThemeScope` (the `attach` token group), a `ChromeStringsScope` (`ChromeStrings.attach`) above the navigator; a `ChromeMotionScope` with `ChromeMotionSpeed.instant` for reduce motion. |
| Open | Parks its keyboard and panel, then `AttachSheet.show` with `AttachSheetOpening(keyboardWasUp:, anchor:)` and the open's `AttachSelection`. |
| Keyboard | Raises the keyboard in `restoreKeyboard` when the policy brings it back. |
| Page | Builds a vertical scrollable on the controller it is given (or `primary: true`). |

## Rules and values

| Rule | Android | iOS |
| --- | --- | --- |
| Rest | top at 2/5 of the height under the status bar (1/3.5 landscape) + 39 | top at `floor(max(w, h) * 0.2488)`, 0.15 at width ≤ 320, 0 in landscape |
| Top | under the status bar, header fades in over 380 ms, corners square off | under the status bar |
| Corners, grabber | 12; 36 x 4 at 20, fades with the header | 38 (0 in landscape); 36 x 5 at 5 |
| Scrim | 51/255, in 400 ms overshoot (0.7) after 20 ms, out 250 ms | 25 %, in 0.3 s linear, out 0.25 s ease in out |
| Open, close | spring damping ratio 0.75, stiffness 350; close 250 ms ease out | springs of mass 5, stiffness 900, damping 110 |
| Drag | rises with the page's scroll; pulled down at the page's start | the same hand-off; off while the keyboard is up |
| Release | below rest: dismiss past 0.8 cm or at 3500 physical px/s, else back over 250 ms per 0.8 cm; between rest and top: fling with the page, snap to the top inside 56 | from rest: dismiss past 60 or down at 300 pt/s, expand up at 300 pt/s or past half the inset, else back over 0.3 s; from the top: dismiss at 1800 pt/s, collapse at 300 pt/s or past half the inset; springs of damping 124 (dismiss 180) |
| Tap above | dismisses (a page can turn it off) | dismisses |
| Discard guard | "Discard selection?" on any dismiss with a selection | "Cancel selection?"; a pan past 40 is cancelled into it |
| Keyboard | back 200 ms after close when it was up | not brought back; caption focus expands |
| Wide screen | none | a 390 x min(670, available) card above the attach button, scrim 10 % |
