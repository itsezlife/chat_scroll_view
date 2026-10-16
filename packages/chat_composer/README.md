# chat_composer

The input side of a chat composer: an input-only controller, a text controller
that keeps formatting and inline content in step with every edit, and input
queries for the suggestion panels a host builds. It depends on
`content_model` (the `RichText` value, `InlineContentRef`, `Observable`) and
`chrome_foundation` (token groups), and knows no panel, inset or presentation
type ([ADR 026](../../docs/adr/026-composer-model.md),
[ADR 020](../../docs/adr/020-package-topology.md)).

The slot-based view (`ComposerSpec`, header, panel and action slots, the island
and the field widget) is a later part of this package; this release is the
controllers.

## Types

| Type | Role |
| --- | --- |
| `ComposerController` | Input only: the text, focus, selection, field scroll and height, the `softKeyboard` option, the input query and its commands (`insertText`, `insertContent`, `backspace`, `clear`, `restore`, `replaceQuery`). No mode state, no reply or edit ids. |
| `ComposerTextController` | A `TextEditingController` whose text carries entities. Recovers the replacement behind each platform value, applies it to a `RichText`, and exposes `richText` for drafts, send and edit-load. `restore` loads a `RichText` back. |
| `SoftKeyboardMode` | `auto` or `suppressed`: whether focusing the field may show the on-screen keyboard. |
| `ComposerQueryKind`, `ComposerQueryRule` | A kind of token the host wants watched (trigger, where it may open, which characters it is made of). The set is open; the composer knows none. |
| `ComposerInputQuery` | The token at the caret: kind, text after the trigger, replace range and the caret anchor rectangle. Published by `ComposerController.query` (`ValueObservable`); `null` when there is no token. |
| `ComposerEntityStyles` | The host's colours for links, mentions, code, spoiler and quote in the field. |
| `InlineContentSpanBuilder` | How the field shows an inline content reference. |

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
- **IME composition.** While the composing range is non-empty the entities are
  not touched. When composition ends the whole composition is applied as one
  replacement against the text before it began. `richText` stays consistent
  with `text` throughout.
- **Queries** are detected at a collapsed caret, also while composing, never
  through inline content, and the first registered kind wins.
  `replaceQuery` refuses a stale query.

## Host contract

| The host provides | The host must not |
| --- | --- |
| Query kinds (`registerQueryKind`) and the suggestion panels for them; the replacement `RichText` (with its mention or inline reference entity and any trailing space) passed to `replaceQuery`. | Expect the composer to look anything up, detect bare URLs or `@names` (body linkify is host-invoked, [ADR 017](../../docs/adr/017-body-linkify-host-invoked.md)), or draw a suggestion panel. |
| Entities that are links and mentions, made where the user or the host decides what they are, inserted with `text.insert` or `replaceQuery`. | Rely on the controller to turn typed text into an entity. |
| `entityStyles` (usually `ComposerEntityStyles.fromTokens` of the chrome theme) and an `inlineContentBuilder` whose span lays out as exactly the reference's alternative text length. | Return a span of another length: the field maps selection by text offsets (a debug assertion checks it). |
| Mode state: reply or edit ids, banners, the busy flag. It loads an edited message with `restore(RichText)` and reads `richText` to send or store a draft (`toJson`, or `RichTextMarkdown` for a body). | Look for reply, edit or enabled state on the controller. |
| The `softKeyboard` option, set while another surface stands in for the keyboard, and the focus commands. | Expect the controller to show or hide the keyboard or touch a platform channel; the field does, from these inputs. |
| The field's reports: `reportFieldHeight`, `reportCaretAnchor`. The host feeds `fieldHeight` into its bottom padding. | Read the anchor as exact: it may lag the text by a frame, and is `null` before the first report. |
| Disposal of every controller, focus node and scroll controller it passed in. | Dispose what the composer created, or use a controller after it. |
| Import hygiene: `hide RichText` on the Flutter widgets import (or `as model` on this one). | Import both `RichText`s unqualified in one file. |

Decisions: [ADR 026](../../docs/adr/026-composer-model.md) (model, queries),
[ADR 031](../../docs/adr/031-localization-accessibility-and-input.md) (entity
edits commit on finished IME composition).

## Testing

The package defines no data seam, so there is no `testing.dart`: the pure parts
(`diffText`, query detection) and the controllers run in plain `flutter test`
with `TextEditingValue` writes standing in for the platform
(`test/support/simulated_input.dart`).
