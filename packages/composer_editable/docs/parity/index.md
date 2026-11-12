# Composer text selection

Contract for **`ExtendedTextField`**, the editable behind the chat composer.
Message-bubble selection is out of scope: it lives in the chat viewport's text
selection.

## Glossary (canonical)

Ubiquitous language: [CONTEXT.md](../../CONTEXT.md). Do not fork terms in
hosts.

## Concepts

| Topic | File | One-line |
| ----- | ---- | -------- |
| Selection stacks | [architecture.md](architecture.md) | Composer vs bubble; what the composer owns |
| Handles | [handles.md](handles.md) | Appear, drag scale, finger-tracked overlay, frozen chrome, settle |
| Magnifier | [magnifier.md](magnifier.md) | Pointer-line focal, ~100ms smooth, hide-under-loupe |
| Gestures | [gestures.md](gestures.md) | Universal enter/dismiss, direction settling, invert model |
| Highlight | [highlight.md](highlight.md) | Stock boxes, one gapless shape; handle and toolbar visibility notifiers |
| Status | [flutter-parity.md](flutter-parity.md) | Done / not implemented / dropped in `composer_editable` |

## Code map

| Layer | Path |
| ----- | ---- |
| Overlay + drag wiring | `packages/composer_editable/lib/src/widget/text_selection.dart` |
| Pure motion helpers | `selection_handle_motion.dart`, `handle_drag_chrome.dart`, `finger_tracked_handle.dart` |
| Visibility notifiers | `render_editable.dart` |

## Related

- [DIVERGENCES.md](../../DIVERGENCES.md), [README.md](../../README.md)
