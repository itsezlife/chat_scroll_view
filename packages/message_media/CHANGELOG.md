# Changelog

All notable changes to `message_media` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- The package ([ADR 047](../../docs/adr/047-message-media.md)) with the
  default media layout's geometry: `computeSingleMediaSize`,
  `GroupedMessages.calculate` with `GroupedMediaMember`,
  `GroupedMessagePosition` and `GroupedPositionFlags`, `MosaicLayout` with
  `MosaicCellLayout`, and `MediaLayoutMetrics`.
- Cells are addressed by `MediaItemId`: a member carries its item's `id`,
  `GroupedMessages.positionOf(id)` and `MosaicLayout.cellOf(id)` find a
  cell, and the caption owner is `captionItemId`. Kinds are
  `content_model`'s `MediaItemKind`; only photo, video and animation are
  boxes.
