# ADR 049: Chat capabilities

What the user may do in a chat is one immutable value, **chat
capabilities**, in a new pure-Dart package `chat_capabilities`. The host
resolves its backend's rights and hands each chat package a live value of
outcomes and reasons, never protocol flags. Each package reads only its own
group, draws the denied form of its own controls per platform, takes every
text from the host and tells the host when the user tries a denied action.
A host that provides nothing gets everything allowed, so today's behaviour
holds.

**Status**: Accepted (2026-11-26, maintainer; decided in the
message-media-transfers map, ticket 20, revised by ticket 24 and the
acceptance pass; refined at issue slicing: the feedback type, the copy hook, the album limit and panel page availability)  
**Date**: 2026-11-26  
**Relates to**: [ADR 012](012-cross-platform-selection-policies.md) (policy shape),
[ADR 020](020-package-topology.md) (amended: `chat_capabilities`),
[ADR 023](023-data-layering-and-persistence.md) (`package:listen`),
[ADR 026](026-composer-model.md) (composer panels and limits),
[ADR 034](034-rich-text-wire-and-persistence.md) (the message length budget),
[ADR 045](045-bulletins.md) (feedback is the host's),
[ADR 046](046-media-picker.md) (attach limits),
[ADR 047](047-message-media.md) (link preview availability),
ADR 048 (outgoing messages; server denials),
[ADR 050](050-diagnostics-events.md) (diagnostics events)

Spec: `.scratch/chat-capabilities/spec.md`, with the per-platform inventory
in `.scratch/message-media-transfers/research/` (research 19).

## Context

Each chat package took its own constant for what is allowed: the picker an
`AttachLimits` per open, the composer a message length and a host-built
"restricted" panel, the large-emoji gate a sticker flag. Nothing modelled
content protection, slow mode or read-only chats, and nothing told the host
why an action was refused. The reference clients resolve one wire model the
same way on every platform (creator, admin, personal ban with an until date,
default ban, a bypass the user can earn) and pick the feedback text from the
reason. Their denied forms differ per platform: an input row replaced by a
bar, a locked field, a picker tab showing the ban text or a toast, a dimmed
button with a tooltip, a link preview that silently does not appear.

## Decided

### Package

| Area | Decision |
| ---- | -------- |
| Home | `chat_capabilities`, pure Dart, depending on `listen` and, for its diagnostics only, `content_model` ([ADR 050](050-diagnostics-events.md); ADR 020 rule 9 as amended). Every chat package may depend on it. |
| Passing | The host passes a `ValueListenable<ChatCapabilities>` explicitly to the controllers and sessions that need it (composer controller, picker session, the message media policy, the outbox), together with a `CapabilityFeedback` (below). There is no scope widget. `chat_capabilities` ships `capabilities.select((c) => c.sending)`, a `ValueListenable` of one group that notifies only when that group changes by `==`, built on `listen`'s `ChangeNotifier`. |
| Default | No value means everything allowed with the default limits: message 4096 code points ([ADR 034](034-rich-text-wire-and-persistence.md)), caption 1024 code points, file size unlimited, album 10. Every length counts code points; the attach limits' caption length, which counts UTF-16 units today, is aligned to it. |
| Resolution | The host's. The value carries outcomes and reasons. |
| Diagnostics | `chat_capabilities` emits its own `capabilities` events (value changes, invalid values, denials and feedback calls) through `ChatDiagnostics.current` ([ADR 050](050-diagnostics-events.md)); `capabilities.debugDescribe()` describes the value without user content. |

### Shape

| Area | Decision |
| ---- | -------- |
| Capability | `allowed` or `denied(reason)`. |
| Denial reason | Sealed: `everyone`, `restricted(until?)` (null until is forever), `unlockable(kind)` (an opaque host string for a restriction the user can lift), `other(tag)`. Amended (review, 2026-11-27): two package forms, `noWriteAccess(access)` (a default write-access panel's text) and `sendPending()` (slow mode holding a send behind a message still sending), so a package never mints `other` tags in the host's tag space. |
| Groups now | `sending` (`text`, `stickers`, `linkPreviews`, `polls`, `inline` as plain capabilities; `media` as a payload-free `MediaKindSet allowed` over photo, video, animation, file, audio, voice and round video, plus `Map<MediaKind, DenialReason> denials`, which `reasonFor(kind)` reads), `writeAccess` (`canWrite` or a replacement: `readOnly`, `join`, `requestToJoin`, `restricted(reason)`, `custom(tag)`), `slowMode` (sealed: `none`, or `active` with interval, next send time, pending), `protection` (copy, forward, save, capture blocked for the chat; the value knows no messages, so `protection.forMessage(messageProtected: bool)` returns the `ProtectionFlags` for one message, the caller passing the message's own flag from its model), `limits` (message length, caption length, file size, album size). GIFs are their own `animation` right; a host may tie it to stickers. |
| Later groups | Reactions, commands, paid messages, admin and others arrive as fields that default to allowed or none, so hosts keep compiling. `custom` maps host keys to capabilities for rules the packages do not model. |
| Bit flags | Only for flag sets with no payload: `MediaKindSet` and `ProtectionFlags`. A private constructor and named constants, at most 31 flags per type (safe as a web integer), a stable bit order that is the serialised form, and a removed flag's bit never reused. Rights with reasons, slow mode and limits are sealed classes or values. |

### Derived types

| Type | Decision |
| ---- | -------- |
| Attach limits | `attach_sheet` takes the `ValueListenable<ChatCapabilities>` and builds `AttachLimits` with a function of its own. `attach_model` stays on `content_model` only ([ADR 046](046-media-picker.md) rule 1). `AttachLimits` gains `albumSize`; the send plan groups at the smaller of its policy's group size and that limit. |
| Message length | The composer's message length limit comes from `limits`. |
| Input row | `chat_composer` picks the panel from `writeAccess` and ships a default panel per kind, showing the host's `denialText` and an optional host action. The host may replace any panel's builder through the existing `ComposerPanelId` resolver; the `ComposerPanelId` documentation is updated to say so. |

The existing constructors stay, so a host without capabilities changes
nothing.

### Denied forms and feedback

| Area | Decision |
| ---- | -------- |
| Forms | Each package draws its control's denied form, with a per-platform default (spec §8): the input row replaced by a bar, a disabled field, a picker page or a toast with the ban text, a dimmed button with a tooltip, a link preview silently absent. |
| Panel pages | The panel's page registry (`panel_shell`) gains a page availability, set by the host (from `sending.stickers` and `sending.animation`, with text from `denialText`); `panel_shell` takes no capabilities edge. Forms with per-platform defaults: `dimmed(hint)` (the tab dimmed, the panel moves to emoji, a tap on the tab shows the hint as a tooltip for 3.5 s), `hidden` (the tab removed, emoji only), `replaced(text)` (the page's content replaced by the text). |
| Feedback type | `CapabilityFeedback` in `chat_capabilities` carries both hooks below; each controller and session takes it with the capabilities listenable. Without one, texts are null and attempts are not reported. |
| Text | From the host: `denialText(action, reason)` for text drawn in place, null for the silent form. A package passes its own `DenialForm` (a closed enum implementing the interface in `chat_capabilities`) so the `denialTextMissing` event names where it drew the silent form. |
| Attempts | `onDenied(action, reason)` (a package also passes its `CapabilityConsumer`: `composer`, `picker`, `panel`, `selection` or `outbox`, and for a slow-mode send the wait left; the seam logs every attempt as `denied`, a repeat inside the package's window with `repeated: true` and without calling the hook) when the user tries a denied action: a tap on a dimmed control, a send during slow mode, a server refusal. `action` is a `CapabilityAction`: `sendText`, `sendPhoto`, `sendVideo`, `sendAnimation`, `sendFile`, `sendAudio`, `sendVoice`, `sendRoundVideo`, `sendSticker`, `sendLinkPreview`, `sendPoll`, `sendInline`, `sendNow` (slow mode), `copy`, `forward`, `save`. Capture blocking is a flag, not an action. The host shows the tooltip, toast or bulletin. |
| Semantics, RTL | A dimmed control stays focusable, labelled as not available, with the `denialText` as its hint. The slow-mode countdown is announced politely when it starts and ends, not every second. Restriction bars are plain text. Denied forms mirror with the layout. |
| Readers | `message_media` reads only protection, per message, through an `allowedItemActions` helper; the host and the viewer build per-item menu entries, share and save from it. |

### Live changes

| Change | Decision |
| ------ | -------- |
| Protection on | Copy, forward and save leave menus and the viewer. The root package's selection facade gains a capability-agnostic `canCopy(messageId) → bool` hook that gates text-selection copy; the host wires it from `protection.forMessage`, so the root takes no capabilities edge. On desktop a selection holding a protected message is cleared; on mobile it stays and loses the entries. Capture blocking reaches the host, which sets the platform's secure flag. |
| Slow mode | A countdown on the send button (Android, desktop) or in the empty field's placeholder (iOS); the picker sends one unit (an album is one); an early send is refused through `onDenied`. |
| Server denial | `onDenied` fires and the outgoing message follows a per-platform policy (ADR 048): on mobile it becomes failed with a denied reason, with Retry and Delete (iOS adds Retry All); on desktop denied media becomes failed with Delete only, and a denied text message is removed with its text restored to an empty composer. The host's `denialText` is shown, never the server's code. |

A kind that becomes denied while items are picked is checked on the
client on every platform: the send is refused through `onDenied` before any
job exists, the picker stays open with the selection and caption kept and
the denied items marked (decided with the maintainer 2026-11-27, after
checking the reference clients, which either send and fail or drop the
selection).

## Amendment (2026-11-27, accepted): names that landed

- The feedback seam is `CapabilityFeedback` (`denialText`, `onDenied`),
  with `CapabilityConsumer` and `DenialForm` beside it; the hooks the host
  gives keep the shapes above, the methods packages call take the extra
  arguments named in the Attempts and Text rows.
- The input row's default panels have ids `readOnly`, `join`,
  `requestToJoin`, `restricted` and `writeAccessCustom`
  (`ComposerPanelId.forWriteAccess`); the resolver is asked first, so a
  host replaces any of them.
- The copy hook is `ChatSelectionController.canCopy`
  (`bool Function(int messageId)`), with `reapplyCanCopy()` and
  `refusesCopy(ids)`; a refusal is reported as `ChatCopyRefused` and the
  facade leaves the selection to the host.
- Page availability is `PageAvailability` in `panel_shell`
  (`available`, `dimmed(hint)`, `hidden`, `replaced(text)`).
- The attach limits are derived by `attach_sheet` from the capabilities
  (`AttachCapabilities`); the picker refuses a send of a denied kind
  through `onDenied` before any job exists.

## Why

- Every send path, menu and picker asks the same questions, and the
  feedback depends on why; one value with reasons answers both.
- Outcomes keep packages free of any backend's protocol; resolution order
  and bypass rules are the host's business.
- Rights are a different context from content identity, so they do not
  belong in `content_model`; a package on `listen` and the shared leaf
  (for diagnostics only) lets every chat package depend on it without
  pulling anything else.
- Passing the value explicitly to controllers makes the dependency visible
  and testable; a per-group selection keeps a slow-mode tick from
  rebuilding the picker's kind gate.
- Bit flags fit sets with no payload and match the engine's existing status
  idiom; reasons need real values.
- Packages know what their controls look like denied; hosts know their
  language and their feedback surfaces.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Capabilities in `content_model` | Chat rights are not content identity |
| A scope widget above the chat | The consumers are controllers and sessions, which take their inputs as arguments; the maintainer chose explicit passing |
| Protocol flags in the value | Ties portable packages to one backend's wire model |
| Booleans without reasons | The host cannot choose the feedback text |
| `ChatAction` as the action enum's name | Reads as a typing status |
| A message-aware protection check on the value | The chat value would have to track messages; the caller already holds the message's flag |
| A `fromCapabilities` constructor on `AttachLimits` | Breaks [ADR 046](046-media-picker.md) rule 1: `attach_model` depends on `content_model` only |
| Bit flags for every right | Reasons and until dates are payloads |
| Replacing `AttachLimits`, the length limit and panel ids | Breaks hosts; deriving them keeps both paths |
| Packages showing their own denial toasts | Feedback UI is the host's |

## Consequences

- `chat_capabilities` joins the root `workspace:` list; ADR 020 gains its row
  (amendment). `chat_composer`, `attach_sheet`, `message_media` and
  `chat_outbox` depend on it; `attach_model` does not.
- `chat_composer` gains a default panel per `writeAccess` replacement.
- The root package's selection facade gains `canCopy(messageId)`; `panel_shell` gains page availability; `attach_model`'s `AttachLimits` gains `albumSize`. None of them depends on `chat_capabilities`.
- A new Chat Capabilities glossary and a context map row.
