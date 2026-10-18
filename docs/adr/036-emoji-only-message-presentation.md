# ADR 036: Emoji-only message presentation

A message whose text is only emoji is presented as the reference clients
present it: no bubble, enlarged, a single emoji as a sticker-sized animation.
The host classifies the body with a pure function in `content_model` and passes
the viewport a body kind; the viewport never re-detects.

**Status**: Accepted, amended for sticker playback and the tap-interaction seams  
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
| Classification | `EmojiOnlyText.of(RichText)` in `content_model` returns the ordered items (unicode sequence or document key) and line breaks, or null. The rule is Android's permissive one: emoji graphemes, whitespace and newlines only; the only entity allowed is inline content with a document key; any style, link, mention, quote or code block disqualifies; no count cap. The grapheme grammar is one scanner in `content_model`, not a second regular expression. Its one table is the set of basic-plane code points that start an emoji, carried as a constant inside `content_model`: see the exception below. |
| Who calls | The host, when it builds the message model. It adds the two facts only it has (the message carries no media, a link preview counting as media; the large-emoji setting and the chat's permission) and passes the result as a body kind. The viewport never classifies. |
| Body | One viewport body widget, `ChatEmojiBody`, with two layouts. **Sticker** when there is exactly one item and the host resolved it to a document (a host-owned unicode-to-document map for the animated pack, or the custom emoji's own document). **Text** otherwise. No bubble. |
| Sizes | Android's tables, as a value the host may override. Text layout: font steps of 81.6, 55.2, 40.8, 33.6, 26.4, 22.8 dp by item count, one step larger when every item is a custom emoji; item box is the font plus 4 dp; text scale is ignored; newlines are honoured; with a header above, wrap width is capped at 65 % of the row's maximum. Sticker layout: `min(viewport width, height) × 0.5 × 0.625` (about 112 dp) with a 10 dp inset. Both use explicit-extent asset presets that decode at the drawn size at device pixel ratio, one cache entry per step. |
| Playback | A host policy, `ChatStickerPlayback`, not a rule of the body: loop, play once then rest on the first or the last frame, or still. The reference default plays the single unicode sticker once and loops a custom emoji. A sticker that plays once does so the first time the open chat shows it, decided by a host-held `ChatStickerPlayLedger` (per chat controller, [ADR 029](029-host-integration.md)), not by the cache. Unicode items in the text layout are glyphs at the step font; a host with the animated pack may opt in through the same resolver. See the amendment below. |
| Chrome | Stays host-side as for every body: time pill over the body's bottom-right, reactions below, reply or forward header beside the sticker layout and above the text layout. |
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
- The size tables are Android's values traced from its source; a change in the
  reference is a change here, recorded with its reason.
