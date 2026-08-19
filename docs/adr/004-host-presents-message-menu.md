# ADR 004: Host presents the message menu

**Status**: Accepted  
**Date**: 2026-08-19

The viewport owns the **idle message tap** seam (full present-message slot, not bubble ink) while **message selection** is inactive. It is not gated on **selection-allowed** — that predicate is membership-only. The host decides whether to present a menu. It exposes that seam as `ChatScrollView.onIdleMessageTap` with `(id, slotGlobal, tapGlobal)`. Null is a no-op — the viewport never presents the overlay. The host calls a presenter (the package may ship a default). That presenter is chrome and session contract only: actions and reactions are host data per presentation, not an engine `MessageAction` catalog. Pixel match to Telegram is best-effort. Android pre-IME back interception is an app `Activity` concern, not a package `android/` plugin.

A **message menu session** is a snapshot: one id, one captured slot rect, overlay eats pointers so the viewport does not scroll under it. The default presenter watches a host-provided presence signal and **dismisses** with no action when that id becomes **absent** — no retarget onto a neighbor. The viewport is not queried. No signal means no watch.

IME visibility is frozen for the session. **Message menu dismiss** (first Back / Escape / scrim) ends only the session. The presenter owns that in Dart (`OverlayBackButtonListener`) and pushes a **pre-IME back claim** onto a package LIFO stack. Native intercept is on iff the stack is non-empty; the example `MainActivity` delivers one back to the top claim. A single overwriting slot (as in flutter_md) is rejected. No package `android/`.

Viewport-owned overlay was rejected: modal hit-testing and IME/back policy do not belong in the render object ([Host Chrome Insets](../architecture/14-host-chrome-insets.md)). A package Android plugin was rejected: this package is Dart-only; the example already owns `MainActivity` for host-only platform hooks.
