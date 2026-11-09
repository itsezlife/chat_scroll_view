# ADR 045: Bulletins

A **bulletin** is a short in-app notice over a surface: "Copied", "Stickers
removed — Undo", "GIF saved". A portable `bulletins` package holds the
bulletin value, a host-owned controller per surface with the reference
clients' one-slot and commit-on-leave semantics, a mount widget with a
bottom-obstruction seam, and a pure-Dart presentation policy per platform
family. Colours are a token group and timings two motion roles in
`chrome_foundation`; labels come from chrome strings. The platform visuals
are builders the host picks, so they land without changing the core.

**Status**: Proposed  
**Date**: 2026-11-09  
**Relates to**: [ADR 012](012-cross-platform-selection-policies.md) (policy shape), [ADR 020](020-package-topology.md) (amended: new leaf above `chrome_foundation`), [ADR 027](027-foundation-theme-glass-motion.md) (token group and motion roles added), [ADR 030](030-testing-policy.md) (fake clock and contract suite), [ADR 031](031-localization-accessibility-and-input.md) (strings group, announcement), [ADR 044](044-content-library-packs-and-preview.md) (an `AppliedEdit` behind an Undo bulletin)

Items marked **[confirm]** are defaults chosen without the maintainer and
open to change before the status moves to Accepted.

## Context

The reference clients show transient notices three ways
(`.scratch/native-media-ffi/research/bulletins.md`, constants with file and
line): Android's `Bulletin` (a card at the bottom of the screen above the
composer and keyboard, spring slide, horizontal swipe, press holds the timer,
one visible app-wide, an Undo button whose delayed action runs when the
bulletin leaves without Undo), iOS's `UndoOverlayController` (a blurred card,
fade and scale, no swipe, the caller dismisses the old one with its commit
action) and desktop's `Ui::Toast` (a toast centred in the window, no Undo).
The workspace had none: the example used Material snack bars, and feedback is
the host's ([AGENTS.md](../../AGENTS.md) invariant; [ADR 044](044-content-library-packs-and-preview.md) row *Feedback*).

## Decided

### Package

| Area | Decision |
| ---- | -------- |
| Placement | A new package `packages/bulletins`: a leaf UI package over `chrome_foundation` only. No chat, panel, content or asset dependency; a host that has none of those can show bulletins. The undo commit is a callback, so a host bridges an `AppliedEdit` ([ADR 044](044-content-library-packs-and-preview.md)) without the package knowing it. |
| Glossary | *Bulletin*, *Bulletin controller*, *Bulletin host*, *Bulletin policy*, *Commit on leave*, *Bottom obstruction* (Chat Chrome glossary). |

### The value

