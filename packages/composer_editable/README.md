# composer_editable

The composer's editable: Flutter's `EditableText` and Material `TextField`,
copied from the SDK, with the selection behavior of the Telegram Android
composer (handle appear and settle, finger-tracked handles, crossing handles,
magnifier focal point, touch gesture matrix, toolbar that fades while the field
scrolls, overscroll handoff to a parent). It depends on `flutter` and
`characters` only.

**A leaf.** `chat_composer` is the only workspace package that depends on it
([ADR 020](../../docs/adr/020-package-topology.md); the dependency lint in
`scripts/check` fails any other dependent and any workspace dependency of this
package). A host reaches the field through `ComposerView`, never through
`ExtendedTextField` directly.

## Public API

| Type | Role |
| --- | --- |
| `ExtendedTextField` | The Material text field. |
| `ExtendedEditableText`, `ExtendedEditableTextState` | The editor behind it and its state (menu anchors and button items, toolbar and magnifier control). |
| `ExtendedEditableTextContextMenuBuilder` | `Widget Function(BuildContext, ExtendedEditableTextState)`: the menu a host mounts. |
| `ExtendedSystemContextMenu` | The iOS system context menu for an `ExtendedEditableTextState`; the default menu where the platform supports it. |
| `ExtendedClipboardTextBuilder`, `ExtendedPasteTextTransformer` | The text a copy or cut writes, and the transform a paste applies. |
| `ExtendedRenderEditable`, `PaddedViewportOffset` | The render object (gutter, content inset, handle and toolbar visibility notifiers) and the viewport offset that carries the inset. |
| `ExtendedTextSelectionControls`, `ExtendedTextSelectionHandleControls`, the `ExtendedMaterial…`, `ExtendedCupertino…` and `ExtendedDesktop…` controls and their `extended…` instances | The handle and toolbar controls, copies of Flutter's under an `Extended` name. Not assignable to Flutter's `TextSelectionControls`. |
| `ExtendedSelectionOverlay`, `ExtendedTextSelectionOverlay`, `ExtendedClipboardStatusNotifier` | The selection overlay machinery. |
| `ExtendedTextSelectionGestureDetectorBuilder` (+ Delegate), `ExtendedTextSelectionGestureDetector` | The gesture layer a field's state subclasses. |
| `OvershootCurve`, `kTelegramHandleMotionDuration`, `smoothMagnifierInfo`, `computeHandleDragChrome`, … | The pure motion helpers behind the handle and magnifier, public for tests and hosts that draw their own handles. |

## Host contract

What the host passes to `ExtendedTextField`, and what happens when it does not.

| Input | Default | Contract |
| --- | --- | --- |
| `controller` | an internal `TextEditingController` | A stock `TextEditingController` (a subclass may override `buildTextSpan`). |
| `scrollController` | an internal one | Attached as the mirror of the handoff controller, so `jumpTo` and `position` work from outside; the field forces `ClampingScrollPhysics` while the handoff is on. |
| `delegateOverscrollToParent` | `true` | Edge scroll and fling beyond the bounds go to the nearest same-axis ancestor `Scrollable`. Set `false` when a nested page scroll is wrong. |
| `contentScrollPadding` | `EdgeInsets.zero` (off) | Multiline only. Vertical `InputDecoration.contentPadding` stays zero or the insets stack. The placeholder follows the inset as `hintText` or as `hint`. |
| `selectionControls` | the platform's controls | Pass `extendedMaterialTextSelectionHandleControls` for Material handles on every platform. A Flutter `TextSelectionControls` does not type-check. |
| `contextMenuBuilder` | the system menu on iOS where `SystemContextMenu.isSupported`, else `AdaptiveTextSelectionToolbar.buttonItems` | Receives an `ExtendedEditableTextState`; build from `contextMenuAnchors` and `contextMenuButtonItems`. Stock `*.editableText` constructors can not be used. |
| `spellCheckConfiguration` | none (disabled) | An enabled one gets Material defaults on Android. A builder the host passes is called with the extended state (declare its parameter as `Object`). Suggestions stay off. |
| `clipboardTextBuilder`, `pasteTextTransformer` | none (plain text) | Copy and cut write `clipboardTextBuilder(value)`; paste replaces the selection with `pasteTextTransformer(value, clipboardText)`. |
| `gutterPainter`, `gutterExtent`, `gutterInset` | none, `0`, `0` | Chrome in the leading gutter, outside the text clip. Pair `gutterExtent` with `gutterInset` so the field leaves room. |
| every other `TextField` parameter | as `TextField` | Unchanged. |

