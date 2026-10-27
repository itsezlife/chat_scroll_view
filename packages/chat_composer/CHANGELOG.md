# Changelog

All notable changes to `chat_composer` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added (counter threshold and attachment header)

- `ComposerSpec.messageLengthCounterFrom`: the text length from which the
  length counter shows (800 of 1000 hides it at 799, shows it at 800). Null
  keeps the stock last-100-remaining threshold, so the human chat is
  unchanged.
- `ComposerHeader.attachment`: a chip above the field with an icon, a title
  and a host-labelled trailing remove action (at least 48 dp, with a
  semantics label) that calls `onRemove`. Lowest priority of the header
  kinds; same 48 dp strip as the others.

### Fixed (monospace face)

- Inline code, a code block and the Mono label of the selection menu draw in
  a real monospace face on every platform (`ChromeMonospace`). They merged
  the CSS generic `monospace` into the field's style, and a host font from a
  package keeps that package through `merge`, so the face resolved as
  `packages/<package>/monospace` and fell back to the body face, on Android
  too. iOS and macOS also need a named family (Menlo), Windows Consolas.

### Added (primary style)

- `ComposerView.primaryStyle` (`ComposerPrimaryStyle`): `disc`, the default,
  draws the send as before; `glyph` draws the bare glyph in the send colour
  with no fill, dimmed when disabled.

### Added (unavailable menu actions)

- `ComposerUnavailableActions` (`hide`, `disable`) and
  `ComposerMenuPolicy.unavailableActions`: what the selection menu does with
  a formatting action that cannot apply to the selection. The mobile policy
  (Android, iOS) leaves it out; the desktop policy (desktop and the web) keeps
  it greyed, as before. `ComposerMenuPolicy.mobile` and `.desktop` take the
  other value from a host. The pointer menu always greys. A touch toolbar
  over plain text no longer shows Regular, and a caret's More page shows only
  the line kinds and Link.

### Changed (style continuation)

- `ComposerTextController`: the word typed at the end of a styled run
  continues it, and so does the word typed at a run's start when no run ends
  there; whitespace ends it. Bold, italic, underline, strike, spoiler, code
  and links carry; quotes, code blocks, list items, mentions, inline content,
  usernames and hashtags do not. A replaced selection and a finished IME
  composition follow the same rule. `insert` and `replaceRange` still put in
  exactly what they are given. There is still no typing style armed by a
  command at a caret.

### Added (form field)

- `ComposerFormField`: the composer's field in a host's form, a
  `FormField<RichText>` under the host's `InputDecoration`. It has the island's
  selection menu (`formatting`, `linkPrompt`, `backPriority`), lists (with a
  `ComposerTextController(lists: true)`), formatting and list keys (without
  submit: Enter is a newline), focus through the controller's `focusNode`,
  Flutter's `validator`, `onSaved`, `autovalidateMode` and `reset` (back to the
  text it was built with), and `maxLength` in code points of the plain text,
  counted in the decoration and drawn in the error colour past it, never
  trimmed. Before, the only public way to the field was `ComposerView`, the
  chat island, so a form host could not have the menu or lists.
- The island's field is unchanged: it is now one of two layouts of the same
  field.

### Fixed (More button press)

- The More button showed nothing when pressed: it was a bare `InkResponse`,
  which takes the theme's splash and highlight, transparent under Material 3.
  It is an `IconButton` again, 56 by 48, whose pressed state layer is the
  Material one.

### Changed (selection menu fit and language)

