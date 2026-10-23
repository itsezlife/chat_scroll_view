# chat_composer

A slot-based chat composer. The host describes the composer for one moment as
a `ComposerSpec` (header, panel, actions, enabled, busy); `ComposerView` lays
it out in a glass island and animates from one spec to the next. Beside the
view sit the input-only controller, a text controller that keeps formatting
and inline content in step with every edit, and input queries for the
suggestion panels a host builds.

It depends on `content_model` (the `RichText` value, `InlineContentRef`), the
pure-Dart `package:listen` (`ValueListenable`: `softKeyboard`, `fieldHeight`,
`extent` and `query` are `package:listen` types, not Flutter's),
`chrome_foundation` (theme tokens, glass, motion, strings, icons) and `catalog_assets` (inline content in the field is drawn by
`ContentView`), and knows no panel, inset or presentation type
([ADR 026](../../docs/adr/026-composer-model.md),
[ADR 020](../../docs/adr/020-package-topology.md)).

## Slots

| Slot | Is | Filled by |
| --- | --- | --- |
| **Header** | The strip above the row: reply, edit, forward, link preview or a host-built suggestion. Reveals and hides with the `headerReveal` motion role. | `ComposerSpec.header`; several candidates are ranked by `ComposerHeader.prioritised` (edit, reply, forward, link preview, suggestion). |
| **Panel** | What occupies the row between the actions: the text field by default. | A `ComposerPanelId` in the spec; every id but `ComposerPanelId.text` is built by the host's `ComposerPanelResolver` (recording, recorded preview, restricted, join). |
| **Actions** | Buttons before and after the panel, mirrored in right-to-left text. | `ActionDescriptor`s: id, semantic icon id, placement, enabled, visible, `primary`, `active`, tap handler, an optional `wrap` and a required semantic label. |

The view holds no mode. Replying is a header the host sets, restricted is a
panel it names, send-or-voice is one action id whose icon it swaps (the glyph
morphs in place).

## Types

| Type | Role |
| --- | --- |
| `ComposerSpec` | The host's declarative description: `header`, `panel`, `actions`, `enabled`, `busy`, `messageLengthLimit`. Rebuilt from chat state, never mutated. |
| `ComposerView` | The island: glass surface, header reveal, row with field-height animation, action slots, panel resolver, shortcuts. Publishes `ComposerController.extent`. |
| `ComposerHeader` | Sealed: `reply`, `edit`, `forward`, `linkPreview`, `suggestion`. Reply and edit titles come from `ChromeStrings.composer`. |
| `ActionDescriptor`, `ActionPlacement`, `ActionWrap` | One action as data. `active` draws the glyph in the accent colour and announces the button as selected (a toggle that is on keeps its one glyph). `wrap` is a widget the composer builds around the rendered button, for whatever the host needs around it (a hover region, a tooltip, a measuring probe); the composer knows none of them. |
| `ComposerPanelId`, `ComposerPanelResolver` | An open set of panel names and the host function that builds the non-default ones. |
| `ComposerFormField` | The same field in a host's form: a `FormField<RichText>` under the host's `InputDecoration`, with the selection menu, lists and formatting keys of the island, `formatting`, `linkPrompt`, `backPriority`, focus through the controller, Flutter's validation and reset, and a `maxLength` counted in code points that is never enforced. |
| `ComposerBottomFade` | The soft fade under the composer. Mounts under the island, outside the glass source. |
| `ComposerShortcutPolicy`, `SubmitComposerIntent`, `DismissComposerHeaderIntent`, `ToggleStyleIntent`, `ToggleCodeBlockIntent`, `ApplyLinkIntent`, `ClearFormattingIntent`, `ToggleListIntent` | Intents and the `$Mobile` / `$Desktop` default key maps (formatting keys follow Telegram Desktop's). |
| `ComposerMetrics` | The island geometry, documented as component constants. |
| `ComposerController` | Input only: the text, focus, selection, field scroll, height and extent, the `softKeyboard` option, the input query and its commands (`insertText`, `insertContent`, `backspace`, `clear`, `restore`, `replaceQuery`), the code-point `length`, `sendableText` and `onPaste`. No mode state, no reply or edit ids. |
| `ComposerPaste` | What `onPaste` reports: the range the pasted text landed in, its plain text and whether the clipboard's rich form was used. |
| `ComposerLengthCounter` | The remaining-count label under the row, shown once `visibleFrom` (100) or fewer code points remain against `ComposerSpec.messageLengthLimit`. |
| `downgradeUnresolvedMentions` | The pure rewrite behind `sendableText`: mentions the host did not resolve become `@name` usernames. |
| `ComposerTextController` | A `TextEditingController` whose text carries entities. Recovers the replacement behind each platform value, applies it to a `RichText`, and exposes `richText` for drafts, send and edit-load. `restore` loads a `RichText` back. |
| `ContentViewSpans` | `ContentViewSpans.builder`, an `InlineContentSpanBuilder` that draws each inline reference through `ContentView`. |
| `SoftKeyboardMode` | `auto` or `suppressed`: whether focusing the field may show the on-screen keyboard. |
| `ComposerQueryKind`, `ComposerQueryRule` | A kind of token the host wants watched (trigger, where it may open, which characters it is made of). The set is open; the composer knows none. |
| `ComposerInputQuery` | The token at the caret: kind, text after the trigger, replace range and the caret anchor rectangle. Published by `ComposerController.query` (a `ValueListenable`); `null` when there is no token. |
| `ComposerEntityStyles` | The host's colours for links, mentions, code, spoiler and quote in the field. |
| `InlineContentSpanBuilder` | How the field shows an inline content reference. |

## Extent

`ComposerController.extent` is the height the view takes in its parent, as
data, frame by frame while it animates: the island with its header and the
margins around it. It excludes the bottom safe-area pad the view draws
(`safeAreaBottom`, default the bottom view padding; pass what a keyboard or
panel has left of it) and any panel or keyboard below. The host adds the bottom
band (the larger of the safe area and the presentation occupancy) and feeds
the sum to the chat's bottom padding ([host insets](../../docs/architecture/14-host-chrome-insets.md)).
The view imports no inset type.

## Behaviour that is easy to get wrong

- **Edits.** A text field reports a whole new value. The controller diffs it
  against the previous text, using the caret to settle ambiguity ("aab" minus
  one "a"), never cutting a surrogate pair, and applies the single replacement
  with `RichText.replaceRange`: an insertion strictly inside a styled run grows
  it, one at its edge does not, a deletion across an edge keeps the part
  outside, a deletion over the whole run removes it.
- **Inline content and mentions are atomic.** The caret never rests inside
  one (a caret moving forward lands after it, back lands before it), a range
  selection widens to hold it whole, and a delete that touches it removes all
  of it. `backspace` removes a whole reference, then one grapheme cluster.
- **Formatting commands** (`toggleStyle`, `toggleCodeBlock`, `applyLink`,
  `removeLink`, `clearFormatting`, with `isActive` / `canApply` / `canLink`
  for a menu's state) change the entities of the selection and never the text, except
  `applyLink` at a caret, which inserts the URL as linked text. A caret turns
  the others off, except the quote and code block, which act on the caret's
  line; there is no typing style, so text typed after a command is plain. What
  may coexist is `RichText`'s rule: code takes the other styles and links out
  of its range, a quote and a code block widen to whole lines, and a command it
  cannot hold (bold inside code, code over a mention) does nothing and
  `canApply` is false. A command that touches the IME composition does nothing.
- **Length budget.** `ComposerSpec.messageLengthLimit` is a number of code
  points of the plain text (`ComposerController.length`): a surrogate pair is
  one, formatting costs nothing and no markdown delimiter is counted. Null is
  no limit; a host passes its server's `message_length_max` (Telegram's is
  4096). Once 100 or fewer remain the view draws the count under the row, in
  the destructive colour when it is negative; while it is negative the
  `primary` action and the submit key are refused (the counter shakes, the
  handler is not called). A send through another action (scheduled, silent)
  checks `length` itself. The composer never trims.
- **Paste report.** `ComposerController(onPaste:)` is told of each paste that
  put text into the field, with the range it landed in after any widening over
  an atom, the plain text and `wasRich`. Paste itself is unchanged: plain stays
  plain, rich is the clipboard's payload, nothing parses markdown. The toast
  that offers to apply formatting is the host's, and applies it with
  `text.replaceRange`. Pastes without a `clipboard` are the platform's and
  are not reported.
- **Mention trust.** Encode `sendableText`, not `richText`: a mention the host
  did not resolve in this draft is sent as its `@name` (`Username`), and one
  whose text is not an `@name` as plain text. Resolved means picked through
  `replaceQuery`, loaded through `restore`, marked with `trustMention`, or
  accepted by the `confirmMention(id)` the host passes (its own look-up of the
  user, never the clipboard's claim). A pasted mention is none of those until
  confirmed. `clear` and `restore` forget the previous draft's trust.
- **Drafts.** A draft is the markdown string the wire carries. The host writes
  `RichTextMarkdown.encode(composer.richText)` to its `KeyValueStore`
  (`content_model`) under a key of the chat id, with the edited message's id
  beside it, debounced on change, and removes it on send; opening the chat
  calls `composer.restore(RichTextMarkdown.decode(stored.value))`. The two
  ends are lossless for every entity kind (a contract test pins it), keep
  newlines and a trailing space, and `RichText.toJson` is not a draft format.
  The composer ships no store helper.
- **The selection menu** is the composer's own (`ComposerSelectionMenu`), on
  every platform, not the platform's: a two-page card. The main row holds the
  clipboard actions and a More button; the More page slides in from the right
  (300 ms, swipe right to close) and holds the clipboard actions that did not
  fit the row, then the formatting actions, with a Back row. Sizes and fit are
  Telegram's floating toolbar: main-row buttons 48 dp tall with 16 dp padding,
  the 56 by 48 More button, labels 14 dp medium, page tiles 42 dp, and a page
  as wide as its widest label (no label is ellipsized where the screen has the
  room) showing four rows and half of a fifth before it scrolls; the card is
  Material elevation 3. Every label is the host's `ChromeStrings`: Cut, Copy,
  Paste and Select all from `editMenu`, the rest from `formatting`, never from
  `MaterialLocalizations`.
  `ComposerSpec.formatting` says which items it may offer, listed in the order
  of `ComposerFormattingOption`; an item whose command cannot apply to the
  selection is greyed, not hidden (Quote is left out over a quoted selection),
  and a collapsed caret gets the page too, with only the line kinds and Link
  enabled. Link is one item, Create or Edit, and needs
  `ComposerSpec.linkPrompt`, which receives the current URL when the selection
  already holds a link; Remove link shows while it does.
  `ComposerSpec.backPriority` is the host's hook for taking Back ahead of the
  soft keyboard while the menu is open; Back closes the whole menu from either
  page. After an item the menu closes and the selection collapses to a caret at
  its extent. Tab from the field enters the menu, and Escape closes it. The
  clipboard labels are Material's, and the colours are `SelectionMenuTokens`
  (build the chrome palette from a colour scheme with
  `ChromePalette.fromColorScheme` for Material's own look).
- **The pointer menu** is the desktop presentation of the field's menu, chosen
  by `ComposerMenuPolicy` (`$Desktop` on macOS, Windows, Linux and the web;
  `$Mobile`, no pointer menu, on touch platforms; pass `ComposerView.menuPolicy`
  to choose). A secondary click in the field opens the reference desktop
  client's context menu at the pointer, a pointer-anchored popup drawn by
  `chrome_foundation`'s `PointerMenu`, and leaves the caret and selection
  where they were (the press opens it on macOS and Linux, the release on
  Windows; `ComposerMenuPolicy$Desktop.platformsOpeningOnPress` is the one
  place that is written). The Menu key and Shift+F10 open it at the caret.
  Rows, top to bottom: Undo, Redo, Cut, Copy, Paste (and Paste as plain text
  while there is a rich clipboard), Delete, Formatting (Bold, Italic,
  Underline, Strikethrough, Quote, Monospace, Spoiler, Code block, the list
  rows while lists are on, Create link or Edit link and Remove link, Clear
  formatting) and Select All, each with its shortcut hint in the platform's
  native form. A row that cannot apply is greyed, never hidden; at a caret
  every style row is greyed. Right-clicking a link with nothing selected
  offers Edit link and edits that link. The Formatting submenu opens on hover
  or Right; arrows, Enter, Space and Escape drive the menu, and the field
  keeps focus and its painted selection throughout. Labels are
  `ChromeStrings.editMenu` (Qt-style `&` mnemonics are drawn underlined), the
  colours `ChromeThemeScope`'s pointer menu tokens. **Spelling** is a seam
  only: give `ComposerSpec.spellChecker` a `ComposerSpellChecker` and the menu
  shows a Spelling submenu for the word under the pointer; there is no
  built-in checker. The floating toolbar stays for touch. Every value the
  reference does not give is a named constant listed in
  [ADR 026](../../docs/adr/026-composer-model.md)'s divergence table.
- **IME composition.** While the composing range is non-empty the entities are
  not touched. When composition ends the whole composition is applied as one
  replacement against the text before it began. `richText` stays consistent
  with `text` throughout.
- **The soft keyboard** is declared, not commanded: while `softKeyboard` is
  `suppressed` the field declares `TextInputType.none`, so focus, caret,
  selection and hardware keys work and the platform keeps its keyboard down.
  No platform channel is involved; the hand-off with a panel is the host's
  presentation's job.
- **Submit** (desktop policy: Enter; Shift+Enter is a newline) invokes the
  `primary` action, and does nothing while the input method composes, the spec
  is busy or disabled, or no primary action can be tapped, so it never eats
  the key that confirms a composition.
- **A pointer tap on an action leaves the field focused**, so the caret and
  the keyboard stay where they were; keyboard users traverse to an action and
  press Enter or Space.
- **Queries** are detected at a collapsed caret, also while composing, never
  through inline content, and the first registered kind wins.
  `replaceQuery` refuses a stale query.

## Host contract

| The host provides | The host must not |
| --- | --- |
| A `ComposerSpec` rebuilt from chat state, every action's `semanticLabel` (from `ChromeStrings.composer` or its own language), and for any panel other than the text field a `panelResolver`. | Mutate a spec, give two actions one id, or look for mode state in the composer. |
| Above the view: `ChromeThemeScope`, `ChromeStringsScope`, a `Directionality`, a `MediaQuery` and Material localisations (the text field reads them; the menus' labels do not). Optional: `GlassSourceScope`, `GlassQualityScope`, `ChromeMotionScope` (map `MediaQuery.disableAnimations` to instant speed), `ChromeIconScope` and an `AssetCacheProvider` when inline content is drawn. | Expect a default language, a silent light theme or reduce-motion read from the platform. |
| The extent: `ComposerController.extent` plus `max(safe area, presentation occupancy)` into the chat's bottom padding, and as `safeAreaBottom` what a keyboard or panel has left of the safe area. | Expect the composer to know insets, the panel or the keyboard height. |
| Icons for header kinds without a stock id (`forward`, `link`) through `ChromeIconScope`; any custom action icon the same way. | Expect an unregistered id to draw more than the neutral glyph. |
| Query kinds (`registerQueryKind`) and the suggestion panels for them; the replacement `RichText` (with its mention or inline reference entity and any trailing space) passed to `replaceQuery`. | Expect the composer to look anything up, detect bare URLs or `@names` (entity detection is host-invoked, not viewport paint, [ADR 017](../../docs/adr/017-body-linkify-host-invoked.md)), or draw a suggestion panel. |
| Entities that are links and mentions, made where the user or the host decides what they are, inserted with `text.insert` or `replaceQuery`. | Rely on the controller to turn typed text into an entity. |
| `entityStyles` (usually `ComposerEntityStyles.fromTokens` of the chrome theme) and an `inlineContentBuilder` whose span lays out as exactly the reference's alternative text length. | Return a span of another length: the field maps selection by text offsets (a debug assertion checks it). |
| Mode state: reply or edit ids, banners, the busy flag. It loads an edited message with `restore(RichText)` and reads `sendableText` to send and `richText` to store a draft, both through `RichTextMarkdown`. | Look for reply, edit or enabled state on the controller, or store a draft as `toJson`. |
| `messageLengthLimit` from its server configuration, a `confirmMention` over its own users when pastes may carry mentions, an `onPaste` when it offers to apply formatting, and the draft store with its debounce. Any trim (an emoji-only message skips it) before the send. | Count markdown source as the length, encode `richText` when it means to send, or expect the composer to trim. |
| For the pointer menu: `ChromeStrings.editMenu`, a `ChromeThemeScope` (it supplies the pointer menu tokens; `PointerMenuTokens.referenceDay` and `referenceNight` are the reference's own), optionally `ComposerView.menuPolicy` and `ComposerSpec.spellChecker`. | Expect a built-in spell checker, or the pointer menu on a touch platform. |
| For the selection menu: `ComposerSpec.formatting` (which items; the default is every item but the list items), `ComposerSpec.linkPrompt` (the link dialog, given the current URL when the selection is linked; without it there is no link item), `ComposerSpec.backPriority` (the hook that takes Back ahead of the soft keyboard; the soft keyboard consumes Back before Flutter sees it, so without it Back closes the menu only where Flutter's own dispatch gets it), the labels in `ChromeStrings.formatting`, and the menu's tokens (`SelectionMenuTokens`) and its `menuEnter`, `menuLeave` and `menuPage` motion roles from `chrome_foundation`. | Mount a `ComposerSelectionMenu` itself, expect an item that cannot apply to vanish (it is greyed), or expect the platform's menu on any platform. |
| The `softKeyboard` option, set while another surface stands in for the keyboard, and the focus commands. | Expect the controller to show or hide the keyboard or touch a platform channel; the field declares its input type from these inputs. |
| Nothing for the field's reports: the view calls `reportFieldHeight`, `reportExtent` and `reportCaretAnchor` itself. | Call the `report...` methods, or read the anchor as exact: it may lag the text by a frame, and is `null` before the first report. |
| Disposal of every controller, focus node and scroll controller it passed in. | Dispose what the composer created, or use a controller after it. |
| Import hygiene: `hide RichText` on the Flutter widgets import (or `as model` on this one). | Import both `RichText`s unqualified in one file. |
| For a form field: `ComposerFormField` with its own `InputDecoration`, `formatting`, `linkPrompt` and `backPriority` (what a spec carries for the island), the text controller's `entityStyles`, a Material ancestor, and its own length check in the validator when saving over `maxLength` must be refused. | Expect the form field to trim, refuse input past `maxLength`, submit on Enter, or swap its controller without a new key. |
| The field through `ComposerView` or `ComposerFormField` only. Both render `ExtendedTextField` from `composer_editable` (Material handles on every platform, overscroll handed to the chat); `ComposerController.fieldScroll` is the mirror of its scroll position. | Use `ExtendedTextField` directly, or expect a stock `TextField` or `EditableText` in the tree. |

Constructor requirements: `ComposerView` takes `controller` and `spec`;
`ComposerController` takes nothing (it builds the text controller, focus node
and scroll controller it is not handed, and disposes only those);
`ComposerTextController` takes nothing, or an `inlineContentBuilder`.
`ContentViewSpans.builder` takes the `AssetCacheScope` to draw through, or
looks up the nearest `AssetCacheProvider`.

Decisions: [ADR 026](../../docs/adr/026-composer-model.md) (model, queries),
[ADR 031](../../docs/adr/031-localization-accessibility-and-input.md) (entity
edits commit on finished IME composition),
[ADR 029](../../docs/adr/029-host-integration.md) (host wiring). Glossary:
[Chat chrome](../../docs/chrome/CONTEXT.md).

## Testing

The package defines no data seam, so there is no `testing.dart`. The pure
parts (`TextReplacement.between`, query detection, header priority) and the controllers run
in plain `flutter test` with `TextEditingValue` writes standing in for the
platform (`test/support/simulated_input.dart`); the view runs under
`test/support/composer_harness.dart`, which supplies every required scope with
the English preset of `chrome_foundation/testing.dart`.

Goldens (`test/goldens`) show each state (idle, reply, edit, restricted) in
light and dark and in both text directions on the flat glass path, with the
test font and the Material icon font from the SDK. They are generated on macOS
with a 1% pixel tolerance; regenerate with
`flutter test --update-goldens test/view`. The sampled and filtered glass
paths are device-dependent and belong to the device checklist.
