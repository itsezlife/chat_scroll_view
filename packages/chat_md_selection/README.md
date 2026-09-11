# chat_md_selection

Message-then-text selection for chat lists: register markdown bodies by Message
ID, keep character selection inert until entry, collapse membership to one
**text selection subject**, arm that document only, and expose Copy / Select
all via pinned `flutter_md`.

## Contract

- Register bodies by Message ID; markdown selection stays inert until
  [ChatMdSelectionController.enterTextSelection].
- Entry collapses message membership to the subject and arms only that
  document for character ranges.
- Leaving message selection clears text selection.
- `flutter_md` is pinned by git commit SHA in `pubspec.yaml`.

## Usage

Register bodies, wrap the subtree in [ChatMdSelectionScope], paint with
[ChatMdBody], then call [ChatMdSelectionController.enterTextSelection] (with a
global point, or without for select-all).
