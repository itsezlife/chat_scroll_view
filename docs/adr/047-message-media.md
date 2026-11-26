# ADR 047: Message media

A message can carry photos, videos, GIFs, files and a link preview. A new
portable package, `message_media`, draws them. Its unit is the **media
item** (an id unique in its chat, a content descriptor, a kind and a spoiler
flag; a `content_model` value),
and everything it does takes a list of items without knowing whether they
came from one message or, later, from several. A per-platform **message
media policy** lays a list out into blocks (mosaic, file stack, link preview)
in pure Dart, then paints them through replaceable cell and chrome builders.
The caption stays the message's markdown body, owned by the viewport's text
selection. Media gestures reach the viewport through one media-agnostic
**body part hit**, so message selection keeps its rules and the viewport
stays unaware of media. Layout changes interpolate between two **media
layouts** keyed by item. The link preview's model, its message-level
options and a host resolver seam live in `content_model`; the card is a
layout block.

**Status**: Accepted (2026-11-26, maintainer; decided in the
message-media-transfers map, tickets 07, 08, 13, 17, the card parts of 22,
ticket 24's conflict answers and the acceptance pass)  
**Date**: 2026-11-26  
**Relates to**: [ADR 012](012-cross-platform-selection-policies.md) (policy shape),
[ADR 013](013-viewport-owns-markdown-text-selection.md) (the caption's text selection),
[ADR 016](016-cross-platform-message-menu.md) (the message menu request),
[ADR 020](020-package-topology.md) (amended: `message_media`),
[ADR 021](021-content-identity-and-collections.md) (content descriptor),
[ADR 023](023-data-layering-and-persistence.md) (amended: the resolver seam),
[ADR 027](027-foundation-theme-glass-motion.md) (`ChromeInk`, tokens),
[ADR 034](034-rich-text-wire-and-persistence.md) (amended: options in the message and the draft),
[ADR 046](046-media-picker.md) (attach kinds, send plan),
[ADR 049](049-chat-capabilities.md) (link preview availability, protection),
mpx ADR 0010 (loading stages, status control, badges)

Spec: `.scratch/message-media-display/spec.md`, with research and per-value
provenance in `.scratch/message-media-transfers/research/` (01, 02, 03, 15,
16, 17, 21).

## Context

The chat drew no message media. An earlier branch ported one reference
client's single-box clamp and album mosaic: photo and video only, layout
keyed by message, no fit mode, no text-side corners, no file rows, no link
preview. The reference clients agree on how media and selection arbitrate:
in message selection a tap on media toggles, a long press is always the
message's. They disagree on almost every value: box sizes and their
algorithm, crop against a blurred fit, corner radii by neighbour, how wide a
caption may make the media, chrome, and motion. Link previews had a stub
card in the example and no model or resolver.

## Decided

### Package and dependency direction

`message_media` holds display only. The viewport keeps no media knowledge;
its one addition is the body part hit. Transfers, the outbox and saving are
elsewhere (mpx ADR 0012, ADR 048, the media-save effort), so a display-only
host takes no transfer plugin.

```
message_media -> content_model, content_assets, chat_capabilities,
                 chrome_foundation, mpx_core (git), chat_scroll_view (root)
```

Cells draw through `content_assets`' `ContentAssetView`. Of the capabilities
the policy reads only protection, per message, for per-item menu entries and
the viewer's share and save.

The edge to the root package is allowed: message media is a chat body and
registers with the viewport's non-text body seam. A host without a chat
shows media through mpx's `AssetView` or `mpx_ui`. The root never depends
on `message_media`, so there is no cycle. `message_media` never depends on
`mpx_transfer` or `chat_composer`, and `chat_composer` never depends on
`message_media`.

### The media item

`MediaItem`, `MediaItemId` and `MediaItemKind` live in `content_model`, so
the outbox and the picker read them without `message_media`.

| Area | Decision |
| ---- | -------- |
| Item | `MediaItem` = `MediaItemId` + `ContentDescriptor` + `MediaItemKind` + `spoiler`. The id is stable and unique per chat, because item state is per chat. Hosts issue the ids of attachments; a link preview's media takes `MediaItemId.linkPreviewOf(messageId, slot)` with `slot` `photo` or `media`. A per-item caption may join later. |
| Descriptor facts | `ContentDescriptor` gains optional `fileName` and `mimeType`, read alike by the picker, save to library, the outbox and the file row. No parallel file-info type. |
| Kind | `MediaItemKind`: a `final class` with `photo`, `video`, `animation` (GIF, the name the attach kinds and the capabilities' media kinds use), `file` and `custom(tag)`, a stable `value` string, tolerant decoding. The host sets it (a photo sent as a file is a `file`); `fromDescriptor` gives a default; an unknown kind draws as a file row. |
| Grouped rows | Later grouped rows pass items from several messages, each `MediaItemId` being its message id. Layout, cells, status and hit-testing never read a message. |

### The message media policy

| Area | Decision |
| ---- | -------- |
| Shape | One `MessageMediaPolicy` with `android()`, `ios()`, `desktop()` and `platform()`, partially overridable. A host replaces only the layout step or only one builder. Defaults are each platform's reference values (spec §6, §7, §9.5, §12). |
| Layout step | Pure Dart. Items, available width, caption position and text presence give a `MediaLayout`: ordered blocks (`mosaic`, `fileStack`, `linkPreview`); a mixed list gives consecutive blocks. Each cell carries a rect, a fit mode (`crop`, `blurFit`, `cropIfVisible(fraction)`) and a neighbour per side (bubble edge, text, item, adjacent bubble). Box sizing is policy; the ported clamp is one platform's default. Files never join a mosaic. |
| Mosaic | A `mosaicAlgorithm` slot. The ported algorithm is the default on every platform until each platform's own algorithm lands. |
| Paint step | Corner radii from neighbours by policy rule, as numeric per-corner radii; a corner takes the bubble-edge radius only when both its sides touch the bubble edge, and the inner radius when either side touches text or another item; one cell builder per kind; chrome slots as replaceable builders: time pill (its rect only, the pill is host chrome), info badge, status control, spoiler, options affordance. The options affordance opens the message menu. |
| Caption | Not drawn by `message_media`. It returns blocks and a caption width policy (`widenMedia` or `wrapAtMedia`). The host composes the bubble, or uses the optional `MessageMediaBubbleLayout`, which places media and text with the message's `invertMedia` and reports text neighbours to the layout. `invertMedia` is one message-level flag: it puts the caption above media and a link preview card above the text. The time sits over media only when media is the bubble's bottom element. |
| State | `MessageMediaState`: one per chat, in a host scope above the list, `MediaItemId` to item state (spoiler revealed now, inline playback later). Headless, not persisted. Without a scope, state is cell-local. It takes `sendOrigin`, a one-shot `Rect? Function(MediaItemId)` function type declared in `message_media`; the host passes the outbox's `takeSendOrigin`, so neither package depends on the other (map 25 §5). |
| Web | The box size follows the web width class (ADR 027 amendment): a 340 set at `compact`, a 420 set at `medium` and `expanded`, recomputed on resize (map 25 §17). |

### Transitions

`MediaLayout` is a value whose cells are keyed by `MediaItemId`.
`MediaLayout.lerp(a, b, t)` interpolates rects and per-corner radii of cells
in both; fit mode and kind snap; cells only in `b` enter, cells only in `a`
exit at their last rect. A re-layout mid-flight starts from the current
frame. One clock per message drives the cells, the bubble size and the
caption. Timings are per-platform policy, and one platform has none. Reduce
motion collapses to the end state. The viewport needs nothing new: a row
reports an interpolated height per frame, as the message change transition
does.

### Gestures

| Area | Decision |
| ---- | -------- |
| Selection | Fixed on every platform: in message selection any tap on media (status control and link preview card included) toggles the message; long press is the message's; drag-select is list-level. |
| Engine seam | One variant, `ChatInlineHit.bodyPart(messageId, partId, role, rect)`. `partId` is opaque to the engine; `message_media` puts one of a sealed pair in it: `MediaHitPart(itemId, part)`, `part` being `content`, `status`, `spoiler` or `options` (for any media item, also inside a link preview card), or `LinkPreviewHitPart(messageId, zone)`, `zone` being `body` (site name included; opens the URL) or `button` (the card's action). `role` is `activate` (the body and the host decide) or `menu` (like a long press or secondary click: opens the message menu, toggles in selection). The message menu request carries the touched `partId` and hands it to the host, which adds per-item entries (or "Copy link" on a card). |
| Cell | Registers as a non-text body and answers `inlineHitAt`; no plain gesture detector owns taps. `message_media` maps its parts (content, status, spoiler, options) to roles and performs open, download, cancel and reveal itself. |
| Normal mode | Per-platform cell policy: where a tap cancels a loading item, double tap as over any bubble, a hidden spoiler takes the first tap, what a photo tap in a link card with text opens, and an enlarge button on such a photo (on by default on desktop). Inline autoplay is a host flag: animations play muted per the auto-download rules, video per the platform's rule. |
| Origin frame | The hit's rect is the item's global rect and the viewer's opening frame; an album opens the viewer with its ids and an index; fresh neighbour rects come back by id through mpx's origin-frame contract. |
| Cursor, hover | Click cursor over `activate` and `menu` parts on desktop, plain in selection; hover highlight is cell-local. |
| Web | Media gestures follow the web input class: hover behaviour with a mouse, tap behaviour with touch (map 25 §17). |
| Semantics, RTL | One node per item (kind, duration or size, progress while loading); status control and options are separate actions; in selection the node's action is the toggle. Mobile does not mirror media in right-to-left chats; desktop mirrors file rows. |

### Link preview

| Area | Decision |
| ---- | -------- |
| Model | `LinkPreview` in `content_model`: url, display url, an opaque type string (the policy takes a host set of small-media types), site name, title, rich-text description, author, optional photo and media descriptors, duration, a large-media hint. |
| Options | `LinkPreviewOptions` belong to the message: chosen url, `media` (`auto`, `small`, `large`), `removed`, and a dismissal state that stays in the composer's draft and is never sent. The card's place above or below the text is the message's `invertMedia`, not an option; the draft options overlay edits that message field. Wire and draft forms are the [ADR 034](034-rich-text-wire-and-persistence.md) amendment's. `auto` follows the platform default; never small without text; the switch is offered only when the page has a photo or video that can shrink. |
| Resolver | `LinkPreviewResolver.resolve(candidates)` in `content_model` returns a `ValueListenable<LinkPreviewState>` that starts `pending` and becomes `loaded` or `none`, following ADR 023's rule that state is a listenable value. It fits a backend that picks among all URLs and one that tries them in order ([ADR 023](023-data-layering-and-persistence.md) amendment). A client-side Open Graph resolver ships in the example only: fetching third-party pages leaks the user's address and follows redirects, so it is the host's choice. |
| Media | The page's photo or media is an ordinary media item drawn and transferred through the same path as message media. |
| Card | A `linkPreview` layout block on the quote / reply block tokens. Metrics, the width rule (`fillBudget`, `fitMedia`, `fitContent`), the appear transition, press feedback over `ChromeInk` (never on links or the action button) and the time's placement under a last-block card are policy. Pending draws nothing. Changes ride `MediaLayout.lerp`; a new page cross-fades. The card's non-media area is an `activate` body part hit (`LinkPreviewHitPart`); description links are text links; card text is not selectable by default. No instant-view loading state in this cut. |
| Composer | The example's watcher keeps detection and timing and gains every URL, the chosen URL, the options and the resolver's state. The header strip draws the same model and gains an open action that opens the draft options overlay. On send the options and the loaded page go into the payload. A message without link preview data shows no preview, unless a host flag resolves it at receive time. |
| Dismissal | `LinkPreviewDismissal`: `fieldUntilBigEdit`, `perUrl`, `untilNoLinks`, a default per platform, one pickable everywhere. |
| Availability | Read from the chat capabilities' `sending.linkPreviews` ([ADR 049](049-chat-capabilities.md)). Denied: no resolve, the page is dropped, strip and options hidden, the message sent `removed`. Receivers draw what arrived. |
| Draft options overlay | Its live preview is the real bubble from the host's bubble builder with the same policy; option changes ride `MediaLayout.lerp`. The chosen link's highlight (from the link hit's contour) and the pending spinner are an overlay layer above the bubble; the engine is untouched. |

## Why

- An item with its own id, rather than a message, is the one unit that
  serves a single message today and a grouped row later, and it is what both
  mobile references key their cells by.
- The platforms differ in values and in algorithm (box clamp, fit, corners,
  caption width, motion), so each is a policy default rather than a constant.
  A pure layout step makes every value a unit test.
- Leaving the caption to the markdown body keeps one owner for text
  selection, copy and spoilers.
- Arbitration through the non-text body seam gives every platform the
  reference's selection behaviour with one engine variant that knows no
  media, and a poll or a location can reuse it.
- Cells keyed by item let two layouts interpolate. Reporting an interpolated
  height is a seam the viewport already has.
- Previews come from a host or backend; a seam over a list of candidates
  covers both shapes the references use, and keeping the client fetch in the
  example leaves the privacy call to the host.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Layout keyed by message | A grouped row and a per-item cancel need item identity |
| A file-info type next to the descriptor | Two places for the same facts; picker, save and outbox read the descriptor |
| One box algorithm and constant radii for all platforms | Each platform's users expect their reference's geometry |
| `message_media` drawing the caption | A second text owner beside the viewport's text selection |
| A plain gesture detector in the media cell | It fights message selection; the non-text body seam already arbitrates stickers |
| A media-specific engine hit variant | Teaches the viewport media; an opaque part id serves any body part |
| A viewport change for media transitions | The row's interpolated height already moves neighbours |
| A second media path for link preview media | The references load, show and open it as message media |
| The Open Graph resolver in a package | Puts a privacy-relevant fetch behind a default |
| Link preview options in `chat_composer`'s menu | The references open a dedicated overlay with a live preview |
| Carrying the branch's grouped map, group row layout and placeholders | Grouped rows are a later effort; placeholders are the loading stages' |
| The media item in `message_media` | The outbox and the picker would depend on a display package to name an item |
| `invertMedia` inside the link preview options | One flag on the message places both the caption above media and the card above the text |
| The host adapting media hits into the engine's types, to avoid an edge to the root package | Message media is a chat body; a host without a chat uses mpx's views instead |

## Consequences

- `message_media` joins the root `workspace:` list; ADR 020 gains its row
  (amendment). Only the branch's geometry comes over, rewritten without
  reference citations.
- `content_model` gains `MediaItem`, `MediaItemId`, `MediaItemKind`,
  `fileName`, `mimeType`, the link preview model, options and resolver, with
  a fake and a contract suite.
- The iOS and desktop mosaics and the desktop box without dimensions land as
  their own issues, each starting from a trace of the reference.
- The root package gains `ChatInlineHit.bodyPart` and the menu request's
  `partId`; nothing else in the viewport changes.
- `chrome_foundation`'s `ChromeInk` gains a bounce and a scale press if it
  lacks them.
- The outbox (ADR 048) uses reserved pieces: upload state in cells, the
  per-item sent check (drawn on `AssetTransfer.sent`: the upload finished,
  publish not yet; map 25 §6), the iOS flight from the send origin through
  `MessageMediaState(sendOrigin:)`. The whole-row appearance is the host's,
  driven by the outbox's `isFreshOutgoing(id)` (ADR 048).
- Glossary: *Message media policy*, *Media layout*, *Body part hit*, *Draft
  options overlay* in the Chat Scroll glossary; *Media item*, *Link preview
  options*, *Link preview resolver* and the descriptor's file facts in the
  Content and Assets glossary.
