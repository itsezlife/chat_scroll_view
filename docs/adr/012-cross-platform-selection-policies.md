# ADR 012: Cross-platform selection policies

**Status**: Accepted  
**Date**: 2026-09-12  
**Updated**: 2026-09-12 (engine-owned mobile routing; membership/retarget as
this policy; inline hits; deferred desktop drag-out promotion)  
**Supersedes**: [ADR 010](010-message-then-text-selection.md)

Chat-list **message selection** and **text selection** are two modes under one
domain model. How they nest, enter, dismiss, and behave on Copy is a
**selection policy**, not a universal mobile rule. Long-press routing into
text vs **span gesture** is engine-owned under the active strategy — not a
host **span yield** predicate as the named entry mechanism.

Hosts supply the policy (sealed strategy variants, e.g. `$Mobile` / `$Desktop`);
default maps OS family (iOS/Android → mobile; desktop + web → desktop). Copy
success is observable via typed listeners and an optional callback; **copy
feedback UI** stays app-side. Conditional `_vm` / `_js` imports are only for
real native/web spirit forks — not for splitting these pure-Dart policies.

Character-range **text selection** stays one message. At most one **text
selection subject** at a time.

## Mobile (`$Mobile`)

Message-then-text: first long-press on a row enters **message selection** (and
may start a **span gesture**). A further long-press on body text of an
already-selected message enters **text selection** on that subject. Idle
long-press on body text still enters message selection first.

On text entry, this policy **preserves** the selected set of messages intact.
Text selection nests under message selection without destroying other selected
messages, matching Telegram Android behavior.

| Cause                                      | Text selection      | Message selection           |
| ------------------------------------------ | ------------------- | --------------------------- |
| Tap / Back dismiss text                    | clear               | keep existing set           |
| Copy success                               | clear               | clear mode                  |
| Clear / empty message selection            | clear               | clear                       |
| Reposition range within current subject    | move range          | keep existing set           |
| Long-press another selected message’s body | move to new subject | keep existing set           |
| Long-press an unselected message           | clear               | select message / start span |

Retargeting across selected messages while text-active moves text selection to
that subject without mutating message selection. Long-press on an unselected
message preserves message-then-text by clearing text selection and starting
message selection / span gesture.

## Desktop/web (`$Desktop`)

Direct character-range entry: press+drag (letter / word / paragraph by click
count) on bubble text, with no prior **message selection**. Text-active and
message membership are **mutually exclusive**. Settled **message selection**
does not allow starting character-range text selection (tdesktop parity);
inline link/code activation may still fire without clearing membership.

Desktop gestures are drag-distance driven (`startDragDistance`), without a
timer-based long-press. The message menu on desktop is triggered by
secondary click (right-click), not a primary left-click tap.

| Cause                         | Text selection  | Message selection |
| ----------------------------- | --------------- | ----------------- |
| Tap dismiss text              | clear           | already empty     |
| Copy success                  | keep range      | already empty     |
| Enter text                    | move to subject | clear set         |
| Esc                           | clear if active | else clear set    |
| Press text in another message | new subject     | clear             |

**Accepted, deferred past foundation:** while dragging a text range **outside**
the subject bubble during a continuous hold, the interaction temporarily
promotes to **message drag selection** (`updateDragSelection`), visually
overlaying text selection. Moving the cursor back into the origin bubble during
the same hold restores text selection (`clearDragSelection`). Releasing outside
commits message selection (`applyDragSelection`), locking out further text
selection until message mode is dismissed. Omission from the foundation cut is
not a policy rejection.

## Inline hits (both strategies)

Link activation and code/pre click-to-copy (or host callbacks for those) are
first-class against idle-tap dismiss. Under mobile policy, **message
selection** or a live **character-range text selection** suppresses *all*
inline activations (links, inline code, fenced COPY chrome) so row toggles /
range ownership win. Under desktop/web policy, inline activation stays live
during **message selection** alone and during arm-for-entry; a live
character-range still suppresses inline activation. Idle link and code taps
still activate.

## Considered options

- **Android-only forever (ADR 010 as universal law)** — rejected: Desktop/web
  entry and Copy/dismiss contradict message-then-text and Copy-clears-mode.
- **Two unrelated controllers / hosts** — rejected: duplicates lifecycle and
  drifts glossary.
- **Pointer-kind policy switching** — rejected as default (surprising on
  phone + mouse); hosts may still override.
- **Cross-platform modes + host-overridable policy strategies** — accepted.
