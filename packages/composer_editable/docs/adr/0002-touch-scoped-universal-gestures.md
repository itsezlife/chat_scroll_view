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

## Amendment: iOS keeps two stock paths

The touch matrix drops two behaviors an iOS text view has, and they are kept:
a long-press on a **focused, editable** field moves the caret with the
floating cursor (an unfocused or read-only field takes the word path), and a
finger tap on the **collapsed caret** of a focused, editable field toggles the
toolbar so the Paste menu is reachable. Every other iOS tap and long-press
follows the touch matrix. The default context menu on iOS is the system menu
where the platform supports it.