## Behaviour that is easy to get wrong

- **Which platforms get the touch matrix.** `android`, `iOS` and `fuchsia` use
  the long-press / double-tap / tap-dismiss matrix; desktop keeps stock
  gestures. iOS keeps the floating cursor on a focused long-press and the Paste
  toggle on a caret tap.
- **The toolbar is never remounted by a scroll.** It fades and drops out of hit
  testing while faded, so a menu's local state survives a scroll.
- **`RenderEditable.painter` is free.** The editable paints the selection
  highlight itself, as one shape without seams between lines, under the text
  and under a host's `painter`.
- **No debug-only branches.** Nothing reads the framework's pipeline-phase
  flags, so debug and release take the same path.

## Flutter pin and re-vendor

The sources are copies of Flutter's text input files (`EditableText`,
`TextField`, the selection overlay and the four handle controls), pinned to one
SDK **exactly**: `flutter: 3.41.7` in this package's `pubspec.yaml`, the same in
the root `pubspec.yaml`, `.fvmrc` and CI. `flutter pub get` under another
Flutter fails resolution instead of compiling stale copies.

The package is a patch series over a **baseline**: the SDK's files, renamed
(`Extended*`), fixed with this package's analysis options and formatted, kept in
`tool/baseline/<version>/`. [DIVERGENCES.md](DIVERGENCES.md) is generated from
that baseline and the sources; do not edit it, edit
`tool/divergences.template.md`.

**Every workspace SDK upgrade includes the re-vendor.** On a branch:

```shell
dart packages/composer_editable/tool/revendor.dart --sdk=<new flutter root>
```

(`dart tool/revendor.dart` from this directory; not `dart run`, which resolves
the workspace first. Without `--sdk` it uses `FLUTTER_ROOT` or the `flutter` on
`PATH`.) It then

1. raises every SDK pin and runs `flutter pub get`;
2. builds the new baseline from the SDK and three-way merges each file, old
   baseline to new baseline, into `lib/` (`git merge-file`);
3. regenerates `DIVERGENCES.md` and runs `flutter test test/unit_test.dart`;
4. prints which files merged cleanly, which conflict and what the suite said
   (exit 0 clean, 1 conflicts or a failing suite, 2 refused).

Resolve the `<<<<<<<` hunks it leaves in `lib/`, make the suite pass, commit.
`--baseline-only` rebuilds just the baseline and `DIVERGENCES.md` (after a
change to the rename table or the template); `--skip-suite` skips step 3's
tests. The tool refuses to run when a vendored path or the old baseline is
missing, and never creates a directory. A clean textual merge is not a semantic
guarantee: the suite and the device checklist (ADR 030) decide. The
`sdk-lookahead` workflow rehearses this against the newest stable every week
([scripts/README.md](../../scripts/README.md)).

See [CONTEXT.md](CONTEXT.md) for the terms, [docs/parity/index.md](docs/parity/index.md)
for the Telegram reference and the gaps, and the gesture decisions in
[docs/adr/](docs/adr/).

## Tests

`flutter test test/unit_test.dart` runs every test file in one process. Handle
motion and magnifier feel are checked on a device (ADR 030), not in widget
tests.
