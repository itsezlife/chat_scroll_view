# Universal field gestures in extended_text

Selection enter/dismiss is owned once by `extended_text` and applies to every
`ExtendedTextField` consumer. The enter matrix is long-press → one-touch,
double-tap enter → immediate finish (no one-touch), no triple-tap paragraph,
idle caret tap vs tap dismiss. Unnamed edges follow ordinary editable-field
defaults; universal enter/dismiss wins on conflict. We rejected keeping Flutter’s
platform-forked stock matrix and rejected a rich-editor-only gesture path so
plain fields and markdown share one stable model.

## Status

accepted

**Superseded in part by** [0002-touch-scoped-universal-gestures.md](0002-touch-scoped-universal-gestures.md)
(platform scope: universal matrix on touch only; desktop keeps stock long-press
and triple-tap). Option C for touch consumers remains accepted.

## Considered options

- **A — Plain editable-field stack only**: ship stock (or near-stock) platform
  enter gestures everywhere. Rejected: too fragile and inconsistent with the
  enter/dismiss behavior we want to stabilize.
- **B — Rich-editor-only gestures**: keep a special matrix for markdown / rich
  hosts. Rejected: splits the product and reintroduces per-screen forks.
- **C — Universal field gestures (chosen)**: bake the rich-style enter/dismiss
  matrix into `extended_text` for all consumers; defer remaining edges to
  editable-field defaults.
