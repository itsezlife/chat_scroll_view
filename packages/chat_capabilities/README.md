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
| `DenialReason` | `everyone`, `restricted(until:)` (null until is for good), `unlockable(kind)` (an opaque host string for what lifts it), `other(tag)`. |
| `SendingCapabilities` | `text`, `stickers`, `linkPreviews`, `polls`, `inline`. |
| `WriteAccess` | `canWrite`, or what replaces the input row: `readOnly`, `join`, `requestToJoin`, `restricted(reason)`, `custom(tag)`. |
| `SlowMode` | `interval`, `nextSendAt`, `pending`; `SlowMode.none` by default. `canSendAt(now)` and `remainingAt(now)` take the caller's clock. |
| `ChatProtection` | Chat-level `copy`, `forward`, `save` (allowed by default) and `captureBlocked`. |
| `ChatLimits` | `messageLength` 4096 and `captionLength` 1024 code points, `fileSize` unlimited (null), `albumSize` 10. |
| `custom` | Host rules the packages do not model, by host key. |

Every group has `copyWith`, and so does `ChatCapabilities`.

## Reading the value

The host passes a `ValueListenable<ChatCapabilities>` to each controller or
session that needs it, and each reads only its group:

```dart
final chat = hostCapabilities.withDiagnostics(chatId: chatId);
final sending = chat.select((c) => c.sending);
```

`select` notifies only when its group changes by `==`, subscribes on its
first listener and unsubscribes after its last, so it needs no disposal.
`withDiagnostics` passes the value through and reports it (below).

## Diagnostics

`capabilities` events through `ChatDiagnostics.current`, operations in
`CapabilitiesOp`, all correlated by the chat id given to `withDiagnostics`:

| Op | Level | Fields |
| --- | --- | --- |
| `valueChanged` | debug | `groups` (the changed group names), `writeAccess` (its form), `slowModeActive`, `protected` (what protection denies, or `none`) |
| `invalidValue` | warning | `rule`, one event per broken `CapabilitiesRule`; debug builds then assert |

## Testing

`testing.dart`: `FakeChatCapabilitiesSource`, a settable source (`set`,
`update` per group) that notifies on every set and reports whether it is
listened to.
