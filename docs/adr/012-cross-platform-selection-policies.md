# ADR 012: Cross-platform selection policies

**Status**: Accepted  
**Date**: 2026-09-12  
**Updated**: 2026-09-12 (engine-owned mobile routing; membership/retarget as
this policy; inline hits; deferred desktop drag-out promotion); 2026-10-18
(desktop: every body stays live while text is active; the range suppresses
inline activation only in its own message); 2026-10-18 (every text body is
under the policy, the emoji-only text layout included); 2026-10-19 (status
chrome: the desktop click on an emoji-only message's time selects it, as the
reference does)  
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
messages.

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
message membership are **mutually exclusive**.
Pressing a body arms it as the **text selection subject** on pointer-down, so
text is active almost permanently: every other body therefore keeps its
selection surface while text is active (text cursor, inline hits, the scope's
mouse recognizers). A surface only on the subject would leave every other
message dead until the subject was dismissed (a click elsewhere or Esc), which
is the stuck-pointer defect this clause closes. Settled **message selection**
does not allow starting character-range text selection;
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

## Every text body is under the policy

The strategies above apply to every body that registers a text model, not to
the markdown body alone: the text layout of an emoji-only message
([ADR 036](036-emoji-only-message-presentation.md)) enters, nests, retargets and
dismisses by the same rules (mobile message-then-text with one emoji selected
by a long press, as Android's emoji span rule; desktop direct press and drag),
and the desktop stuck-pointer clause covers it: pressing it arms it and leaves
every other body live. A body that is not text (the single-emoji sticker) never
enters text selection under either strategy. Desktop and iOS Telegram do not
select their large emoji; the viewport does, as the product asks, and
`ChatEmojiBody(selectableText: false)` restores their rule.

## Status chrome (tap barrier)

A mouse click on a message's status chrome (the time and delivery state, which
desktop shows on hover for some bodies) is not a message tap. The host wraps
the chrome in `ChatMessageTapBarrier`; the selection pointer then treats a
primary press that starts on it as no press on the message: no toggle, no span
or drag-select, no text-selection arming, no idle tap, no inline hit under it (a
pill over a sticker's corner is not the sticker).

Left unchanged on purpose: a **secondary** click still reaches
`onSecondaryMessageTap` (the context menu is the message's wherever it opens),
a tap still dismisses live **text selection**, and **touch is never barred**
(Android routes a time tap in message selection to the row like any other tap).

**What the reference does, and what this repository does.** The barrier is the
mechanism; what a click on the status then does is the host's, and the two
hosts in this repository answer differently on purpose.

| Question | Reference | Here |
| -------- | --------- | ---- |
| Click on the date / time, nothing selected | Selects the message (`ListWidget::mouseActionFinish`: `simpleSelectionChange && _mouseCursorState == CursorState::Date && !hasSelectRestriction()` -> `SelectAction::Select`, after `clearTextSelection()`; `history_view_list_widget.cpp:4946-4961`) | Emoji-only message: selects it. Ordinary bubble: nothing |
| Click on the date in message selection | Toggles it like any click (`needItemSelectionToggle` -> `SelectAction::Invert`, `:4911-4944`) | Emoji-only message: toggles it. Ordinary bubble: nothing |
| Drag that starts on the date | A forward drag, not a text selection (`requiredToStartDragging`, `:1905`; `Date` -> `itemOrItsGroup`, `:5372`) | Nothing starts: no drag-select, no text arming (the barrier). The forward drag is not implemented |
| Right click | The message's context menu | The same: `onSecondaryMessageTap` |
| Where `Date` is hit | `BottomInfo::textState`, the time, ticks and views of the info block (`history_view_bottom_info.cpp:213`) | The whole pill |
| Touch (Android) | Time tap acts only for an imported forward (`ChatMessageCell.checkDateMotionEvent`, `delegate.didPressTime` -> `ChatActivity` undo hint); in action mode any tap on the row, time included, selects it | A touch is never barred: in message selection it toggles the row, otherwise it is the idle tap |

The select-on-click is a **desktop-policy** behaviour: the example's emoji-only
pill answers a mouse or trackpad click with `ChatSelectionController.toggle`
(it selects, unselects, clears a live text selection and respects the cap and
`isSelectable`) and only when the selection policy does not route a primary tap
to the idle message. The click handler is a detector **inside** the barrier,
limited to mouse and trackpad: the barrier keeps the press from the viewport's
tap, so without the handler a click on the pill does nothing, and a touch must
not reach it so that the viewport's own tap keeps the mobile behaviour. A
secondary click is not that detector's, so the menu still opens.

**Ordinary bubbles stay as they were**: their time is inside the barrier and a
click on it does nothing, although the reference selects there too. The
inconsistency is recorded, not resolved: a host that wants the reference's
behaviour for bubbles gives the bubble's time the same detector.

**Hover is the row's, not the box's.** The reference shows an emoji-only
message's time while the pointer is anywhere on the message's row:
`ListWidget::mouseActionUpdate` clamps `x` to the list and finds the element by
`y` alone (`:5020-5065`), and `UnwrappedMedia::needInfoDisplay` shows the info
while `_parent->isUnderCursor()` (`history_view_media_unwrapped.cpp:727-732`). The
host's hover region is therefore the viewport's cell of the row (the example's
`EmojiRowHover`, outside the row's padding and alignment), not the emoji box.

## Copy by keyboard (both strategies)

The platform copy shortcut (`CopySelectionTextIntent`) copies what is selected,
under either policy:

- A **text selection** is copied by the viewport through the same path as the
  selection's Copy (`copyTextSelection`: `copyWriter`, the policy's Copy
  effects, `ChatCopied`). The markdown scope answers the intent itself with a
  plain-text write, nearer to the focus than any facade action, so each body
  binds the copy key to an intent of the facade's own.
- A **message selection** is copied by the host (ADR 032), which binds the
  intent above the viewport and the composer. The viewport keeps the focus on
  a live message selection (`ChatKeyboardShortcuts`), re-asking after the
  frame because a host may release its composer's focus after the wrapper's
  listener ran.
- A focused composer with a selection answers first; with none, its copy is
  disabled and the intent goes on to the host.

The format of a copy of several messages is the host's, per policy: `$Desktop`
writes `[time] Name: text` lines a newline apart for several and the text alone
for one (Telegram Desktop, `HistorySelectedItemsText`); `$Mobile` writes
messages a blank line apart with a `Name:` line where the sender changes
(Telegram Android, `ChatActivity` copy and `getMessageContent`). Telegram iOS
has no Copy for a selection of several messages.

## Inline hits (both strategies)

Link activation and code/pre click-to-copy (or host callbacks for those) are
first-class against idle-tap dismiss. Under mobile policy, **message
selection** or a live **character-range text selection** suppresses *all*
inline activations (links, inline code, fenced COPY chrome) so row toggles /
range ownership win. Under desktop/web policy, inline activation stays live
during **message selection** alone and during arm-for-entry; a live
character-range suppresses inline activation only inside its own message (the
**text selection subject**). A link or code chrome in another message
activates, and dismisses the range as any click away from it does. Idle link and code taps
still activate.

## Considered options

- **Android-only forever (ADR 010 as universal law)** — rejected: Desktop/web
  entry and Copy/dismiss contradict message-then-text and Copy-clears-mode.
- **Two unrelated controllers / hosts** — rejected: duplicates lifecycle and
  drifts glossary.
- **Pointer-kind policy switching** — rejected as default (surprising on
  phone + mouse); hosts may still override.
- **Cross-platform modes + host-overridable policy strategies** — accepted.
