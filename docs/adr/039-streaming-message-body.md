# ADR 039: Streaming message body

The text of a row that grows while its message stays fixed (an LLM reply over
any transport) is owned by the row, not by the data source. One controller
buffers deltas and notifies at most once per frame; ids stay the host's; a plain
mode skips the markdown parser and takes an inline hook.

**Status**: Accepted  
**Date**: 2026-10-28  
**Relates to**: [ADR 001](001-message-id-scheme.md), [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 034](034-rich-text-wire-and-persistence.md), [ADR 035](035-markdown-engine-fork.md), [ADR 037](037-spoiler-and-mention-inline-styles.md)

## Context

A streamed reply arrives as many small deltas, at 30 to 50 per second, into one
row. Pushing each delta through the data source as a new message would change
the row's identity, rebuild its tile and re-measure the viewport on every
delta. The package must stay transport-agnostic (no SSE here) and human chat
must see no behaviour change. The host needs to keep its own ids: the server id
of a reply often arrives only with the final event.

## Decided

| Concern | Decision |
| ------- | -------- |
| Row-owned body (approach B) | `ChatStreamingBodyController` holds the text of one row and implements `ValueListenable<Markdown>`. The message object of the row stays fixed; the viewport never sees a new message while the text grows, only a relayout of the row. The data source is not involved per delta. |
| One update per frame | `append(delta)` writes to a buffer and asks the frame scheduler once; every delta of that frame becomes one parse (a `StreamingMarkdownParser`, which re-parses only the still-growing tail) and one notification. The scheduler is a constructor seam (`ChatStreamingFrameScheduler`, default: the next engine frame) so a test drives frames by hand. Empty deltas are ignored. |
| Lifecycle | Live, then settled or disposed. `settle(finalText)` drops buffered deltas, replaces the text with the server's final text and notifies once, now. `append` after `settle` or `dispose` is a silent no-op (a late delta of a cancelled stream is normal and must not throw or revive the row); `settle` after `settle` or `dispose` is a no-op. A frame callback that outlives a `settle` flushes nothing. `isSettled` reports the state. The host ends the stream with one `updateMessage` that swaps the row to its final message. |
| Rendering and selection | `ChatStreamingBody(controller, messageId, body, theme, autoscroll, embedResolver)` renders the controller through `ChatMarkdownBody` and registers each text it shows with the selection facade (`putBody`, `order: messageId`), under the same registration rule as `ChatMarkdownBody`. Selection and copy work on a live row and after `settle`; the tile may keep the widget on the settled controller or switch to `ChatMarkdownBody`, the registration is the same. Everything around the text (bubble, steps, cards, actions) stays the host's. |
| Host-owned ids | The package promotes no provisional ids: **Message ID** stays immutable ([ADR 001](001-message-id-scheme.md)). The host assigns sequential local ids; server ids (the user message id, the reply's id from the final event) live in its tile model, not the scroll key. A live row that is removed (failed, or cancelled before text) becomes **Absent**; its id is not reused or promoted. The human chat's proposed-id and promote flow stays in the app. |
| Plain mode | `ChatStreamingBodyController(plain: true)` skips the parser. The text splits on `\n` into `MD$Paragraph`s of plain `MD$Span`s (empty lines are dropped), so `*`, `#`, `**` and `_` never format. It uses only public `flutter_md` types: no change to the fork. Selection and copy work as usual. |
| Inline hook | `ChatInlineHook(pattern, build)` (plain mode only; ignored in markdown mode). Every non-empty `pattern` match in a paragraph becomes the `MD$Span` that `build(match, start)` returns, where `start` is the match offset in its paragraph and the span should use it as its range so selection maps onto the text. The hook re-scans the whole accumulated paragraph on each frame, so a mark split across deltas (`[V` then `1]`) resolves to one span once its last piece arrives; until then the partial text shows literally. The span is any `MD$Span`; the AI Recruiter returns its vacancy pill (the `flutter_md` fork's vacancy style, the pill of ticket 01, which is text-native like [ADR 037](037-spoiler-and-mention-inline-styles.md)'s mention). |
| Follow tail | The glossary term **Follow tail** covers the last row growing in place and the band shrinking or growing under the tail (keyboard, composer, viewport resize), both under test (`chat_follow_tail_growth_test.dart`). Scrolled off the tail, history moves 0 px while the last row grows. Human chat gains the shrink fix. |

## Accepted as-is

| Item | Why |
| ---- | --- |
| Live-row selection is fixed at creation | A selection started on a live row does not grow with the text. Making it follow the growth is out of scope. |
| One-frame overshoot of about 7 px | When the steps block above the text opens, the row's growth is seen one frame late. Not worth a second layout pass. |
| Plain mode has no formatting at all | Intended: recruiter text is plain, and a literal `*` or `#` must show. A host that wants markdown uses the default mode. |
| No transport, no coalescing policy beyond a frame | SSE, retries and backpressure are the host's. |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| A new message per delta through the data source | Row identity, tile rebuild and viewport re-measure on every delta |
| Provisional-id slot with promotion in the package | Breaks the immutable Message ID; the host knows when its server id arrives and the tile model can carry it |
| A stream per row owned by the viewport | The package would own a transport concept; a `ValueListenable` is enough and any source can feed it |
| A `flutter_md` plain-text mode | Public `MD$Paragraph` and `MD$Span` already build the same `Markdown`; no fork change |
| Escaping markup in the host before parsing | Escapes leak into selection and copy |

## Consequences

- Additive: a minor release. Human chat is unchanged apart from the Follow tail
  fix.
- The text of a live row is re-parsed (markdown) or re-split (plain) per
  frame, not per delta. Plain mode with a hook rescans the accumulated text per
  frame, linear in the reply length.
- Performance on a physical phone: **pending**. Ticket 07 records raster and
  frame-budget numbers for a 2,000 character reply at 30 and 50 Hz with the
  steps block toggling (target: at most one frame over budget per reply, raster
  p90 of 3 ms or less, profile mode at 120 Hz). Link the result here once it
  exists; until then this ADR claims no number.