- The selection menu's sizes and fit are Telegram's floating toolbar
  (`FloatingToolbar.java`), traced value by value, instead of the fixed sizes
  the previous port took from the message menu. The main row's buttons are 48
  dp tall (were 42) with 16 dp padding (were 12; 24 at the row's first start
  and, with no More button, its last end), 48 dp wide at least, the More
  button is 56 by 48 flush with the card's end (was 46 by 42), and a button
  stays on the row while it fits beside the More button, the last item of the
  whole menu taking that room if nothing follows. Labels are 14 dp medium with
  no letter spacing (were the theme's body-large at 16), the Back label 16 dp
  regular. The More page is as wide as its widest row (was a fixed 150 dp that
  ellipsized any translation longer than about a dozen characters),
  never narrower than its Back row, never wider than the screen less 32 dp;
  it is four rows and half of a fifth tall at most (rows counted at 48 dp,
  two at least where the room is short) and scrolls under a 16 dp fade at
  both edges; its Back row is 48 dp (arrow at 16, label at 56) with a
  one-device-pixel hairline at its top edge, which is the card's edge when
  Back is above the list. The card is at most 264 dp tall (was 320), sits 16
  dp from the screen's sides (was 12) and its row is at most `min(400, width -
  32)` wide. Source-breaking only for code that imports `src/menu` internals.
  The page turn, the enter and leave motion, the elevation and the greyed
  formatting rows are unchanged and recorded as deviations in ADR 026.
- Every label of the selection menu, the clipboard rows included, is a
  `ChromeStrings` string: Cut, Copy, Paste and Select all come from
  `ChromeStrings.editMenu` (the pointer menu's group, its `&` marks removed),
  no longer from `MaterialLocalizations`. An app without a Material delegate
  for its language used to get English clipboard rows beside its own
  formatting rows. Existing tests that looked for Material's "Select all" will
  find the host's wording ("Select All" in the English preset). The field no
  longer needs Material localisations for the menu, only for its text field.

### Added (desktop pointer menu)

- The desktop presentation of the field's menu: a secondary click opens the
  reference desktop client's context menu at the pointer (Undo, Redo, Cut,
  Copy, Paste, Paste as plain text, Delete, Formatting, Select All, and a
  Spelling submenu when a checker is given), drawn by `chrome_foundation`'s
  `PointerMenu`, with shortcut hints per platform (`ComposerMenuHints`), greyed
  rows instead of hidden ones, the Formatting submenu (Bold ... Spoiler, Code
  block, lists, Create or Edit link, Remove link, Clear formatting) and Edit
  link for the link under the pointer. Chosen by `ComposerMenuPolicy`
  (`ComposerView.menuPolicy`, default by platform): on macOS, Windows, Linux
  and the web a right click no longer selects the word and shows the floating
  toolbar, it opens this menu and leaves the selection alone; the toolbar stays
  for touch and under `ComposerMenuPolicy.mobile()`. Existing code that
  asserted the floating card after a desktop right click will now see the
  pointer menu.
- `ShowComposerMenuIntent`, bound to the Menu key and Shift+F10 by the desktop
  shortcut policy, opens the menu at the caret.
- `ComposerController`: `undoHistory`, `canUndo`, `canRedo`, `undo`, `redo`,
  `deleteSelection`, `selectAll` and `canPaste` (a paste probe that gives up
  after 300 ms and says yes). `ComposerField` hands `undoHistory` to the
  editable.
- `ComposerTextController`: `linkAt`, `applyLinkTo` and `removeLinkFrom`, links
  addressed by position instead of by selection.
- `ComposerSpellChecker` and `ComposerSpec.spellChecker`: the host's spell
  checker seam. No implementation ships.

### Added

- `ComposerSelectionMenu`, the field's selection menu on every platform: a
  two-page swipe-back card. The main row holds the clipboard actions and a More
  button (46 by 42); the More page (150 dp wide, 42 dp tiles, a Back tile at the
  end nearer the selection, a 1 dp divider, scrolling inside 320 dp) slides in
  from the right over 300 ms and closes with a swipe right or a fling of 600
  dp/s; clipboard actions that do not fit the row (at most `min(400, width -
  24)` wide) go to the top of the page. Labels are the theme's body-large at
  16, the card is Material elevation 3 at radius 12, with Material icons. The
  card fades in over 150 ms and out over 220 ms with a 5 dp drift away from the
  selection; scroll and out-of-view fades are the editable's toolbar wrapper's.
  It sits above the selection when 320 dp fit there, else below, 8 dp over and
  20 dp under the selection, 12 dp from the screen's edges. The platform menu is
  no longer used. Items: the clipboard actions (with Paste as plain text while
  the composer has a rich clipboard), then Bold, Italic, Underline,
  Strikethrough, Monospace, Spoiler, Quote, Code block, Link (Create or Edit by
  state, and Remove link while the selection touches a link), the list items
  (while lists are on) and Clear formatting, each previewing its own effect. An
  item that cannot apply to the selection is greyed on the page, not hidden
  (Quote is left out over a quoted selection), and a collapsed caret gets the
  page with only the line kinds and Link enabled. After an item, and on Escape
  or Back, the menu closes and the selection collapses to a caret at its
  extent, on every platform; Back closes the whole menu from either page. Tab
  from the field moves focus into the menu (only the page that shows is
  traversed). The text scale is clamped to 1.3.
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
- `ComposerTextController.canLink`: whether a link can be put on the
  selection, whichever the URL (true over a link already, for the URL it
  has). The menu's link item and the link shortcut share one ask-and-apply
  protocol and this one applicability check.
- The list gutter has semantics: each marker is a node labelled from
  `FormattingStrings.bulletListItem` / `numberedListItem`, at its item's first
  line, so a screen reader speaks the list.

### Changed

- Source-breaking: `ComposerFormattingOption` is in the page's order (Bold,
  Italic, Underline, Strikethrough, Monospace, Spoiler, Quote, Code block,
  Link, Bullet list, Numbered list, Clear formatting); code that relied on
  `values` order sees the new one.
- Source-breaking: the clipboard actions of the menu take Material's labels on
  every platform (Cupertino's wording on iOS and macOS is gone), and Copy
  collapses the selection on every platform, not on Android alone.

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
