# ADR 038: Composer editable, the Flutter fork

`composer_editable` is the composer's one editable: a renamed, patched copy of
the framework's text field, editable text and selection overlay, kept as a
patch series over a recorded baseline of the pinned SDK. It is a leaf package
with `chat_composer` as its only dependent. This ADR records what it changes
from stock, what it drops, and how it follows SDK upgrades. It also carries the
gesture decisions of the fork's earlier local ADRs.

**Status**: Accepted  
**Date**: 2026-10-18  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 026](026-composer-model.md), [ADR 030](030-testing-policy.md), [ADR 031](031-localization-accessibility-and-input.md)

## Context

The reference composer is a plain Android `EditText`; its selection behaviour
is the platform's. Flutter's stock editable differs from that in ways a chat
composer notices: the toolbar remounts on scroll, handles cross badly, and the
touch gesture matrix is the framework's per-platform fork. A copy of the
editable that fixes these has to be owned by a package with its own tests, a
recorded baseline and a way to follow the SDK, or it drifts from the SDK it
copies.

## Decided

| Concern | Decision |
| ------- | -------- |
| Package | `packages/composer_editable`: a leaf (`flutter` and `characters` only) with `chat_composer` the only permitted dependent, enforced by the dependency lint ([ADR 020](020-package-topology.md)). Hosts reach the field through the composer view, never the raw field. Class names keep the `Extended*` prefix. |
| Names | The full-copy selection types that shadow the framework's names (`TextSelectionControls`, `SelectionOverlay`, `TextSelectionOverlay`, `ClipboardStatusNotifier`, `emptyTextSelectionControls`, the handle-control instances) are renamed `Extended*` and exported, so non-assignability to the framework types is visible at the import. |
| Kept divergences | Toolbar fade during scroll (the toolbar stays mounted and its hit-testing is dropped while the fade reads zero; overlap counts any selection box). Overscroll handoff to the parent scrollable, default on, because the composer sits over a scrolling chat. Crossing handles on every platform, with handle types frozen from drag start until the settle. Handle motion: a 250 ms overshoot appear, instant hide, a finger-tracked grab offset, a settle to the caret anchor. Magnifier: finger clamped to the line, line-centre Y, time-smoothed. The touch gesture matrix (below). Handle-controls plumbing, the clipboard seams, the gutter painter and the caret-visibility widening. The selection highlight painted as one shape: stock draws a rect per box and shows a seam between lines that no `BoxHeightStyle` closes, so the editable paints the stock boxes as one path with the engine's line gaps bridged. |
| Opt-in | `contentScrollPadding` (the inset band inside the scrolled text) is off by default and its `hintText` assert is softened. |
| Dropped | The hybrid selection-width paint with exclusive-end affinity: its parity claim is false (the reference composer's selection paint is AOSP's, glyph-bounded), it is the one divergence that reaches into the render object's internals (swapping the width style, downcasting listenables, debug-flag runtime guards), and stock `BoxWidthStyle.max` is what the reference shows. The handle drag scale: three documented values with no reference source. |
| Restored | The iOS system context menu reachability, the caret-tap Paste menu and the floating cursor, on the fork's menu-builder path. The Android spell-check `TypeError` is fixed with suggestions kept off. |
| Handles | The composer passes the fork's Material handle controls on every platform: the reference handles are drawn by the app, not by the platform. Cupertino stays available to an overriding host. |
| Gestures | **Touch platforms** (Android, iOS, Fuchsia): long-press selects a word and starts a one-touch extension; double-tap enters selection and finishes at once (no one-touch); there is no triple-tap paragraph selection; a tap dismisses an active selection; an idle caret tap places the caret. **Desktop platforms** keep the framework's long-press and triple-tap. Unnamed edges follow ordinary editable-field defaults. |
| Menu | The menu builder mounts `ComposerSelectionMenu` ([ADR 026](026-composer-model.md)). |
| SDK pin | The package pins Flutter exactly, raised only by a re-vendor; the workspace root carries the same bound and the CI toolchain file pins what CI runs. |
| Re-vendor | The fork is a patch series over a renamed baseline. A tool copies the five stock source files from a given SDK, renames and formats them (that output is the baseline for the SDK, kept under the package), three-way merges fork ← old baseline → new baseline, reports conflicts and runs the suite. The divergence list is regenerated from the baseline diff. A CI job dry-runs the re-vendor on the next stable SDK and reports; it does not fail the build. Every workspace SDK upgrade includes a re-vendor. |
| Gates | Its own `test/unit_test.dart` groups its test files; it uses the root analysis options after a mechanical cleanup, with no permanent lenient exception. A device checklist row covers composer selection: appear, drag, cross, settle, magnifier, toolbar fade on scroll, on Android and iOS ([ADR 030](030-testing-policy.md)). |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Keeping the application's copy | Every consumer would carry its own fork of 15 000 lines |
| Folding the files into `chat_composer` | The code has its own tests and re-vendor chore and needs a boundary |
| Keeping the name of the original package | Names the lineage; the role is the composer's editable |
| A stock `TextField` fallback beside the fork | Two editables in one composer, two behaviours to test |
| One universal gesture matrix on every platform | Desktop and web are pointer- and keyboard-driven; one-touch long-press and no triple-tap overreach there |
| Hand-edited copies at fixed paths | They drift from the SDK unnoticed; a merge-based tool shows conflicts instead |
| The fork's own lenient analysis options | A permanent exception in a workspace whose check has none |
| Keeping the hybrid selection paint | See Dropped |

## Consequences

- The fork does not compile on an SDK that removes an intent or internal it
  copies; the dry-run job reports that before anyone upgrades.
- A host cannot swap the editable for another: the composer renders through
  this one.
- Text selection chrome inside message bodies is a different system
  ([ADR 013](013-viewport-owns-markdown-text-selection.md)).
