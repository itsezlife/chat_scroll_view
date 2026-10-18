# ADR 036: Emoji-only message presentation

A message whose text is only emoji is presented as the reference clients
present it: no bubble, enlarged, a single emoji as a sticker-sized animation.
The host classifies the body with a pure function in `content_model` and passes
the viewport a body kind; the viewport never re-detects.

**Status**: Accepted  
**Date**: 2026-10-18  
**Relates to**: [ADR 012](012-cross-platform-selection-policies.md), [ADR 021](021-content-identity-and-collections.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 029](029-host-integration.md)

## Context

All three reference clients reclassify a message after parsing: no media, text
of emoji and whitespace only, no entities except custom emoji, gated by a
default-on setting. A single emoji becomes a sticker-sized item (animated
pack emoji or custom emoji); several become enlarged text from fixed per-count
size tables, independent of the user's text size. There is no bubble; the time
and reactions sit on the body.

## Decided

| Concern | Decision |
| ------- | -------- |
| Classification | `EmojiOnlyText.of(RichText)` in `content_model` returns the ordered items (unicode sequence or document key) and line breaks, or null. The rule is Android's permissive one: emoji graphemes, whitespace and newlines only; the only entity allowed is inline content with a document key; any style, link, mention, quote or code block disqualifies; no count cap. Grapheme rules come from `emoji_data`'s tables, not a second regular expression. |
| Who calls | The host, when it builds the message model. It adds the two facts only it has (the message carries no media, a link preview counting as media; the large-emoji setting and the chat's permission) and passes the result as a body kind. The viewport never classifies. |
| Body | One viewport body widget, `ChatEmojiBody`, with two layouts. **Sticker** when there is exactly one item and the host resolved it to a document (a host-owned unicode-to-document map for the animated pack, or the custom emoji's own document). **Text** otherwise. No bubble. |
| Sizes | Android's tables, as a value the host may override. Text layout: font steps of 81.6, 55.2, 40.8, 33.6, 26.4, 22.8 dp by item count, one step larger when every item is a custom emoji; item box is the font plus 4 dp; text scale is ignored; newlines are honoured; with a header above, wrap width is capped at 65 % of the row's maximum. Sticker layout: `min(viewport width, height) × 0.5 × 0.625` (about 112 dp) with a 10 dp inset. Both use explicit-extent asset presets that decode at the drawn size at device pixel ratio, one cache entry per step. |
| Playback | Custom emoji animate and loop. The single unicode sticker animates once, `autoplay` decided by a host-held played-once memory per chat screen (per-chat controllers, [ADR 029](029-host-integration.md)), not by the cache; a tap replays through the binding. Unicode items in the text layout are glyphs at the step font; a host with the animated pack may opt in through the same resolver. |
| Chrome | Stays host-side as for every body: time pill over the body's bottom-right, reactions below, reply or forward header beside the sticker layout and above the text layout. |
| Selection and taps | No text selection: `ChatEmojiBody` registers with the selection controller as a non-text body, so a long-press is message selection or the menu under the selection policy ([ADR 012](012-cross-platform-selection-policies.md)). Copy is the message's `RichText` through the existing message Copy. A custom emoji tap is `ChatInlineHit.embed`; the single sticker's tap is `ChatInlineHit.sticker`, and the body replays the animation itself. |
| Composer | Unchanged, with no preview. An emoji-only draft is not trimmed on send, so a multi-line arrangement survives. |
| Seam | `ChatEmojiBody` is a second viewport-provided body beside the markdown body; both register with the selection controller, one as a text body and one not. That registration kind is the whole seam for later media bodies: no new abstraction. |
| Out of scope | The tap overlay effect (larger animation, peer interaction, haptics) is a host feature over `ChatInlineHit.sticker`. Sticker and GIF message bodies are not designed here; the sticker layout of `ChatEmojiBody` seeds the sticker body, which it delegates to when that lands. |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Classifying in the markdown body over the parsed document | The body has neither the no-media fact nor the permission; it would classify per mount instead of per message |
| Two body widgets now (sticker, text) | The sticker body's owner is the media effort; one widget with two layouts seeds it |
| Android's first-frame stills for unicode in the text layout | iOS and Desktop draw glyphs; glyphs need no decode |
| A count cap on emoji | Sizes shrink instead; all clients accept long runs |

## Consequences

- A host that never calls the classifier shows every emoji-only message as an
  ordinary markdown body, which is correct but not parity.
- The size tables are Android's values traced from its source; a change in the
  reference is a change here, recorded with its reason.
