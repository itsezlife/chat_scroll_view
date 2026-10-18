# ADR 036: Emoji-only message presentation

A message whose text is only emoji is presented as the reference clients
present it: no bubble, enlarged, a single emoji as a sticker-sized animation.
The host classifies the body with a pure function in `content_model` and passes
the viewport a body kind; the viewport never re-detects.

**Status**: Accepted, amended for sticker playback and the tap-interaction seams, for per-platform presentation, for the size of a unicode emoji in a bubble and the configurable desktop cap, and for the message menu's scrim on a message without a bubble  
**Date**: 2026-10-18  
**Relates to**: [ADR 012](012-cross-platform-selection-policies.md), [ADR 021](021-content-identity-and-collections.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 029](029-host-integration.md)

## Context

All three reference clients reclassify a message after parsing: no media, text
of emoji and whitespace only, no entities except custom emoji, gated by a
default-on setting. A single emoji becomes a sticker-sized item (animated
pack emoji or custom emoji); several become enlarged text from fixed per-count
size tables, independent of the user's text size. There is no bubble; the time
and reactions sit on the body. Beyond that the three differ almost completely:
sizes, inset, count cap, where the time and the reply sit, what the time's
container looks like, what a right-to-left chat mirrors and how selection
shows. They are not two families (mobile and desktop) but three (Android, iOS,
desktop), so the platform is a strategy, not a flag; see the amendment below.

## Decided

