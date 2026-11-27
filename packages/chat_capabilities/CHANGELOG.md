# Changelog

All notable changes to `chat_capabilities` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Changed (review)

- **Breaking:** `SlowMode` is sealed: `SlowMode.none` (`SlowMode$None`) or
  `SlowMode.active(interval:, nextSendAt:, pending:)` (`SlowMode$Active`,
  which has `copyWith`). A wait or a pending send without an interval can
  no longer be built. Code that wrote `SlowMode(interval: ...)` writes
  `SlowMode.active(interval: ...)`; code that read `slowMode.interval`
  switches on the two forms. The rules `slowModeIntervalNegative` and
  `slowModeWaitWithoutInterval` are replaced by
  `slowModeIntervalNotPositive` (an active slow mode of zero or less).
- **Breaking:** `DenialReason` has two package forms,
  `noWriteAccess(WriteAccess)` and `sendPending()`, in place of the
  `other('readOnly' | 'join' | 'requestToJoin' | 'slowModePending')` tags
  the composer raised. A host's `denialText` / `onDenied` that matched those
  tags matches the new forms; an exhaustive switch on `DenialReason` gains
  two cases.
- **Breaking:** `CapabilityFeedback.denialText(form:)` takes a `DenialForm`,
  an interface each package implements with its own closed enum, in place
  of a `String`.
- **Breaking:** `CapabilitiesOp` keeps only this package's operations
  (`valueChanged`, `invalidValue`, `denialTextMissing`, `feedbackFailed`,
  `denied`). `panelChosen`, `slowModeStarted` and `slowModeEnded` moved to
  `chat_composer`'s `ComposerOp`, `limitsDerived` and `pickerOneSend` to
  `attach_sheet`'s `AttachOp`; names and category are unchanged, so logs
  filter as before.
- `DenialReason.diagnosticForm` clips a host's `unlockable` kind or `other`
  tag so the form always fits an event field; `onDenied` runs the host's
  hook whatever the event does.
- `onDenied(repeated:)`: a consumer's repeat inside its window reports
  `denied` with `repeated: true` and skips the hook.
- `ChatProtection` holds its `ProtectionFlags` as its one source; the bools
  read from them. `ChatProtection.of(flags)`.
- `Capability.reason`, `WriteAccess.diagnosticForm`, `WriteAccess.denialReason`
  (a replacing panel's reason), `SendingCapabilities.reasonFor(action)` and
  `SendingCapabilities.map` (each plain right at once).
- `select(onValue:)`, the reporting hook a consumer that derives a value
  (the picker's limits) uses instead of its own lazy listenable.
- The trace section `chat_scroll_view.capabilities.select` under
  `--dart-define=chat_scroll_view.trace=phase`.

### Added

- The package ([ADR 049](../../docs/adr/049-chat-capabilities.md)):
  `ChatCapabilities` with the groups `sending`, `writeAccess`, `slowMode`,
  `protection`, `limits` and `custom`, each defaulting to allowing
  everything, so `const ChatCapabilities()` is the value a consumer assumes
  without a signal. `Capability` (`allowed`, `denied`) and `DenialReason`
  (`everyone`, `restricted`, `unlockable`, `other`); `WriteAccess` forms;
  `SlowMode` with `canSendAt` / `remainingAt` over the caller's clock;
  default limits of 4096 / 1024 code points, no file size limit and 10
  items per album.
- `select`, a per-group `ValueListenable` that notifies only when its group
  changes and holds its subscription only while listened to.
- `withDiagnostics(chatId:)`, which reports `capabilities` events
  (`CapabilitiesOp.valueChanged`, `CapabilitiesOp.invalidValue`) for each
  distinct value; `brokenRules` and `debugDescribe()` on the value.
- `testing.dart`: `FakeChatCapabilitiesSource`.
- The bit flag sets `MediaKindSet` (over `MediaKind`) and `ProtectionFlags`,
  with `bits` / `fromBits` as their serialised form. `sending.media`
  (`SendableMedia`: `allowed` kinds, `denials`, `reasonFor`), all kinds
  allowed by default, so existing values are unchanged.
  `ChatProtection.flags` and `forMessage(messageProtected:)`. The rule
  `mediaDenialForAllowedKind`; `debugDescribe()` and `valueChanged`
  (`protectionBits`) carry the new bits.
- Denial feedback: `CapabilityAction` (stable names and order) with
  `forMediaKind`, and `CapabilityFeedback`, the host's `denialText` and
  `onDenied` hooks behind guarded methods. `CapabilityFeedback.none` has no
  hooks, so a host without feedback keeps today's behaviour. The events
  `denialTextMissing` and `feedbackFailed`; `DenialReason.diagnosticForm`.
  `testing.dart`: `RecordingCapabilityFeedback`.
- `onDenied` takes the reporting `CapabilityConsumer` (required) and, for a
  send during slow mode, the `remaining` wait, and reports the `denied`
  event (`CapabilitiesOp.denied`) for every attempt, `CapabilityFeedback.none`
  included. Consumers no longer emit it themselves.
