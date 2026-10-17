# Touch-scoped universal gestures; desktop keeps stock

ADR-0001 baked a single enter/dismiss matrix into every `ExtendedTextField`
consumer. Desktop/web UX is pointer- and keyboard-driven and differs sharply
from touch, so forcing one-touch long-press and “no triple-tap paragraph” onto
`linux` / `macOS` / `windows` was overreach. We keep the universal matrix on
**touch platforms** (`android`, `iOS`, `fuchsia`) and restore **stock Flutter**
long-press and triple-tap on **desktop platforms**. Double-tap may continue to
share a common `selectWord` path (near stock on desktop).

## Status

accepted

supersedes [0001-universal-field-gestures.md](0001-universal-field-gestures.md)
for platform scope (touch vs desktop). ADR-0001’s choice of a shared touch
enter matrix (option C) remains in force for touch consumers.

## Considered options

- **Keep ADR-0001 literally everywhere** — rejected: harms desktop/web UX.
- **Split by pointer kind (mouse vs touch)** — deferred: more complex; platform
  split matches Flutter’s existing editable forks and is enough for now.
- **Touch universal + desktop stock (chosen)** — restore stock long-press and
  triple-tap on desktop; leave touch enter/dismiss as in ADR-0001.