| Concern | Decision |
| ------- | -------- |
| Classification | `EmojiOnlyText.of(RichText)` in `content_model` returns the ordered items (unicode sequence or document key) and line breaks, or null. The rule is Android's permissive one: emoji graphemes, whitespace and newlines only; the only entity allowed is inline content with a document key; any style, link, mention, quote or code block disqualifies; no count cap. The grapheme grammar is one scanner in `content_model`, not a second regular expression. Its one table is the set of basic-plane code points that start an emoji, carried as a constant inside `content_model`: see the exception below. |
| Who calls | The host, when it builds the message model. It adds the two facts only it has (the message carries no media, a link preview counting as media; the large-emoji setting and the chat's permission) and passes the result as a body kind. The viewport never classifies. |
| Body | One viewport body widget, `ChatEmojiBody`, with two layouts. **Sticker** when there is exactly one item and the host resolved it to a document (a host-owned unicode-to-document map for the animated pack, or the custom emoji's own document). **Text** otherwise. No bubble. |
| Platform | `ChatEmojiPolicy` (`$Android`, `$Ios`, `$Desktop`; web follows desktop), a pure-Dart strategy the host picks once from the platform (`ChatEmojiPolicy.forPlatform`). It owns the font tables, the sticker extent and inset, the count cap, the sticker-permission gate, the wrap under a header, where a header goes and whether a right-to-left chat mirrors. See the amendment below. |
| Sizes | Per platform, from the policy. Android's, as a value the host may override (`ChatEmojiSizes`): text layout font steps of 81.6, 55.2, 40.8, 33.6, 26.4, 22.8 dp by item count, one step larger when every item is a custom emoji; item box is the font plus 4 dp; text scale is ignored; newlines are honoured; sticker layout `min(viewport width, height) × 0.5 × 0.625` (112.5 dp on a 360 dp phone) with **no** inset. iOS: a 94 pt font scaled and floored by the longer of the longest line and the line count, a fixed 112 pt sticker in a 10 pt inset. Desktop: 38 px images 2 px apart, a fixed 112 px sticker, custom emoji lines of 112, 78 and 58 px by their larger dimension. All use explicit-extent asset presets that decode at the drawn size at device pixel ratio, one cache entry per step. |
| Playback | A host policy, `ChatStickerPlayback`, not a rule of the body: loop, play once then rest on the first or the last frame, or still. The reference default plays the single unicode sticker once and loops a custom emoji. A sticker that plays once does so the first time the open chat shows it, decided by a host-held `ChatStickerPlayLedger` (per chat controller, [ADR 029](029-host-integration.md)), not by the cache. Unicode items in the text layout are glyphs at the step font; a host with the animated pack may opt in through the same resolver. See the amendment below. |
| Chrome | Stays host-side as for every body, and is per platform: the host reads the body's geometry (`ChatEmojiBody.geometryFor`: the box, the text rectangle and trailing edge, the last line, the sticker's art rectangle, the strip the host reserved under the items) and places the time pill, reply or forward header and reactions by the platform's rules. Where each goes is in the amendment below; the reply is **above** the text and **beside** the sticker on Android only. |
| Selection and taps | No text selection: `ChatEmojiBody` registers with the selection controller as a non-text body, so a long-press is message selection or the menu under the selection policy ([ADR 012](012-cross-platform-selection-policies.md)). Copy is the message's `RichText` through the existing message Copy. A custom emoji tap is `ChatInlineHit.embed`; the single sticker's tap is `ChatInlineHit.sticker` on the drawn sticker only, the body replays the animation itself under a platform tap policy, and the host gets the tap as `ChatStickerActivated`. See the amendment below. |
| Composer | Unchanged, with no preview. An emoji-only draft is not trimmed on send, so a multi-line arrangement survives. |
| Seam | `ChatEmojiBody` is a second viewport-provided body beside the markdown body; both register with the selection controller, one as a text body and one not. That registration kind is the whole seam for later media bodies: no new abstraction. |
| Out of scope | The tap overlay effect (larger animation, peer interaction, haptics) is a host feature over `ChatInlineHit.sticker`; the seams it needs ship (amendment below), the effect does not. Sticker and GIF message bodies are not designed here; the sticker layout of `ChatEmojiBody` seeds the sticker body, which it delegates to when that lands. |

### Exception: the basic-plane emoji set lives in `content_model`

The classifier cannot read `emoji_data`'s catalogue, because `content_model`
is a leaf that depends on no workspace package ([ADR 020](020-package-topology.md)),
and it cannot move into `emoji_data`, because the host calls it where it
builds the message model, with no emoji catalogue loaded. So the set of
basic-plane emoji code points (`©`, `®` and `U+203C` to `U+3299`, the keys the
catalogue lists) is a constant in `content_model`, and the two copies are kept
in agreement by a test rather than by a dependency:
`packages/emoji_data/test/audit/emoji_only_agreement_test.dart` classifies
every catalogue key and every basic-plane symbol in the window through
`EmojiOnlyText.of` and fails when the set and the catalogue disagree in either
direction. A change of the
catalogue's Unicode version re-runs that test; the constant is updated with it.

## Amendment: per-platform presentation and chrome

The first decision treated the three clients as one, with Android's numbers.
They are not one, and two of its statements were Android's alone: the reply is
above the text layout and beside the sticker layout **on Android only** (iOS
puts it beside both, at the screen edge away from the message; desktop puts it
beside when the row holds both and above otherwise), and an enlarged run has no
count cap **except on desktop**, where more than three regular emoji is an
ordinary bubble (custom emoji lines are not capped). The decision is replaced
by the following.

### The body's surface

`ChatEmojiBody` takes a `ChatEmojiPolicy` (Android's by default), a
`parentWidth` (the share a header's wrap is of; the viewport's width by
default) and a `bottomReserve`. `ChatEmojiBody.geometryFor` returns the same
`ChatEmojiGeometry` the widget lays out to, so a host places chrome before the
body is built and the two cannot disagree. The sticker's inset is the policy's,
not a constant of the sizes: none on Android and desktop, 10 pt on iOS. The
wrap under a header is the policy's rule too: Android caps it at 65 % of the
**parent** width (not of the row's maximum), iOS takes 45 pt off the row's
width, desktop narrows nothing. A platform that does not mirror (Android, iOS)
lays the lines out left to right in a right-to-left chat; desktop mirrors.

### What each platform does

| Concern | Android | iOS | Desktop |
| ------- | ------- | --- | ------- |
| Large emoji gated by the chat's sticker permission | yes: the whole feature is off in a chat that bans stickers | no | no |
| Count cap | none | none | 3 regular emoji by default, the host's to move (see the amendment below); more is a bubble |
| Time pill, text layout | in a strip under the emoji (3 dp below them, 17 dp high, 3 dp under it), 1 dp (incoming) or 4 dp (outgoing) inside the text's end | in a strip under the text, 4 pt inside its end and bottom (20 pt strip) | beside the content, bottom-aligned (incoming); under it (outgoing) |
| Time pill, sticker layout | over the art, `[-7, +10]` of its bottom edge, 5 dp inside its end | 4 pt inside the frame, so 6 pt outside the art | beside the sticker (incoming); over its bottom-end corner (outgoing) |
| Time pill shown | always | always | on hover, as the last own message, while sending or failed; an outgoing large emoji always |
| Pill shape | 17 dp, radius 12, 6 dp padding, 12 dp text, 60 % of the service alpha | fully rounded, 17 pt, 7 pt padding, 11 pt text | radius about 6, 8 x 2 padding, 13 px text |
| Ticks | 12 x 12 checks 4.8 dp apart, clock, error square | 11 x 9 vector checks 6 pt apart, clock | Android's glyphs in a 24 px status space |
| Edited | one string, `edited 09:05`, part of the pill's width | the same | the same |
| Reply or forward | above the text, left-aligned to its box for either sender; beside the sticker, an incoming one 18 dp from it, an outgoing one pinned 16 dp from the row's left edge | beside both layouts, pinned to the edge away from the message | beside when the row holds both, else above |
| Header panel | service colour at full alpha, radius 4 (6 for a forward with a reply), 14 dp text, a 3 dp bar | the same fill, radius 4, 14 pt, a 3 pt bar | service colour, radius about 6, 13 px |
| Reactions | 26 dp chips under the pill, outgoing right-aligned | under the frame, 4 pt gap | under the element |
| Mirrors in a right-to-left chat | no | no | yes, wholly |
| Selection | the viewport's whole-row tint; nothing of the body's own | a checkbox only | the glyphs are recoloured |

The service colour behind pill and panels derives from the chat's wallpaper
(Android: the wallpaper darkened in HSV at alpha `0x66`, the pill at 60 % of it;
iOS: black at 0.2 over a wallpaper, `#748391` at 0.45 over none; desktop's
palette is not known, so Android's derivation). The host supplies the wallpaper
colour; a host without one gets a documented default (`#748391`), so the colour
is a platform derivation of a plausible wallpaper, never a fixed black.

### Divergences from the reference, with their reasons

Every value the sources at hand did not give is a single named constant that
takes the nearest verified platform's value. None is silently chosen.

| Divergence | Value taken | Why |
| ---------- | ----------- | --- |
| Android clock size (`EmojiChrome$Android.unverifiedClockSize`) | 12 dp | the clock drawable's intrinsic size was not traced; the check's size |
| Android check and eye glyphs | paths traced by eye from the 3x bitmaps | the app ships no bitmap; a path at the bitmap's size and stroke |
| iOS pill height (`unverifiedPillHeight`) | 17 pt | the date line's height is a font metric; 11 pt text plus 2 + 2 |
| iOS reply and forward panel height (`unverifiedHeaderHeight`, `unverifiedForwardHeight`) | 40 and 44 pt | the nodes' line heights are font metrics |
| iOS views icon and its text gap (`unverifiedViewsIconHeight`, `unverifiedViewsSpace`) | 9 pt high, 4 pt | the bundle icon was not read |
| iOS item box | font + 4 | the glyph line's height is a font metric; the preset's box padding |
| iOS clock position | centred in the pill | the sources give an offset in a frame not traced |
| Desktop pill radius (`unverifiedRadius`) | 6 px | `roundRadiusLarge` is in a library absent from the sources |
| Desktop tick size, gap, inset (`unverifiedTickSize`, `unverifiedTickGap`, `unverifiedStatusInset`) | 12 px, 4.8, 8 | the sprites' sizes are absent; Android's |
| Desktop views icon and gap | 12 px wide, 8 | the icon is part of a 20 px block; its split is not given |
| Desktop 6-7 and 8+ custom emoji (`unverifiedLargeCustomBox`, `unverifiedNormalCustomBox`) | 38 and 26.8 px | the emoji-size table is absent; the isolated size, and Android's smallest box |
| Desktop reactions gap (`unverifiedReactionsGap`) | 4 px | the message widget's own spacing is not in the sources; iOS's |
| Desktop palette | Android's derivation | `msgServiceBg`, `msgServiceFg` and the selection overlay are in resources that are absent |
| Desktop image box | font 34 in a 38 px box | the reference draws pre-rendered 36 px images with a 1 px outline; this draws a glyph or an asset in the box |
| Reaction chip internals | 8 padding, 16 emoji, 4 gap | only the chip's height (26) and gap (4) were traced |
| Wallpaper default | `#748391` | the demo has no wallpaper; the iOS built-in wallpaper's tint is the one neutral colour the sources give |
| Row margins | the host's list padding | the clients' 9 dp / 9 pt / 16 px outer margins are the list's, not the chrome's; a pinned header is placed in the row frame |
| Time text position | centred in the pill | the reference derives it from a font's line height |
| Jump highlight | the viewport's | each client highlights differently; it is not the body's |
| Reply preview width | what the row leaves less the panel's padding | the reference's per-layout formulas depend on the screen's displayed size |

Not modelled: the share button and the avatar column's offsets (the host's
row), a tablet's size rule, desktop's wide-chat mode (outgoing on the left),
and a failed message's error beside the node on iOS.

## Amendment: a unicode emoji in a bubble, and the desktop cap

Reported on desktop: in an ordinary bubble (the five-emoji message, the
eleven-emoji message with a word) regular emoji look "weirdly small", and the
sizes differ inside one message.

### Root cause

A unicode emoji in a markdown body is text, and a colour emoji font draws its
glyph into a square of the **font size**: 15 px text, 15 px emoji (the picture
inside it is about 0.93 of that). The references do not. Android sets an emoji
span to the font's **height**, `ascent + descent` (`Emoji.EmojiSpan`, about 1.18
times the size for SF), and a custom emoji to 1.2 times that
(`AnimatedEmojiSpan`); the fork's inline embeds already followed the second rule
(`MarkdownInlineEmbedMetrics.extentScale`). So a unicode emoji was 0.85 of the
height Android gives it and 0.71 of the custom emoji beside it: the "small",
and the two sizes of one message (the unicode glyphs of the screenshot beside
the custom emoji of the showcase message). The layer that owns it is the span
builder of the fork, which turns text into `TextSpan`s; the font size cannot
be corrected from outside it.

### Decided

| Concern | Decision |
| ------- | -------- |
| Where | The fork's `MarkdownThemeData.emojiRuns` (a host scanner) and `emojiScale`: each range is a child span whose font size makes the glyph `emojiScale` times the font's height, with the text's line height. The text, its offsets, selection, spoiler ranges and recognizers are unchanged; with no scanner nothing changes. The fork knows no emoji table. |
| The scanner | `EmojiRuns.of(text)` in `content_model`: the grammar of `EmojiOnlyText` (one scanner, no second regular expression), restricted to what the platform draws in colour: a code point of `U+1F000` or above, a keycap, a presentation selector, a ZWJ, or a BMP base the standard draws as an emoji by default (`Emoji_Presentation`, a constant in `content_model` beside the other table). A heart, a copyright sign or a digit with no selector is a text glyph and stays at the font size. |
| Who applies it | `ChatMarkdownBody` sets it on the theme it resolves unless the host's theme has its own `emojiRuns` (`(_) => const []` turns it off). The classification of a message (emoji-only) stays the host's; this is paint. |
| The scale | `ChatEmojiPolicy.inTextEmojiScale`, read by the host into `MarkdownThemeData.emojiScale`: 1 on Android (the verified rule), 1 on iOS (not traced; Android's, the authority where iOS is silent), 1.2 on desktop (the same box as a custom emoji, so one message holds one size). |
| Line height | Pinned to the text's: the run's `height` is the text's line over the glyph's size. What is left is what an emoji at the font size always did: the emoji font splits the line with a deeper descent than the text's, so a line that holds one is up to a pixel taller than a line of text alone. |
| The desktop cap | `ChatEmojiPolicy.desktop(regularLimit:)`, default 3 (the reference's), asserted at least 1; `ChatEmojiPolicy.forPlatform(desktopRegularLimit:)` hands it to the desktop family and the web, and Android and iOS, which have no cap, ignore it. The cap counts every item of a message that is not all custom emoji, as before; custom-only lines are never capped. The example keeps it in `LargeEmojiSetting.desktopLimit`, a record of its own, and offers steps of it in a menu next to the large-emoji toggle on desktop only. `ChatEmojiPolicy$Desktop.regularLimit` is now the instance's cap and the 3 is `defaultRegularLimit`. |
| Mixed rows | Four or more regular emoji on desktop are an ordinary text bubble (the reference's rule above the cap), and their emoji are the in-text rule of this amendment, not the emoji-only tables. A row of unicode and custom emoji counts as regular (it is not all custom). |

### Divergences from the reference, with their reasons

| Divergence | Value taken | Why |
| ---------- | ----------- | --- |
| Desktop's in-text emoji size | 1.2 times the font's height, the custom emoji's box | `lib_ui` (its `emojiSize`, `AdjustCustomEmojiSize` and the text emoji padding) is absent from the checkout; 18 px at the 13 px message font is the remembered figure (1.38 times), and 1.2 times the 15 px bubble font is 1.41, so the choice is consistent with it, unverified |
| iOS in-text emoji size | Android's | not traced |
| The gap between two emoji of a line | The platform font's advance | Apple Color Emoji advances about 1.25 em on the platform's text system, with the picture about 0.93 em inside it; `flutter test` lays the same font out at 1.0 em, so a test cannot pin the gap and none does. The pictures are enlarged; the gap grows with them and is not tightened |
| Sizes in `flutter test` | Measured with the real macOS fonts | Ahem draws every glyph as a square of the font size, which is exactly what hid the bug; the measurement test and the goldens load Apple Color Emoji and SF and are skipped where the files are missing |

## Amendment: sticker playback, replay and the interaction seams

Decided from the three reference clients' source (Android is the authority;
iOS and Desktop where they differ).

> **Open question for the product owner: does a tap near the sticker replay it?**
> The product belief is that on mobile a tap *near* (not exactly on) the
> sticker replays it, and on desktop it does not. The source does not support
> it: all three clients require a hit inside the drawn sticker rectangle, and
> no touch slop was found on Android. The default therefore follows the
> source: `ChatStickerTapPolicy.replayTapSlop` is 0 on both strategies. The
> belief can be enabled by changing one value, for example
> `ChatStickerTapPolicy.mobile(replayTapSlop: 12)` passed as
> `ChatEmojiBody.tapPolicy`; the slop widens the one hit that is also the
> interaction, so a tap in it is a `ChatStickerActivated` too. Both strategies
> have a test of the mechanism. Nobody has measured a device: confirm the
> claim on a phone before turning it on.

| Concern | Decision |
| ------- | -------- |
| What loops | The host's `ChatStickerPlayback`, never hard-coded: `loop`, `onceThenFirstFrame`, `onceThenLastFrame`, `still`. `ChatStickerPlayback.defaultFor` is the reference rule (a single unicode emoji plays once and rests, a custom emoji loops); ordinary animated stickers loop, which is the same `loop` for the sticker body that delegates later. The body reads no animation setting; the host maps its settings and power policy to a mode. |
| Rest frame | A value of the mode (`AssetProfile.restFrame`): the first frame on Android and Desktop, the last on iOS (its player is not in the checked source, so unverified). Default first. |
| Play once, remembered | A host-owned `ChatStickerPlayLedger` (`hasPlayed` / `markPlayed` by message id), scoped to the open chat and not persisted, as all three clients keep it. The body asks when it mounts, keeps the answer for that mount and records when the animation is *playing* (Android marks at the first drawn frame, not at the end; here it is the moment the binding starts advancing, at most a frame earlier). Nothing is stored in the body or the cache, so a recycled row mounts again and rests. An edit-morph twin neither plays nor records. |
| Playback in `catalog_assets` | `AssetProfile.loop` is honoured: a paint that does not loop plays one pass and holds the rest frame (`AssetPaintable.isHolding`, `restart`), and the binding reports `AssetPlayback.ended` on the next playback tick and then costs no ticks. `AssetBinding.replay()` returns whether it started a pass: false while a pass runs or loops (a pass is never rewound, as on all three clients), when hidden or detached, and when nothing animates yet. A profile that does not animate holds its first frame until a replay. The picture is never recorded per frame: the paintable still derives its frame from the shared clock at paint. The body reaches this through `PlayableEmbed` (`ContentEmbed` is one); an embed that is not playable cannot replay. |
| Visibility | `ChatEmojiBody.isActive`, one host input (row visibility, app lifecycle, route focus, power policy). An inactive row's embeds are hidden and cost no ticks, it exposes no sticker rectangle, cannot replay and drops a remote interaction. The clock's pause layers (low power, fast scroll, hidden surface) hold a pass where it is. Android's freeze below a quarter visible is the host's to feed through this input. |
| Hit area | The drawn sticker rectangle, not the 10 dp inset around it, outset by `replayTapSlop` (0). A tap beside it, inside the message cell, is an ordinary message tap on all three clients. |
| Tap policy | `ChatStickerTapPolicy`, a pure `$Mobile` / `$Desktop` strategy that follows the selection policy. Tap on a hit: replay (if not playing) on both. Long press: mobile replays (Android restarts a non-looping sticker when its menu opens; iOS is read to open the menu only, so `replaysOnLongPress` is a parameter), desktop has none. |
| Interaction event | `ChatStickerActivated` is emitted for every tap on a hit, playing or not, distinct from the replay, with the emoji (`content`, `isCustomEmoji`), the message id, the sticker rectangle in global coordinates and `tapTime` on the facade's injected monotonic clock (`ChatSelectionController.monotonicClock`). A long press is told too (`gesture`), carries no effect, and is not told while message selection suppresses inline activations. Whether the message is the user's is the host's own fact. |
| Host seams | By message id on the facade: `stickerRectOf` (the live place to draw over, null for a row that shows no sticker), `replaySticker`, and `playRemoteInteraction`, the incoming-side entry point: it restarts the sticker and returns where to draw (or null to drop the interaction and send no acknowledgement, as every client does for a hidden row). The body does not draw the effect: it is three times the sticker and crosses neighbouring rows. |
| Host-owned, not built | The effect and its overlay; the animation index (a random source the host injects); the wire (`messages.setTyping` with `sendMessageEmojiInteraction(emoticon, msg_id, {"v":1,"a":[{"i":n,"t":seconds}]})` and the `...Seen` acknowledgement); batching; caps on concurrent effects; haptics and sound; the hint; the gates (a private chat, not Saved Messages, not secret, sent); the persisted "effect played" flag of Android's automatic effect. |
| Example stub | `StickerInteractionStub` batches taps with the values the host owns, a 500 ms debounce after the last tap and a 1.0 s window from the first, and shows the `{"v":1,"a":[...]}` it would send. The window is not Android's open-ended debounce: Desktop discards an incoming entry whose offset is outside `[0, 1]` s or not strictly greater than the one before, so closing a batch at 1.0 s keeps every offset acceptable to Desktop, and taps in the same instant are one. A tap on another message sends the pending batch at once. Clock, random source and timer are injected for its tests. |

### Divergences from the reference clients

| Reference | Here | Why |
| --------- | ---- | --- |
| Android marks "played" at the first drawn frame | When the binding starts advancing, observed on the embed's signal | A paint must not call out; the difference is a frame, and a row scrolled past before either is not recorded |
| Each surface has its own player | Surfaces that share an entry (same content, same spec) share one playback and replay together | One decode per entry is the cache's design; two identical emoji-only messages visible at once are the only case, and they replay in step. A looping and a non-looping surface of one entry follow the last paint |
| Frame-indexed haptics, sound, the 3x effect, the seen acknowledgement, the hint | Not built | The ticket ships the seams; each is a host feature |
| Rest on the last frame (iOS) for a sticker that has not played in this entry | Shows the first frame | Reaching the last frame of a sequence decoded one frame at a time costs decoding all before it; only a pass that was played rests on the last |
| Android: a rejected tap (12 concurrent, 4 per message) is not counted in the batch | Every tap on an emoji with an effect is counted | The caps belong to the effect, which the host owns |

### Not verified (carried from the research)

- iOS `AnimatedStickerNode`: whether `.still(.end)` is the last frame, and the order of the `started` callback against the seen set. `onceThenLastFrame` is therefore a parameterised guess.
- Whether Android rebuilds its message objects (resetting its played map) on an edit, a reaction or a reload, so whether the ledger should forget on an edit.
- Android per-layer pauses beyond the activity and low-end scrolling; how the power-saver level is loaded.
- Desktop double click on a sticker and the exact reasons behind its paused state; Desktop's self-chat handling of an outgoing interaction.
- Whether a tap near the sticker replays on a real phone (the open question above).

## Amendment: the message menu's scrim on a message without a bubble

An emoji-only message has no bubble, so the mobile **message menu** sheet
([ADR 016](016-cross-platform-message-menu.md)) had no bubble outline to leave
undimmed. The example reported one rounded rectangle (radius 12) around the
whole chrome box (reply panel, items, pill, reactions), which lit the gaps
between the parts and read as a bubble that is not there. Decided from the
two mobile clients (Android is the authority); Desktop's menu is a popup with
no dim.

| Concern | Android | iOS | Here |
| ------- | ------- | --- | ---- |
| Dim colour and level | `scrimPaint` is a plain `new Paint()` (black), alpha `0.2` at most (`dimBehindView(view, true)` asks `0.2f`), `ChatActivity.java:4509`, `10578-10590`, `10633-10684` | `contextMenu.dimColor`: black at `0.6` (dark), `#000a26` at `0.2` (day), `DefaultDarkPresentationTheme.swift:767`, `DefaultDayPresentationTheme.swift:1044`; over a zoom blur of the chat (`ContextControllerImpl.swift:132-137`, `1266-1285`) | Android's: black, `0.2` on a dark scheme (the presenter's `scrimColor`); not changed |
| Fade | 320 ms, `EASE_OUT_QUINT`, `ChatActivity.java:10690-10691` | 0.2 s alpha (`ContextControllerImpl.swift:534`) | the presenter's linear 320 ms; not changed |
| Lifted or a hole | **Lifted**: the scrim rect covers the whole view, then the scrim cell is drawn again over it, clipped to the cell's own box and to the list's visible area, `ChatActivity.java:17649-17651`, `17805-17822` | **Lifted**: the message's node is taken out of the list above the blur (`ChatMessageContextControllerContentSource.swift:76-105`) | a hole in the dim over the live message; the pixels are the same, the dim is not repainted on the message |
| What stays bright | whatever the cell paints: no bubble is drawn for an emoji or a sticker (`MessageObject.java:11078`, `shouldDrawWithoutBackground`), so the art, the time pill, the reply panel and the reactions, each in its own shape; transparent pixels of the cell stay dimmed | the node's whole content (art, date and status, reply info, forward info), the same | the parts, each in its own shape, with square art |
| Time pill | part of the cell, so lifted | `dateAndStatusNode` is a subnode of the lifted node, so lifted | lifted when it is shown (Desktop's hidden pill is not) |
| Geometry of the lift | the cell's drawn pixels; no outline is added | `contextContentFrame` is the art frame, plus 20 pt under it for the text layout (`ChatMessageAnimatedStickerItemNode.swift:1568-1590`); it places the menu, the node itself is lifted whole | `ChatEmojiGeometry.content` (the items' area or the sticker's art, without the iOS inset and without the strip reserved for the pill) |
| Sticker restarts on open | `restartSticker(cell)` when the dim starts, `ChatActivity.java:10639`, `32916` | not found | not done: playback is the host's (see the playback amendment) |

`ChatMessageSurfaceParts` (a `ShapeBorder`, a union of rectangles each in an
outline of its own) is the seam: a body that has no outline passes it as the
`shape` of `ChatMessageSurfaceBounds`, and the presenter's hole follows it with
no new request field. It is root, not example, because every bubble-less body
(a sticker, a round video, an enlarged emoji run) needs the same thing. The
example's `emojiSurfaceParts` builds it from the chrome placement it already
has: the body's `content`, the header panel (the platform's radius), the pill
(its fully rounded or radius-12 shape) and each reaction chip.

| Divergence | Value taken | Why |
| ---------- | ----------- | --- |
| Square art | the art's rect has no corner radius | the clients draw the art's pixels; a glyph run or a sticker has no outline to round |
| Hole instead of lift | the dim is cut where the message is, not painted under a copy | the viewport paints under the route; the transparent pixels inside the art's rect are therefore lit, which the clients keep dimmed |
| Light scheme dim | `0.08` (the presenter's softening) | Android's `0.2` is a dark-chat value; unchanged by this amendment |
| No blur (iOS) | none | the sheet has no backdrop filter; Android's is a flat dim |

Not verified: Android's `ChatMessageCell` pill and reply paint for a
sticker-layout cell at scrim time were read as part of `child.draw`, not stepped
through; the iOS lift of the reply node was read from the subnode list, not from
a device; the exact day-theme dim is `#000a26` at 0.2 per the source above and
was not compared with a screenshot. Nothing was run on a device.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Classifying in the markdown body over the parsed document | The body has neither the no-media fact nor the permission; it would classify per mount instead of per message |
| Two body widgets now (sticker, text) | The sticker body's owner is the media effort; one widget with two layouts seeds it |
| Android's first-frame stills for unicode in the text layout | iOS and Desktop draw glyphs; glyphs need no decode |
| A count cap on emoji | Sizes shrink instead; all clients accept long runs |
| A `playOnce` boolean on the body, or the body reading the animation setting | The three clients disagree on the rest frame and on what loops; the body cannot know the user's setting, the host can |
| Remembering what played in the body or the cache | The body is recycled and the cache is shared by every chat; the memory is the open chat's |
| An ended callback that records "played" | The reference records at the start; recording at the end would replay a sticker the user scrolled past after one frame |
| A tap near the sticker replays, by default | No client does it; kept as one parameter instead (see the open question) |

## Consequences

- A host that never calls the classifier shows every emoji-only message as an
  ordinary markdown body, which is correct but not parity.
- The size tables are the platforms' values traced from their sources; a change
  in the reference is a change here, recorded with its reason.
- A host picks one `ChatEmojiPolicy` for the platform it runs and passes it to
  the body and to its chrome; mixing a policy of one platform with the chrome of
  another is a host error the types do not catch.
