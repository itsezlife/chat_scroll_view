# ADR 033: Code blocks in rich text

Rich text gains a code block entity: whole lines of code with an optional
language. It is what a fenced block of a message is, so copying one and
pasting it into the composer keeps it a block in its language, as the
reference clients keep `pre` with its language.

**Status**: Accepted
**Date**: 2026-10-17
**Relates to**: [ADR 021](021-content-identity-and-collections.md), [ADR 026](026-composer-model.md), [ADR 032](032-rich-clipboard.md)

## Context

`RichText` had inline `code` only. A fenced block in a message, a `<pre>`
pasted from a web page or another client, and a tapped code block all became
inline code, losing the block and its language. The composer could not hold
one, and the markdown a message is sent as could not write one.

## Decided

| Concern | Decision |
| ------- | -------- |
| Kind | `EntityKind.codeBlock({String? language})`: a payload kind beside link, mention and inline content, not an `EntityStyle`, because it carries the language. |
| Shape | Like a quote, it widens to whole lines. Like inline code, it holds no other entity, and it overlaps no quote, so the markdown it writes is one fence and nothing nests inside it. Blocks on neighbouring lines stay two, as quotes do; overlapping or touching blocks of one language merge. |
| Language | Letters, digits and `+ # . _ -` (`dart`, `c++`, `c#`, `objective-c`); anything else is refused, as a fence's info string could not carry it. |
| Markdown | A backtick fence, one longer than any backtick run in the code (three at least), with the language as the info string; the code inside is written as it is. Reading takes the first word of the info string as the language and runs an unclosed fence to the end. |
| JSON | `kind: codeBlock`, with `language` when there is one. |
| HTML | Written as `<pre>` or `<pre lang>`; read from `pre` with `lang`, `language`, `lng`, `data-language` or a `language-` class on its `code`. |
| Composer | Styled as inline code (monospace on the code background). There is no command to make one yet; one arrives by paste or by loading a message for editing. |

## Consequences

- A code block inside a quote cannot be said; a paste that has one keeps the
  quote and drops the block, the decoders' fallback order.
- Data written with a code block reads, in an older version, as text without
  it: unknown entity kinds are skipped by `Entity.fromJson`.
