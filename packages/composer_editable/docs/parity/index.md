# Composer text selection

Parity target for **`ExtendedTextField`** / **`MarkdownTextField`** (chat input,
job forms, any editable field). Reference: Telegram Android **composer** → stock
**AOSP `android.widget.Editor`** (`HandleView`, `SelectionHandleView`,
`MagnifierMotionAnimator`).

**Not in scope here:** read-only message bubbles. See
[bubble-selection/overview.md](../bubble-selection/overview.md).

## Glossary (canonical)

Ubiquitous language: [extended-text](../../packages/extended-text.md)
(`packages/extended_text/CONTEXT.md`). Do not fork terms in consumers.

## Concepts

| Topic | File | One-line |
| ----- | ---- | -------- |
| Reference stack | [architecture.md](architecture.md) | Composer vs bubble; what Telegram themes vs what AOSP owns |
| Handles | [handles.md](handles.md) | Appear, drag scale, finger-tracked overlay, frozen chrome, settle |
| Magnifier | [magnifier.md](magnifier.md) | Pointer-line focal, AOSP ~100ms smooth, hide-under-loupe |
| Gestures | [gestures.md](gestures.md) | Universal enter/dismiss, direction settling, invert model |
| Highlight | [highlight.md](highlight.md) | Hybrid boxes, exclusive-end affinity, paint vs ephemeral cache |
| Flutter gap list | [flutter-parity.md](flutter-parity.md) | Done / partial / missing in `extended_text` |

## Code map

| Layer | Path |
| ----- | ---- |
| Overlay + drag wiring | `packages/extended_text/lib/src/widgets/text_selection.dart` |
| Pure motion helpers | `selection_handle_motion.dart`, `handle_drag_chrome.dart`, `finger_tracked_handle.dart` |
| Hybrid geometry | `selection_boxes.dart`, `render_editable.dart` |
| Consumer | `packages/flutter_md/lib/src/editor/text_field.dart` |
| Spec / issues | `.scratch/composer-handle-motion/` |

## Related

- [extended-text](../../packages/extended-text.md)
- Repo: `packages/extended_text/DIVERGENCES.md`, `CONTEXT-MAP.md`
