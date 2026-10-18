# ADR 034: Rich-text wire and persistence contract

A message body travels, is stored and is drafted as one markdown string, the
dialect `RichTextMarkdown` writes. There is no entities table or second column.
The client enforces a length budget in code points of plain text; a server
guards storage in raw units and never truncates; mentions and link schemes are
checked on both sides and downgraded to text rather than rejected.

**Status**: Accepted  
**Date**: 2026-10-18  
**Relates to**: [ADR 017](017-body-linkify-host-invoked.md), [ADR 021](021-content-identity-and-collections.md), [ADR 023](023-data-layering-and-persistence.md), [ADR 026](026-composer-model.md), [ADR 029](029-host-integration.md), [ADR 032](032-rich-clipboard.md), [ADR 033](033-code-blocks-in-rich-text.md)

## Context

The reference clients keep a message as text plus an entity list. This
workspace keeps bodies as markdown ([ADR 017](017-body-linkify-host-invoked.md),
[ADR 029](029-host-integration.md)), and a host's backend usually stores one
text column. Three questions follow: what the stored form is, how long a message
may be when formatting costs source characters, and how far a server may trust a
body that claims a mention or a link.

The encoder's expansion is unbounded in general: a detected URL is written
twice, a short styled run costs 4 to 18 characters, escapes can double a text.
A limit on the markdown source would penalise formatting and could not be
checked from the visible text.

## Decided

| Concern | Decision |
| ------- | -------- |
| One form | The markdown string is the one persisted and wire form. `RichTextMarkdown` in `content_model` is lossless over the closed `EntityKind` set and is pinned against the markdown fork's parser by a conformance test in the fork ([ADR 035](035-markdown-engine-fork.md)). `RichText.toJson` stays client-local: the rich clipboard payload ([ADR 032](032-rich-clipboard.md)), never a draft or wire format. |
| Length budget | **4096 code points of `RichText.plain`** (`plain.runes.length`): Telegram's budget, set by the host from its server configuration as `ComposerSpec.messageLengthLimit`. The client shows the remaining count at 100 or fewer and refuses an over-budget send. Nothing counts markdown delimiters. Graphemes are not counted: a server cannot count them identically. |
| Raw guard | A server rejects a body over **16 384 UTF-16 code units** with a `400` and never truncates: cutting markdown inside an entity corrupts it. The guard is a storage limit sized for the encoder's expansion, not the message limit. When the server gains a reader of the `RichTextMarkdown` grammar it enforces the plain budget on ingest and publishes the limit in its configuration. |
| Mention trust | **Validate on both sides, downgrade, never reject.** The client rewrites every `Mention(id)` the host did not resolve in this draft (picked, loaded for edit, or pasted from the app's own HTML and re-checked against the user source) to `Username(name)` before encoding ([ADR 032](032-rich-clipboard.md) trust rule made concrete). The server checks each `mention:<id>` target on send and edit (the id exists and may be mentioned in the chat); a failing target becomes `username:<name>`, or the link is stripped to its label when the label is not an `@name`. A `400` carrying the field, offset and reason is for markup malformed beyond recovery only. |
| Link schemes | A server keeps an allow-list on ingest: `http`, `https`, `mailto`, `tel`, and the app schemes `mention`, `username`, `hashtag`, `document`, `unicode`, `external`. Any other scheme is downgraded to its label. The client encoder already refuses the banned schemes of [ADR 032](032-rich-clipboard.md). |
| Ingest | One ingest function serves send and edit: guard, mention check, scheme allow-list, then detection when the server has it, then store. |
| Reconcile | A response to a send or edit always carries the body as stored, and the client always reconciles its optimistic message with it. A server that rewrites a body, whether by downgrading a mention or by detecting links, is therefore a server-only change. |
| Detection | Client detection runs at send and as a receive-time fallback ([ADR 017](017-body-linkify-host-invoked.md)). A server may later detect on ingest and become the authority; the contract allows it and nothing requires it. `username:` and `hashtag:` targets are text and never validated. |
| Drafts | A draft is the same markdown string the wire carries, kept client-side in the host's `KeyValueStore` ([ADR 023](023-data-layering-and-persistence.md)) under a key derived from the chat id, with the edited message's id beside it for an edit in progress. It is written debounced on composer change and cleared on send; `richText` and `restore` are its two ends. A later server draft sync carries the same string. |
| Over-budget text | Sending a long text as a file is not composer contract (it needs file messages); a host may offer it as an action. |
| Existing data | No migration. Bodies stored before this contract decode as they are, and the receive-time fallback adds link-class entities lazily. A host whose stored dialect differs from the codec's repairs it on edit-load, idempotently and client-side; bodies nobody edits keep their bytes. |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| An entities table or a JSON column next to the text | A second source of truth for ranges against selection, copy and the markdown that bodies already are; a server-side change for a gain the codec already gives |
| Counting markdown source as the budget | Penalises formatting, and is the wrong unit for the user |
| Counting graphemes | The server cannot count them identically |
| A raw worst-case limit on source derived from the budget | The encoder's expansion has no tight bound |
| Silent truncation at a unit count | Corrupts markdown mid-entity; a user loses text without a message |
| `422` for an unknown mention | Punishes the common case of a stale mention; Telegram's server drops a bad mention entity and keeps the text |
| Draft as `RichText.toJson` | Two formats for one text; the markdown is the wire form and a server could carry it unchanged |
| Server-side data migration of stored bodies | Needs a reader of the grammar on the server and touches data outside the contract |

## Consequences

- A body at the plain budget stores unless its markdown source exceeds the raw
  guard (four times the budget in units); the guard is sized so ordinary
  formatting fits, and a pathological body is refused by the server although
  the client allowed it.
- A host that cannot read the markdown grammar on its server can only enforce
  the raw guard and the scheme and mention checks; the plain budget is then
  client-enforced.
- The server must publish its limit in configuration for the client budget to
  follow it; until then a host passes the constant.
