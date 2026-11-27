# Changelog

All notable changes to `chat_capabilities` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added (limitsDerived)

- `CapabilitiesOp.limitsDerived`, emitted by the picker package when it derives
  its limits.

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
