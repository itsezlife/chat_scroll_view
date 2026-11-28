# Changelog

All notable changes to `chat_outbox` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- The package ([ADR 048](../../docs/adr/048-outgoing-messages.md)), on
  `content_model` and `chat_capabilities`.
- `OutgoingMessage` and `OutgoingItem`; `OutgoingStatus` (`preparing`,
  `uploading`, `publishing`, `sent`, `failed`, `cancelled`) and the closed
  `OutgoingFailure` reasons, equal by value, with stable `name`s.
- `OutgoingPayloadCodec<M>`, the host's model to payload bytes, a
  `dart:convert` `Codec`.
- `ChatOutbox` with `byClientMessageId` and the one-shot `isFreshOutgoing`,
  which report `echoMatched` and `freshOutgoingTaken` (`OutboxOp`).
- `debugSnapshot(chatId)`: `OutboxDebugSnapshot` with every section
  declared (strategy, tip, tail rows with their items, publisher, send in
  flight, counters) and a JSON-encodable `toMap()`. Sections the outbox does
  not know yet are null.
- `testing.dart`, the home of the package's fakes (none yet).
