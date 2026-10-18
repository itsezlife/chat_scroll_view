# Changelog

All notable changes to `chat_composer` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- `ComposerSelectionMenu`, the field's selection menu on every platform:
  Telegram Android's floating toolbar (48 dp rows, a 56 by 48 More button, an
  overflow page that reshapes the card over 250 ms and is sized to its items up
  to 264 dp with an edge fade, enter 150 ms, dismiss 150 ms plus 100 ms, a hide
  while the selection moves after 500 ms and back 50 ms after). The platform
  menu is no longer used. Items: the clipboard actions, then Quote, Spoiler,
  Bold, Italic, Mono, Strikethrough, Underline, Code block, the list items
  (while lists are on), Create or Edit and Remove link, and Regular. An item
  that cannot apply to the selection is left out. Tab from the field moves
  focus into the menu; Escape closes it.
- `ComposerFormattingOption` and `ComposerSpec.formatting`: which items the
  menu may offer (default `ComposerFormattingOption.standard`).
- `ComposerSpec.backPriority` (`ComposerBackPriority`): the host's hook for
  taking Back ahead of the soft keyboard while the menu is open.
- `ComposerTextController.selectedLinkUrl`: the target of the link the
  selection touches.
- Formatting shortcuts: `ToggleStyleIntent`, `ToggleCodeBlockIntent`,
  `ApplyLinkIntent`, `ClearFormattingIntent` and `ToggleListIntent`, bound in
  both default maps to Telegram Desktop's keys (Ctrl or Cmd with B, I, U, K;
  with Shift also X, M, P, `.`, N, 7, 8). Each Action calls the
  `ComposerTextController` command the selection menu calls, and is enabled
  by `canApply`, so a key that would change nothing reaches the field. The
  code block has no key. The list Intent has no Action yet.
- `ComposerSpec.linkPrompt` (`ComposerLinkPrompt`): the host's dialog that
  asks for a link's URL; the link shortcut is inert without it.

### Changed

- Source-breaking: `ComposerLinkPrompt` takes the current URL,
  `(BuildContext, String? currentUrl)`, null when the selection holds no link;
  the dialog edits it when there is one.
- The selection menu's "Paste as plain text" is on the overflow page unless the
  row has room for it, and the clipboard labels are Material's.
- The link shortcut is enabled over a selection already linked to the probe
  URL it used to compare against (`https://example.com`).
- The field's `contextMenuBuilder` is one stable tear-off, so a rebuild of the
  field no longer recreates the editable's toolbar.
- The field renders `ExtendedTextField` from `composer_editable`, with Material
  selection handles on every platform and overscroll handed to a parent
  scrollable; it is no longer a stock `TextField` (a test finding `TextField`
  or `EditableText` finds `ExtendedTextField` / `ExtendedEditableText`).
- Source-breaking: `contentSpanBuilder(scope: ...)` is
  `ContentViewSpans.builder(scope: ...)`, and the default
  `alternativeTextSpan` is `ComposerTextController.alternativeTextSpan`.

### Fixed

