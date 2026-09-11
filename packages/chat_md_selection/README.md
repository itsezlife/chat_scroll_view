# chat_md_selection

Message-then-text selection for chat lists: register markdown bodies by Message
ID, keep character selection inert until entry, collapse membership to one
**text selection subject**, arm that document only, and expose Copy / Select
all via pinned `flutter_md`.

## Contract

- Register bodies by Message ID; markdown selection gestures stay disabled until
  [ChatMdSelectionController.enterTextSelection].
- Construction owns [ChatSelectionController.spanYield]: yields only when the
  id is already selected and the global point hits that message’s selectable
  body text; the yield notify enters text selection at that point.
- First long-press on glyphs of an unselected message never yields — message
  selection / span still wins. Long-press on selected padding / chrome does not
  yield (unselect span remains available).
- Selected bodies mount a hit-test surface while text selection is inactive;
  only the subject mounts a surface (and is armed) while text selection is
  active.
- Entry collapses message membership to the subject and arms only that
  document for character ranges.
- Leaving message selection clears text selection.
- `flutter_md` is pinned by git commit SHA in `pubspec.yaml`.

## Usage

Register bodies, wrap the subtree in [ChatMdSelectionScope], paint with
[ChatMdBody]. Span yield is wired automatically; hosts may also call
[ChatMdSelectionController.enterTextSelection] (with a global point, or without
for select-all).
