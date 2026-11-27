# chat_capabilities

The **chat capabilities** of one chat: what the user may do there, as an
outcome per action (a **capability**) and, when denied, a **denial reason**.
The host resolves its backend's rights into this value; the chat packages
only read it. Pure Dart: it depends on `listen`, `meta` and, for its
diagnostics events only, `content_model`.

Decisions: [ADR 049](../../docs/adr/049-chat-capabilities.md). Glossary:
[Chat Capabilities](../../docs/capabilities/CONTEXT.md).

## Types

| Type | Role |
| --- | --- |
| `ChatCapabilities` | One immutable, value-equal value per chat, one field per group. `const ChatCapabilities()` allows everything with the default limits, which is what a consumer assumes without a value. `brokenRules` names the rules a value breaks; `debugDescribe()` describes it without user content. |
| `Capability` | `allowed` or `denied(reason)`; `isAllowed`. Carries no text. |
| `DenialReason` | `everyone`, `restricted(until:)` (null until is for good), `unlockable(kind)` (an opaque host string for what lifts it), `other(tag)`; `diagnosticForm` names the form for events. |
| `SendingCapabilities` | `text`, `media`, `stickers`, `linkPreviews`, `polls`, `inline`. |
| `SendableMedia` | `sending.media`: the `allowed` kinds (a `MediaKindSet`, every kind by default) and `denials`, a reason per kind outside `allowed`; `reasonFor(kind)` is null for an allowed kind and `everyone` for a denied kind without an entry. |
| `MediaKind`, `MediaKindSet` | The kinds `photo`, `video`, `animation`, `file`, `audio`, `voice`, `roundVideo`, and a bit flag set of them (`none`, `all`, `of`, `\|`, `&`, `without`, `contains`, `kinds`). |
| `WriteAccess` | `canWrite`, or what replaces the input row: `readOnly`, `join`, `requestToJoin`, `restricted(reason)`, `custom(tag)`. |
| `SlowMode` | Sealed: `SlowMode.none` (the default) or `SlowMode.active(interval:, nextSendAt:, pending:)`. `canSendAt(now)` and `remainingAt(now)` take the caller's clock. |
| `ChatProtection` | Chat-level `copy`, `forward`, `save` (allowed by default) and `captureBlocked`, read from its `flags` (the one source; `ChatProtection.of(flags)`), and `forMessage(messageProtected:)`, which adds a protected message's copy, forward and save to the chat's flags. |
| `ProtectionFlags` | A bit flag set of restrictions: `copy`, `forward`, `save`, `captureBlocked`. |
| `ChatLimits` | `messageLength` 4096 and `captionLength` 1024 code points, `fileSize` unlimited (null), `albumSize` 10. |
| `custom` | Host rules the packages do not model, by host key. |

Every group has `copyWith`, and so does `ChatCapabilities`.

The two flag sets have a private representation and a stable bit order,
which is their serialised form: `bits` writes it, `fromBits` reads it and
drops bits it does not know. A removed flag's bit is never reused, and a set
holds at most 31 flags, so it stays a small integer on the web.

## Reading the value

The host passes a `ValueListenable<ChatCapabilities>` to each controller or
session that needs it, and each reads only its group:

```dart
final chat = hostCapabilities.withDiagnostics(chatId: chatId);
final sending = chat.select((c) => c.sending);
```

`select` notifies only when its group changes by `==`, subscribes on its
first listener and unsubscribes after its last, so it needs no disposal. A
consumer that derives a value and reports it (the picker's limits) passes
`onValue`, called with each distinct group before the listeners hear of it.
`withDiagnostics` passes the value through and reports it (below).

## Denial feedback

The host passes one `CapabilityFeedback` beside the listenable. It holds the
host's two hooks, and packages call them through its methods:

| Method | When | Returns |
| --- | --- | --- |
| `denialText(action, reason)` | a package draws a denied control with text in place | the host's text, or null for the package's silent form |
| `onDenied(action, reason, consumer:)` | the user attempts a denied action | nothing; the host shows the feedback |

`action` is a `CapabilityAction`, whose names and order are stable;
`CapabilityAction.forMediaKind` maps a `MediaKind` to its send action.
`CapabilityFeedback.none` (the const default) has no hooks, so texts are
null and attempts go unreported. A throwing hook is swallowed and reported.

```dart
final feedback = CapabilityFeedback(
  denialText: (action, reason) => strings.denied(action, reason),
  onDenied: (action, reason) => bulletins.show(action, reason),
);
```

A package passes its `CapabilityConsumer` (`composer`, `picker`, `panel`,
`selection`, `outbox`) to `onDenied`, a send during slow mode its
`remaining` wait, and a repeat inside its window `repeated: true` (logged,
the hook skipped); the hook itself sees only the action and the reason. A
package names where it draws a text with its own `DenialForm` enum.

`DenialReason` has the host's forms (`everyone`, `restricted`, `unlockable`,
`other`) and two the packages raise: `noWriteAccess(access)` for a panel
that replaces the input row, and `sendPending()` for slow mode holding a
send behind a message still sending.

## Diagnostics

`capabilities` events through `ChatDiagnostics.current`, operations in
`CapabilitiesOp`, all correlated by the chat id given to `withDiagnostics`.
A consumer's own `capabilities` events are in its package's enum
(`chat_composer`'s `ComposerOp`, `attach_sheet`'s `AttachOp`).

| Op | Level | Fields |
| --- | --- | --- |
| `valueChanged` | debug | `groups` (the changed group names), `writeAccess` (its form), `slowModeActive`, `protected` (what protection denies, or `none`), `protectionBits` |
| `invalidValue` | warning | `rule`, one event per broken `CapabilitiesRule`; debug builds then assert |
| `denialTextMissing` | debug | `action`, `reason` (its form), `form` (the silent form the package draws, when it names one) |
| `denied` | info | `action`, `reason` (its form), `consumer`, `remainingMs` (when given), `repeated` (a repeat inside the consumer's window); reported by `onDenied` for every attempt, with or without a host hook |
| `feedbackFailed` | error | `hook` (`denialText` or `onDenied`), `action`, `errorType`; the event carries the error and stack trace |

The feedback events are correlated by the `correlation` the calling package
passes (the chat id, and the message's when known). A host string in a
reason form (an `unlockable` kind, an `other` tag) is clipped to fit a
field.

The timeline section `chat_scroll_view.capabilities.select` (a group
recomputed and compared) is compiled in with
`--dart-define=chat_scroll_view.trace=phase`.

## Testing

`testing.dart`: `FakeChatCapabilitiesSource`, a settable source (`set`,
`update` per group) that notifies on every set and reports whether it is
listened to. `RecordingCapabilityFeedback` records every `onDenied` call
(`denials`, oldest first) and answers `denialText` from its `texts` table by
action; it goes through the real seam, so its events are the real ones.
