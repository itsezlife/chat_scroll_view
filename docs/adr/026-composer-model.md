# ADR 026: Composer modes, state and extension seams

`chat_composer` is described by three orthogonal slots (header, panel,
actions) filled from a host-built `ComposerSpec`. Its controller owns input
only. Its text controller keeps entities in sync with edits and produces a
neutral rich-text value. It knows neither the panel nor any inset arbiter.

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — the input query is a `package:listen` `ValueListenable` ([ADR 023](023-data-layering-and-persistence.md) Amendment)  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 021](021-content-identity-and-collections.md), [ADR 027](027-foundation-theme-glass-motion.md), [ADR 028](028-panel-presentation.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Mode model | Three slots, not one growing enum. **Header** is what sits above the field (reply, edit, forward, link preview, suggestion) with a priority rule. **Panel** is what occupies the input row, chosen by a host-supplied resolver (default text panel; recording; recorded preview; restricted, join and unblock sibling panels). **Actions** is a data list of `ActionDescriptor` (id, semantic icon, placement leading or trailing, enabled and visible, `active` for the on state of a toggle, tap handler, and an optional `wrap` that builds a host widget around the rendered button so the host can add a hover region or a probe without the composer knowing it) for emoji toggle, attach, mic or send, scheduled, silent, bot menu and slow mode. The composer owns slots, layout and animation; the host owns what fills them. The sealed idle, editing and replying mode and the hard-coded buttons are deleted. |
| State owner | Declarative. The host builds `ComposerSpec(header, panel, actions, enabled, busy)` and passes it to the widget, which animates between specs. `ComposerController` owns input only: entity-aware text, focus, selection, input queries, field scroll and height, and the commands `insertContent`, `insertText`, `backspace` and `clear`. Reply and edit begin-commands, stored ids and preview strings stay with the host. |
| Text model | `ComposerTextController` (a `TextEditingController` subclass) keeps plain text and entity spans in sync with edits and renders inline content through the asset cache. It exposes the neutral rich-text value, plain text plus entities (offset, length, kind), used for drafts, send and edit-load. Entity kinds: inline content ref, bold, italic, code, strike, underline, spoiler, quote, link, mention. Formatting UI is the platform selection menu extended, not a toolbar widget. Entity edits commit on finished IME composition. |
| Rich-text home | `content_model`, next to the inline content ref. The root viewport does not depend on it; hosts map the value to their body model (markdown, per [ADR 017](017-body-linkify-host-invoked.md) and [ADR 029](029-host-integration.md)). |
| Suggestions | The composer exposes the active token as a `ValueListenable` (`package:listen`) input query (kind, text, replace range, caret anchor rect) and `replaceQuery(...)`. Query kinds are an open, host-registered set (trigger plus rule). The host builds mention, hashtag, command and inline-emoji panels. |
| Extent | The composer publishes its own height as data; the host feeds it, with presentation occupancy, into the viewport bottom padding ([host insets](../architecture/14-host-chrome-insets.md)). The composer imports no inset types. |
| IME | An input option `softKeyboard: auto or suppressed` plus focus commands. Hand-off choreography with the panel belongs to presentation ([ADR 028](028-panel-presentation.md)). The composer does not use `SystemChannels` to coordinate with the panel. |
| Units | Island shell (glass), header slot (reveal animation), field (entity input, height animation), action slots, panel resolver. The bottom fade stays with the composer. The emoji-face icon resolver is deleted: the host sets the action's semantic icon. |
| Panel link | The composer does not know the panel. The emoji toggle is an action whose icon the host derives from presentation visibility and the shell's selected page. |

## Why

- Telegram iOS splits an accessory panel (a resolver), alternative input panels (sibling nodes plus a resolver) and accessory items (a data list). Android uses `fieldPanelShown`, recording ints and priority bit-flags. Desktop uses separate member controls plus `ComposeFeatures`. Text is entity-bearing everywhere, and suggestions and mentions live outside the composer unit everywhere.
- The old `ChatEnterView` mixed row UI, IME policy, panel-open suppression keyed on icon state and custom render boxes. The header banner existed twice: as a widget and as a sealed mode.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Extending the sealed mode; per-mode strategy objects bundling header, panel and actions | Modes multiply; the slots vary independently |
| Plain controller with placeholder characters; host-owned text model | Entities would drift from the text; every host reimplements sync |
| Suggestion panels built into the composer; no query abstraction | Suggestion sources are host data |
| Controller-owned mode state with commands; a both-ways facade | Two owners for one state |
| The rich-text value in its own package or inside the composer package | `content_model` already holds the inline ref, and bodies need the value without the composer |

## Related

- Glossary: [Chat chrome](../chrome/CONTEXT.md), [Content and assets](../content/CONTEXT.md)
