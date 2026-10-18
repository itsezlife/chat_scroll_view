# ADR 037: Spoiler and mention inline styles

Mention and spoiler are first-class inline styles of the markdown engine, not
links with a host convention and not paint tricks. A mention is a style bit
with its own tap callback and its own inline hit; a spoiler hides glyphs
behind an animated particle fill, revealed per message.

**Status**: Accepted  
**Date**: 2026-10-18  
**Amended**: 2026-10-18 (chat-polish-3, ticket 10): the dust also holds while the window has no focus, behind a dialog and on low power, and goes on from its phase afterwards; no pause touches the reveal state (row *Fill*)  
**Amended**: 2026-10-18 (chat-polish-2, ticket 07): a text selection no longer reveals a spoiler; the selection is made, painted and copied with the spoiler still hidden (row *Selection*, and the *Reveal* row lost a sentence)  
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
| Hit kinds | `ChatInlineHit.resolvedMention` (a resolved user, carrying its id) and `ChatInlineHit.usernameMention` (a typed username, none), two variants so a username with an id cannot be built, and `ChatInlineHit.hashtag`, with the contour and touch origin of a link; cursor is the click cursor. This reverses the deferred "no separate hit kinds" option of [ADR 017](017-body-linkify-host-invoked.md). |
| Spellings | Unchanged on the wire: `||x||` for a spoiler, `[@name](mention:id)`, `[@name](username:name)`, `[#tag](hashtag:tag)`. |
| Spoiler state | A fork-owned `MarkdownSpoilerController` (a change notifier holding the revealed document ids and the reveal origin), passed to the markdown widget like the selection controller. The viewport creates one beside the selection controller, keyed by message id. Scope is the whole document, as every client does it; in memory only, never persisted; it survives remounts (virtualisation, edit-morph twins). There is no re-hide when a selection is dismissed. |
| Hidden paint | Glyph positions never move: span building takes `revealed`, and a hidden spoiler run gets a transparent colour with identical metrics, so the painter keeps one glyph picture per `(size, revealed)` and a reveal swaps pictures without layout. A live pass paints the fill over each hidden spoiler's range boxes. Embeds inside a hidden spoiler paint at opacity 0. |
| Reveal | A tap reveals with a circular clip of about 300 ms from the touch point: hidden picture outside the circle, revealed inside, embeds fading in with it. A selection does not reveal (row *Selection*). A tap on a link or embed inside a hidden spoiler reveals instead of activating. The tap that reveals is absorbed (below). Copy keeps the spoiler entity; the plain text carries its characters (row *Selection*). |
| Selection | A text selection over a hidden spoiler leaves it hidden, on both **selection policies**: select all, a drag from or across it, a long-press word on it. Nothing in the viewport calls `spoilers.reveal` for a selection, and a tap, a click and the host's own `reveal` remain the ways to reveal. The fork draws the selection tint under the glyph picture and the dust fill over it (`MarkdownRenderObject.paint`, pinned by the fork's `spoiler_selection_test.dart`), so a selected hidden spoiler shows the tint through the particles, never its letters. **Copy**: the structured content the host's `copyWriter` receives keeps the spoiler style bit of the selected span; the host puts `EntityKind.spoiler` on the clipboard (HTML `<tg-spoiler>`, markdown `\|\|x\|\|`; both codecs already carry it) and a paste into the composer is a spoiler there, sent as `\|\|x\|\|`. The plain text (`ChatTextCopy.plainText`, the clipboard's plain form) carries the characters under the spoiler, hidden or not, as every reference client's does; the plain form is what another app without a rich paste receives, and a hidden spoiler is not a secret from someone who selected it. The reference clients differ (table below). |
| Absorb | The engine reveals on pointer up, before the viewport's tap recognizer fires, and a hidden spoiler is no inline hit, so the same tap used to fall through to the idle message tap. The selection pointer now notes at pointer down whether the message's spoilers were hidden and, when its tap lands and they are revealed, drops the idle message tap. It reads the reveal rather than the spoiler's geometry, so the engine stays the one place that decides slop, button and hit area. Only the idle message tap is absorbed: a tap while **message selection** is live still toggles the row (and reveals nothing, see Selection mode) and one that dismisses a text selection still dismisses it. A long press (message selection or the long-press menu), a drag (scroll or text selection) and a secondary click (the host's context menu) are not taps, so none is absorbed and none reveals. The reference clients agree: a tap on a hidden spoiler is consumed by the spoiler, a long press goes to the message menu. |
| Selection mode | Android takes no spoiler touch while the chat is selecting (`ChatMessageCell.checkSpoilersMotionEvent` stops at `canPerformActions()`), so there a tap toggles the row and the spoiler stays hidden. The engine's `MarkdownSpoilerController.tapReveals` is that switch: while false a tap is still absorbed but reveals nothing. The facade keeps it equal to `isSelectionMode` (committed message selection or a live drag-selection preview) at the one place every membership change passes through, before listeners are told, because the engine reads it on the pointer up and the toggle follows in the same event. The write is not left to the host: the rule is the policy's, and a host that also set it would fight the facade. Leaving the mode brings the reveal back at once. A selected row's body stays hittable on mobile ([ADR 015](015-per-body-scope-owns-continuous-text-gestures.md)) and every desktop row does, so both reach the engine and need the switch; an unselected mobile row ignores pointers and never did. |
| Hold time | A press held past `MarkdownSpoilerController.tapTimeout` is a long press, which belongs to the viewport's gesture (the message menu, a message selection), and its release reveals nothing. The default is `kLongPressTimeout`, 500 ms, where Android and Qt touch start a long press; Telegram iOS starts it at 0.3 s and a host that follows it lowers the value. A desktop host whose pointer is a mouse sets it to null: a mouse click has no hold limit. The window is measured on the pointer events' own timestamps, so a stalled frame does not turn a tap into a long press. The setting is the host's through `ChatSelectionController.spoilers`, with no option of its own on the facade: it is one assignment, the policy cannot tell a mouse from a touch screen on a hybrid device, and the engine already reads it when the pointer comes up. |
| Fill | The reference clients' live particle tile: one 128 dp tile of particles re-rendered on each 30 fps tick (`Picture.toImageSync`, no decode, no async gap) and sampled by every hidden spoiler through a repeating `ImageShader` with a per-spoiler offset, clipped to a 3 dp rounded rect. Density about 0.09 particles per dp²; round points of 1.2 dp (alphas 0.3 and 0.6) and 1.4 dp (alpha 1.0), in the text colour; speed 4 to 10 dp/s in random directions, life 1 to 3 s, respawning uniformly in the tile. The tick comes from the asset cache's shared clock ([ADR 022](022-asset-cache-and-media-pipeline.md)) and pauses when no hidden spoiler is on screen and under every pause layer of that clock: the window without focus, minimised, a dialog over the chat, low power. The dust is told the time it ran, not the time that passed: a pause is cut out, so it goes on from its phase (the reference client's spoiler animation does the same), and a pause never changes which spoilers are revealed. The reference client also re-hides revealed spoilers on a jump to a message in the same section; that is not replicated. With motion off the tile is rendered once and never re-rendered. Where `toImageSync` is unsupported the static tile stands in. |
| Tokens | Spoiler colour and particle motion are `chrome_foundation` tokens; the host wires them. |

### Reference clients on a selection over a hidden spoiler

| Client | Reveal | Selection paint | Copy |
| ------ | ------ | --------------- | ---- |
| Android (`TextSelectionHelper`, `ChatMessageCell.drawMessageText`) | None: the helper has no spoiler path. | Highlight path is drawn first, then the text and `SpoilerEffect.renderWithRipple`: tint under the dust. | `ClipData.newHtmlText(plain, CustomHtml.toHtml(spanned))`: the plain text holds the characters, the HTML wraps them in `<spoiler>`. Pasting into the input (`EditTextCaption`, `CopyUtilities.fromHTML`) restores the spoiler. |
| Desktop (`HistoryInner`, `HistoryView::Element`) | None found: the only reveal is a click (`setSpoilerLinkFilter`) and spoilers hide again with `hideSpoilers`. The text engine (`lib_ui`) is not in the sparse checkout, so its paint order and copy format are not read here. | Not read. | Not read. |
| iOS (`ChatMessageTextBubbleContentNode`) | Yes: `updateRange` reveals (`updateDisplayContentsUnderSpoilers`) when the range intersects a spoiler, and the end of the selection hides again. | After the reveal the text shows. | The selected string. |

Android is the authority (see [AGENTS.md](../../AGENTS.md)) and the user's
report matches it and Desktop, so the rule follows them. iOS is the one
divergence: a host that wants iOS's rule reads the selection from
`onInteraction` and calls `spoilers.reveal` itself; there is no policy switch,
because the viewport has no iOS selection policy to hang it on.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| `link` and `mention` set together | Every existing link branch fires first and hosts go back to string-sniffing |
| Deriving the mention in the viewport from the URL | The engine would keep painting mentions as links for hosts that are not chat |
| Reveal state in widget state | Lost on remount |
| Reveal state inside the selection controller | Two concerns in one controller |
| A selection that enters a spoiler reveals it (the previous rule) | Only iOS does it. Android and Desktop select the hidden text and keep the particles, and the copy carries the spoiler as a style, so there is nothing a reveal protects |
| Copying the plain text with the spoiler's characters replaced | Not what any reference client does, and a paste into an app with no rich form would lose the text |
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