- A backspace from the host (the panel's) that empties the field, or one on
  an empty field, no longer fails an assertion while revealing the caret: an
  empty field has no line to measure, only the caret.

- An edit made through the controller (`insertText`, `insertContent`,
  `backspace`: a panel's emoji or backspace) scrolls a field past its maximum
  lines to show the whole line the caret is on, as typing does. Flutter
  reveals the caret only after edits typed into the field, so an emoji
  inserted from a panel could land on a line out of sight. The field answers
  the controller's new `caretReveals` signal after the frame, at once, by the
  line as laid out.
- A mouse click on a composer button keeps the field focused on desktop
  platforms: the buttons are part of the field's tap region.

### Changed

- Source-breaking: `ComposerBottomFade` is a `StatelessWidget` that washes the
  whole zone: the island-shaped hole and its `glassKey`, `glassCornerRadius`,
  `cutoutSync` and `ComposerBottomFadeState` are gone. `ComposerView.islandKey`
  stays for hosts that measure the island.
- A mouse over an enabled action turns its glyph to `ActionTokens.iconHover`.

### Changed

- **`ComposerController.extent` excludes the bottom safe-area pad.** The view
  still draws `safeAreaBottom`; the host adds the bottom band itself (the larger
  of the safe area and the presentation occupancy). The extent is measured after
  layout and reaches the host a frame late, so a sum that relied on the pad
  dipped while a panel closed under the safe area. A host that fed the extent
  straight into the chat's bottom padding adds the safe area now.
- `ComposerController.requestKeyboard()`: asks the field to raise the
  on-screen keyboard after the frame. The field focuses, or, when it took focus
  while the keyboard was suppressed, attaches to the platform's text input
  again with the current type (Android keeps the type a field attached with,
  so such a field never raised the keyboard it was allowed again). Changing
  `softKeyboard` alone still shows nothing, so a panel that closes leaves the
  keyboard down; a tap on such a field attaches it again by itself.
- `ComposerView.onFieldPointerDown` / `onFieldPointerEnd` (and the same pair on
  `ComposerField`): a pointer went down on the field, and lifted or was
  cancelled. They come before the field reacts, so a host can lift a
  suppressed keyboard on the press and the tap's focus attaches with the
  keyboard allowed. The lift comes before `onFieldTap`.

### Changed

- Change notification is `package:listen` (`listen: ^1.0.1`), not
  `content_model`'s removed `Observable` family: `ComposerController`'s
  `softKeyboard`, `fieldHeight`, `extent` and `query` are `ValueListenable`s
  (the `package:listen` type, not Flutter's, which is a different one), and
  the internal `ObservableBuilder` is `ListenValueBuilder`.

### Added

- `ComposerController` attaches to its clipboard (`RichClipboard.attach`):
  where the platform performs copy, cut and paste itself (a browser), the
  composer's focused field takes them over and keeps its entities.

- `ComposerController(onPastedMedia:)`: a paste while the clipboard holds
  images or files hands them to the host instead of inserting text (a paste
  as plain text leaves them), and an image a keyboard inserts
  (`ContentInsertionConfiguration`, Android) goes there too;
  `receiveMedia` hands media over directly. The host completes with whether
  it sent them; a paste whose media was not sent pastes the text that came
  with it, as the reference desktop client does. Text and media come from
  one clipboard read.
- A paste lands nowhere when the text changed while the clipboard was read
  or the host looked at the media.
- Inserted entities that cannot sit where the text lands are dropped the
  broadest first (code blocks and quotes, then styles, then links), not all
  at once: a code block pasted into a quote keeps the custom emoji next to
  it.
- `ComposerShortcutPolicy.desktop(inBrowser:)`: in a browser, which pastes
  as plain text itself, Shift+V with Command or Control is left unbound;
  `forPlatform(isWeb: true)` sets it.
- A code block (`EntityKind.codeBlock`) is styled as inline code.
- Rich clipboard (ADR 032): `ComposerController(clipboard:)` takes a
  `RichClipboard`, and `copySelection`, `cutSelection` and `paste({plain})`
  keep the text's entities across the system clipboard. Pasting into a quote
  unwraps the pasted quotes; a failing clipboard is reported and changes
  nothing. With a clipboard the field routes its copy, cut and paste there
  (key shortcuts, macOS menu selectors, the selection menu, which also offers
  Paste as plain text); without one it keeps the platform's plain clipboard.
- `PastePlainTextIntent`, bound to Shift+V with Command or Control in both
  shortcut policies.
- `ActionDescriptor.wrap` (`ActionWrap`): a widget the composer builds around
  the action's rendered button, so a host can put a hover region, a tooltip
  or a probe around one action without the composer knowing it. The button
  keeps its key and still receives taps; an action that is not visible is not
  wrapped.
- `ActionDescriptor.active` and `ComposerButton.active`: the on state of a
  toggle. The glyph takes the accent colour and the button is announced as
  selected; an inactive button sets no selected state, as before.
- `ComposerSpec` (header, panel, actions, enabled, busy) and `ComposerView`:
  the island with a glass surface, a header strip that reveals and hides, a
  row that follows the height of its panel, directional layout and action
  slots. Replaces the sealed idle, editing and replying mode, the hard-coded
  attach, voice and send buttons and the emoji-face icon resolver of the
  previous chrome: those become a `ComposerHeader`, an `ActionDescriptor`
  list and a host-set icon id.
- `ComposerHeader` (reply, edit, forward, link preview, suggestion) with
  `prioritised`; `ComposerPanelId` and `ComposerPanelResolver` for panels the
  host supplies; `ActionDescriptor` with a required semantic label.
- `ComposerController.extent`: the view's height as data, for the host's
  bottom padding.
- `ComposerBottomFade` (from `ChatContentBottomFade`), `ComposerMetrics` (from
  `ChatInputMetrics`), `ComposerShortcutPolicy` with
  `SubmitComposerIntent` and `DismissComposerHeaderIntent`.
- `contentSpanBuilder`: inline content in the field drawn by `ContentView`.
- A suppressed soft keyboard declares `TextInputType.none`; the composer uses
  no platform channel.

- `ComposerController`: input-only controller (text, focus, selection, field
  scroll and height, `SoftKeyboardMode`, commands `insertText`, `insertContent`,
  `backspace`, `clear`, `restore`).
- `ComposerTextController`: a `TextEditingController` that keeps `RichText`
  entities in step with edits, treats inline content and mentions as atomic,
  and applies IME compositions as one replacement when they finish.
- `ComposerInputQuery` listenable with host-registered `ComposerQueryKind`s
  and `ComposerController.replaceQuery`.
