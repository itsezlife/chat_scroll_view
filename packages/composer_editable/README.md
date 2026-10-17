# extended_text

Fork of Flutter `EditableText` + Material `TextField` (and the selection
overlay pieces they need), vendored from the Flutter SDK pinned below.

## Why

Stock toolbar / scroll / IME lifecycle forces fragile workarounds. This package
owns those widgets so apps (and `flutter_md`) can fix behavior once and reuse
everywhere.

## Public API

- [ExtendedTextField] — Material text field
- [ExtendedEditableText] / [ExtendedEditableTextState] — raw editor
- [ExtendedEditableTextContextMenuBuilder] — context menu builder typedef

Internal selection helpers stay in `lib/src/widgets/text_selection.dart` and
are not part of the stable public surface yet.

## Flutter pin

See [DIVERGENCES.md](DIVERGENCES.md). Re-vendor with:

```bash
./tool/vendor_from_flutter.sh
```