| Area | Decision |
| ---- | -------- |
| Bulletin | An immutable `Bulletin`: a `message`, an optional `title` (title over subtitle, the reference's two-line layouts), an optional `leading`, an optional `action`, a `duration` (null: chosen by the factory rule), an optional `placement` (null: the policy's), an optional body tap callback and an optional spoken label (default: title and message). |
| Content kinds | What differs between the reference layouts is the leading slot, so that is the sealed family: `BulletinLeading.icon(ChromeIconId)` (a stock or host-registered chrome icon, tinted), `.animation(Object source)` (a vector animation such as the reference's Lottie icons), `.thumbnail(Object source)` (a sticker or photo), `.countdown()` (the ring with the seconds left, drawn from the handle's remaining time) and `.custom(WidgetBuilder)`. `animation` and `thumbnail` carry an opaque source the host's builder resolves (an asset key, a content key); with no builder the slot keeps its size and stays empty, never a failure state. Text is one line without a title and up to two lines under one, as the reference; `maxLines` overrides. |
| Action | Sealed `BulletinAction`: `.undo(onUndo:, onCommit:)` and `.button(label:, onPressed:)`. The undo label comes from chrome strings; a button's label is the caller's. Pressing either closes the bulletin. |
| Duration class | `BulletinDuration.short`, `.long`, `.prolonged`, `.untilDismissed` and `.exactly(Duration)`. The policy maps a class to a timeout. Factory rule when the bulletin names none (the reference's `BulletinFactory`): an undo bulletin is prolonged; otherwise text under 20 characters (title and message together) is short, longer is long. |

### Controller and semantics

| Area | Decision |
| ---- | -------- |
| Owner | One `BulletinController` per surface, created and disposed by the host and mounted by a `BulletinHost`. Not a global singleton: a sheet or a second window has its own. One visible app-wide (Android's static slot) is the host's choice of how many controllers it makes. **[confirm]** |
| One slot | `show(bulletin)` returns a `BulletinHandle` and takes the slot. A bulletin already showing closes as *replaced*; there is no queue (Android). The policy is fixed for the controller's life. |
| Closing | Every handle closes exactly once, with a `BulletinExit`: `timedOut`, `replaced`, `dismissed` (the host's `dismiss`), `swiped`, `actionPressed`, `undone`, `surfaceGone` (the host unmounted, or the controller was disposed). `handle.closed` completes with it and never with an error. |
| Commit on leave | An undo bulletin's `onCommit` runs exactly once when it closes with any exit but `undone`; `onUndo` runs once when Undo is pressed, and then `onCommit` never runs. So the commit runs on timeout, swipe, replacement, `dismiss`, an unmounted host and controller disposal (Android's `delayedAction` in `onDetach`; iOS's `.commit`). A bulletin shown on a disposed controller closes at once as `surfaceGone` and commits. |
| Undo window and `AppliedEdit` | The bulletin, not the library's timer, ends the window: the host applies the edit with an undo window no shorter than the bulletin can stay (`Duration` of the prolonged class plus any pause) and wires `onUndo: applied.undo`, `onCommit: applied.commit`. Commit is idempotent there, so the longer window is only a guard. **[confirm]** (alternative: an untimed edit window in `content_model`) |
| Timer | The timeout starts when the view reports the enter transition finished (`handle.markEntered`), not at `show` (Android posts its hide runnable after the enter, B:355). `untilDismissed` has no timer. Time comes from a `BulletinClock` seam (`system`, and `ManualBulletinClock` in `testing.dart`), never `Timer` directly. |
| Pause | `handle.pause()` stops the timer; `resume()` starts the whole timeout again (Android re-posts the full duration on release, B:192-198). The host view pauses on press where the policy says so; a host may pause for its own reasons (an open reaction row). `remaining` is the time left while running, the full timeout before entering or while paused, and null without a timer. |
| Change signal | `controller.current` is a `ValueListenable<BulletinHandle?>`; it notifies on show and on close. |

### Host mount

| Area | Decision |
| ---- | -------- |
| `BulletinHost` | A widget over the surface's content: `BulletinHost(controller:, obstruction:, builders:, child:)`. It lays the bulletin out in the area the policy and the obstruction leave, plays the enter and exit (the outgoing bulletin finishes its exit while the new one enters), runs the policy's gestures, announces the bulletin to assistive technology on show (Android does, B:276; iOS relies on its nodes) and closes the current one as `surfaceGone` when it unmounts. It reads the policy from the controller. |
| Bottom obstruction | `obstruction`: a `ValueListenable<EdgeInsets>` of what covers the surface's edges (at the bottom the composer, its safe inset and the keyboard; at the top a bar). The bulletin keeps clear of it and follows a change with the policy's follow spring (Android: stiffness 900, no bounce, B:299-303). Null: the view padding and keyboard inset of the `MediaQuery` (Android's window-inset fallback). Where the policy clips at the obstruction, the bulletin enters from behind the bottom edge rather than over the composer (B:1222-1229). |
| Builders | `BulletinBuilders`: `frame` (the surface behind the content: shape, fill, glass or blur), `content` (the whole body; default lays out leading, title, message and action), `leading` (per leading kind, so the host resolves `animation` and `thumbnail`) and `action`. Each defaults to a stock builder that paints with the token group and the policy's metrics, plain and flat. Tickets 130-132 add per-platform builder sets (Android glass card, iOS blur, desktop toast) as more stock values; the host chooses one or its own. |

### Presentation policy (layout and motion values)

| Area | Decision |
| ---- | -------- |
| Shape | `BulletinPolicy`: plain values and decisions, no widgets and no platform reads, in the selection policy's shape: `BulletinPolicy.android()`, `.ios()`, `.desktop()` and `BulletinPolicy.forPlatform(TargetPlatform, isWeb:)` (the web gets desktop). Unlike the selection and panel policies it is an `abstract base class`, not sealed, and the stock variants are `base` classes: a host replaces the policy by extending a stock variant and overriding one value, or by implementing its own. Nothing in the package switches over the variants. **[confirm]** |
| Values | Placement (`bottom`, `top`, `center`), outer margin, minimum height, corner radius, width (`maxWidth`, null for the full width), the timeout per duration class, the enter and exit transition, swipe to dismiss and its thresholds, press to pause, press scale, the follow spring, whether the bulletin clips at the obstruction. |
| Android | Bottom; margin 8 horizontal (the reference's 16 dp layout padding draws the card inset by 8 on each side, B:800, B:1221) and 8 vertical; min height 48 (B:797); radius 16 (B:811); full width, capped at 400 on a wide window **[confirm]** (B:121-125 wraps on tablets); timeouts 1500 / 2750 / 5000 (B:89-91); `slide` enter and exit on the spring damping 0.8, stiffness 400 (B:1121-1163); swipe away past a third of the width or a fling over 2000 px/s (B:534-680); press pauses (B:192-198); press scale 0.98 (B:802); clips at the obstruction. |
| iOS | Bottom; side margin 12 (UON:1936); min height 50 (UON:1989); radius 25 (UON:1576); full width; timeouts 3000 / 3000 / 5000 (copy, link, saved and plain notices 3 s; a bulletin with a button 5 s; UON:953, 1032, 1047) **[confirm]**; `fadeScale` from 0.96 (UON:2208-2212, 2242-2247); no swipe, no press pause, no press scale; does not clip. |
| Desktop | Centred in the window (`Ui::Toast` without `attach`); margin 16, min height 40, radius 9 (`chat_helpers.style:973`), width capped at 380 (`chat.style:207-211`); timeouts 1500 / 4000 / 5000 (4 s and 5 s are call sites, `history_view_context_menu.cpp:129`, `history_view_sticker_toast.cpp:31`; the 1.5 s default lives in the unchecked-out `lib_ui`) **[confirm: UNVERIFIED]**; `fade`; no swipe, no pause. The reference shows no Undo in a toast; the policy still shows the action, so an undo offered through the same API stays reachable. **[confirm]** |
| Timed motion | The two new motion roles `bulletinShow` (255 ms, ease-out quad) and `bulletinHide` (175 ms, ease-in quad), the reference Android `DefaultTransition` (B:1058-1098), time the `fade` and `fadeScale` transitions; a spring transition is physical and takes no role. One role table for all three families **[confirm]**: a host wanting the iOS 0.3 s fade overrides the roles through `ChromeMotionScope`. Under `ChromeMotionSpeed.instant` every transition, the spring included, and the follow are jumps. |

### Tokens and strings

| Area | Decision |
| ---- | -------- |
| Token group | `BulletinTokens` in `chrome_foundation` (`ChromeThemeData.bulletin`, `ChromeThemeScope.bulletinOf`): `background`, `foreground` (title, message, icon tint), `accent` (the action and links), `countdown` (the ring and its digits). `fromPalette` gives the reference's dark card on every palette, as the reference keeps it dark in day and night themes (0xEA272F38, white, 0xFF85CAFF; ThemeColors:650-652); `referenceAndroid` names the same values. Metrics are policy values, not tokens ([ADR 027](027-foundation-theme-glass-motion.md) row *Metrics*). |
| Strings | `BulletinStrings` (`ChromeStrings.bulletin`): `undoAction` and `dismissAction` (the spoken dismiss action). Message texts are the host's: it already has them in its own strings (for packs, `PackSheetStrings`). |

### Tests

| Seam | Fake / suite |
| ---- | ------------ |
| `BulletinClock` | `ManualBulletinClock` (advances by hand, `now` included) in `testing.dart` |
| `BulletinPolicy` | `BulletinPolicyContract.run`: timeouts ordered short ≤ long ≤ prolonged and `untilDismissed` untimed, `exactly` passed through, positive metrics, swipe thresholds present when swipe is on. Run over the three stock policies; a host runs it over its own. |
| Controller | Behaviour tests over the manual clock: one slot, every exit once, commit on leave per exit, undo never commits, timer after enter, pause and resume, dispose. |
| `BulletinHost` | Widget tests: placement over the obstruction, follow, exit on unmount, swipe and press per policy, announcement, builders override. |

## Why

- A notice is not chat or panel chrome; a host with neither still wants one,
  so the package sits on the foundation alone.
- The reference's leave rule (commit unless undone, whatever closes it) is
  the contract a pending library edit needs; making it a property of the
  controller means no caller can forget a path (replacement, unmount).
- A controller per surface keeps the reference's per-screen anchoring
  (Android's container per fragment, iOS's `.current`) and lets a sheet hold
  its own, without a hidden global.
- The three families differ in values (margins, radius, timeouts, transition,
  gestures), not in mechanism, so one view reads a value policy; the visuals
  that do differ (glass, blur) are builders, which a host must be able to
  replace anyway.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| A global bulletin service or a static slot | Hides who owns the slot, cannot follow a sheet, and makes tests share state |
| A queue of bulletins | None of the references queues; a stale notice after a newer one misleads |
| Content kinds as one sealed family per reference layout (simple, two-line, Lottie, two-line Lottie, ...) | The layouts differ in the leading slot and line count only; a family per layout multiplies the builders a host overrides |
| A sealed policy | A host could not restyle one value without forking the package |
| The policy building widgets | Layout and motion would stop being testable as values; the visuals belong to the builders |
| The undo window owned by the library's timer alone | The bulletin can outlive it (pause, a slow enter); Undo would show and do nothing |
| Depending on `content_model` for `AppliedEdit` | Couples a notice leaf to the data layer for one callback pair |
| Snack bars (Material) | No commit on leave, no obstruction seam, no platform looks, `ThemeData`-bound |

## Consequences

- `ChromeThemeData`, `ChromeThemeScope` and `ChromeStrings` gain a required
  group each; every host and test that builds them whole adds it.
- `ChromeMotion` gains two roles; a host table built whole adds them.
- Tickets 130 to 132 add per-platform builders and may adjust policy values;
  ticket 133 moves the example's snack bars to bulletins.
