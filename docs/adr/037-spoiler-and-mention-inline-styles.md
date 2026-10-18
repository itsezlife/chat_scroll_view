# ADR 037: Spoiler and mention inline styles

Mention and spoiler are first-class inline styles of the markdown engine, not
links with a host convention and not paint tricks. A mention is a style bit
with its own tap callback and its own inline hit; a spoiler hides glyphs
behind an animated particle fill, revealed per message.

**Status**: Accepted  
**Date**: 2026-10-18  
**Relates to**: [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 017](017-body-linkify-host-invoked.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 029](029-host-integration.md), [ADR 035](035-markdown-engine-fork.md)

## Context

All three reference clients draw mentions as coloured text and underline only
URLs. They reveal a spoiler for the whole message at once, play a particle
fill while it is hidden, and keep it static when animations are off. Before
this decision a mention reached the host as a link with a `mention:` scheme,
so every link branch of the engine fired first and hosts sniffed strings.

## Decided

| Concern | Decision |
| ------- | -------- |
| Mention bit | `MD$Style.mention`, exclusive with `link`. The parser sets it when a link destination's scheme is `mention`, `username` or `hashtag`; `extra` carries the id or name. It paints in the theme's mention colour without underline. The engine fires `onMentionTap` (not `onLinkTap`) with the scheme, id and name. Copy reads the bit, not the URL. |
| Hit kinds | `ChatInlineHit.mention` (a resolved user or a typed username, the hit saying which) and `ChatInlineHit.hashtag`, with the contour and touch origin of a link; cursor is the click cursor. This reverses the deferred "no separate hit kinds" option of [ADR 017](017-body-linkify-host-invoked.md). |
| Spellings | Unchanged on the wire: `||x||` for a spoiler, `[@name](mention:id)`, `[@name](username:name)`, `[#tag](hashtag:tag)`. |
| Spoiler state | A fork-owned `MarkdownSpoilerController` (a change notifier holding the revealed document ids and the reveal origin), passed to the markdown widget like the selection controller. The viewport creates one beside the selection controller, keyed by message id. Scope is the whole document, as every client does it; in memory only, never persisted; it survives remounts (virtualisation, edit-morph twins). There is no re-hide when a selection is dismissed. |
| Hidden paint | Glyph positions never move: span building takes `revealed`, and a hidden spoiler run gets a transparent colour with identical metrics, so the painter keeps one glyph picture per `(size, revealed)` and a reveal swaps pictures without layout. A live pass paints the fill over each hidden spoiler's range boxes. Embeds inside a hidden spoiler paint at opacity 0. |
| Reveal | A tap reveals with a circular clip of about 300 ms from the touch point: hidden picture outside the circle, revealed inside, embeds fading in with it. A selection that enters a hidden spoiler reveals the document. A tap on a link or embed inside a hidden spoiler reveals instead of activating. Copy keeps the spoiler entity; the plain text copies revealed. |
| Fill | The reference clients' live particle tile: one 128 dp tile of particles re-rendered on each 30 fps tick (`Picture.toImageSync`, no decode, no async gap) and sampled by every hidden spoiler through a repeating `ImageShader` with a per-spoiler offset, clipped to a 3 dp rounded rect. Density about 0.09 particles per dp²; round points of 1.2 dp (alphas 0.3 and 0.6) and 1.4 dp (alpha 1.0), in the text colour; speed 4 to 10 dp/s in random directions, life 1 to 3 s, respawning uniformly in the tile. The tick comes from the asset cache's shared clock ([ADR 022](022-asset-cache-and-media-pipeline.md)) and pauses when no hidden spoiler is on screen. With motion off the tile is rendered once and never re-rendered. Where `toImageSync` is unsupported the static tile stands in. |
| Tokens | Spoiler colour and particle motion are `chrome_foundation` tokens; the host wires them. |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| `link` and `mention` set together | Every existing link branch fires first and hosts go back to string-sniffing |
| Deriving the mention in the viewport from the URL | The engine would keep painting mentions as links for hosts that are not chat |
| Reveal state in widget state | Lost on remount |
| Reveal state inside the selection controller | Two concerns in one controller |
| A fragment shader with procedural particles | Reads as procedural; summed falloffs merge dots into blobs about twice the reference point size |
| Per-spoiler particle systems (the reference's own entity effect) | Cost scales per spoiler: two to three times the raster time of a shared tile at 60 spoilers |
| A pre-rendered atlas of tile frames | Shows nothing while it renders on a switch and weighs 16 to 35 MB at common densities |

## Consequences

- A message with spoilers adds one live repaint pass while hidden spoilers are
  on screen; with none, nothing paints per frame.
- Reveal is per document: two spoilers in one message reveal together, and a
  quote of the same message shares the state.
- The fill's raster cost on web and low-end devices is an acceptance
  measurement of the work that lands it, not a settled number.
