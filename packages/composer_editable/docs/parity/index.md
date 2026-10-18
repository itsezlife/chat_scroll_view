# Composer text selection

Parity target for **`ExtendedTextField`**, the editable behind the chat
composer. Reference: Telegram Android **composer** → stock **AOSP
`android.widget.Editor`** (`HandleView`, `SelectionHandleView`,
`MagnifierMotionAnimator`).

**Not in scope here:** read-only message bubbles, which use a different
Telegram helper and live in the chat viewport's text selection.

## Glossary (canonical)

Ubiquitous language: [CONTEXT.md](../../CONTEXT.md). Do not fork terms in
hosts.

## Concepts

| Topic | File | One-line |
| ----- | ---- | -------- |
| Reference stack | [architecture.md](architecture.md) | Composer vs bubble; what Telegram themes vs what AOSP owns |
| Handles | [handles.md](handles.md) | Appear, drag scale, finger-tracked overlay, frozen chrome, settle |
| Magnifier | [magnifier.md](magnifier.md) | Pointer-line focal, AOSP ~100ms smooth, hide-under-loupe |
| Gestures | [gestures.md](gestures.md) | Universal enter/dismiss, direction settling, invert model |
| Highlight | [highlight.md](highlight.md) | Stock paint; handle and toolbar visibility notifiers |
| Flutter gap list | [flutter-parity.md](flutter-parity.md) | Done / partial / missing in `composer_editable` |

## Code map

| Layer | Path |
| ----- | ---- |
| Overlay + drag wiring | `packages/composer_editable/lib/src/widget/text_selection.dart` |
| Pure motion helpers | `selection_handle_motion.dart`, `handle_drag_chrome.dart`, `finger_tracked_handle.dart` |
| Visibility notifiers | `render_editable.dart` |

## Related

- [DIVERGENCES.md](../../DIVERGENCES.md), [README.md](../../README.md)
