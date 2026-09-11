# ADR 012: Cross-platform selection policies

**Status**: Accepted  
**Date**: 2026-09-12  
**Supersedes**: [ADR 010](010-message-then-text-selection.md)

Chat-list **message selection** and **text selection** are two modes under one
domain model. How they nest, enter, dismiss, and behave on Copy is a
**selection policy**, not a universal mobile rule.

- **Mobile policy** (Telegram Android–like): message-then-text entry (span
  yield / explicit Select text on an already-selected message); text-active
  keeps the **text selection subject** nested in the selected set (collapsed
  to that id); dismiss-text clears the range but keeps the subject selected;
  Copy success clears text and message mode.
- **Desktop/web policy** (Telegram Desktop–like): direct character-range entry
  without prior message membership; text-active and message membership are
  **mutually exclusive** (entering text clears the selected set); Copy writes
  the clipboard only and keeps the range; dismiss clears text; Esc clears the
  active selection kind.

Hosts supply the policy (sealed strategy variants, e.g. `$Mobile` / `$Desktop`);
default maps OS family (iOS/Android → mobile; desktop + web → desktop). Copy
success is observable via typed listeners and an optional callback; **copy
feedback UI** (Android system affordance vs silent desktop) stays app-side.
Conditional `_vm` / `_js` imports are only for real native/web spirit forks —
not for splitting these pure-Dart policies.

## Considered options

- **Android-only forever (ADR 010 as universal law)** — rejected: Desktop/web
  entry and Copy/dismiss contradict message-then-text and Copy-clears-mode.
- **Two unrelated controllers / hosts** — rejected: duplicates lifecycle and
  drifts glossary.
- **Pointer-kind policy switching** — rejected as default (surprising on
  phone + mouse); hosts may still override.
- **Cross-platform modes + host-overridable policy strategies** — accepted.
