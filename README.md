# chat_scroll_view

Endless, anchor-based chat viewport for Flutter. Layout fans out from
`(anchorMessageId, anchorPixelOffset)` instead of a global content height.

## Usage

```dart
import 'package:chat_scroll_view/chat_scroll_view.dart';

ChatScrollView(
  dataSource: dataSource,
  controller: controller,
  messageBuilder: (context, id, message, status, runLayout) {
    if (message == null) return const ShimmerMessage();
    return Text(message.sender);
  },
)
```

Implement [ChatDataSource.fetchRange] for your backend. The example app
under `example/` wires a Supabase demo and an offline comments dataset.

## Markdown bodies

`ChatMarkdownBody` paints a message body registered on the
`ChatSelectionController` and owns the viewport's text selection over it
([ADR 013](docs/adr/013-viewport-owns-markdown-text-selection.md)). The markdown
engine behind it is a fork ([ADR 035](docs/adr/035-markdown-engine-fork.md));
the root package adapts the fork's inline embed contract to `catalog_assets`
([ADR 029](docs/adr/029-host-integration.md)) and depends on `catalog_assets`
and `content_model` ([ADR 020](docs/adr/020-package-topology.md)).

What a body can hold besides text:

| In the text | Painted as | A tap reaches the host as |
| --- | --- | --- |
| `![alt](scheme:id)` | An inline embed from the body's `embedResolver`; the alt text where nothing resolves | `ChatInlineHit.embed` / `ChatEmbedActivated`, only with `handlesEmbedHits` |
| `[@name](mention:id)`, `[@name](username:name)` | Mention colour, no underline | `ChatInlineHit.resolvedMention` / `ChatResolvedMentionActivated` (with the user's `id`), `ChatInlineHit.usernameMention` / `ChatUsernameMentionActivated` (no id); both are a `ChatMentionActivated` |
| `[#tag](hashtag:tag)` | Mention colour, no underline | `ChatInlineHit.hashtag` / `ChatHashtagActivated` |
| `[text](https://...)` | Link colour, underline | `ChatInlineHit.link` / `ChatLinkActivated` |
| `\|\|text\|\|` | Hidden under moving dust until the message is revealed | A tap reveals the whole message and is nothing else: no hit, no `onIdleMessageTap` |

A hit is read from the span's style bit, never from its URL: a mention is not
a link and an image is not a link. Anything inside a hidden spoiler reveals
instead of activating, and a text selection that enters a hidden spoiler
reveals the message. The tap that reveals is absorbed; a long press, a drag and a
secondary click are not ([ADR 037](docs/adr/037-spoiler-and-mention-inline-styles.md)).

### Host contract

| The host provides | The host must not |
| --- | --- |
| One stable `InlineEmbedResolver` per body setup (`ContentEmbedResolver` over its `AssetCacheScope`, or its own composition by scheme) as `ChatMarkdownBody.embedResolver` | Build a new resolver per build (the engine resolves every embed again), or send a bare emoji character expecting an embed: only `![alt](scheme:id)` is one |
| `ChatSelectionController(handlesEmbedHits: true)` when `ChatEmbedActivated` means something (a sticker preview, a pack sheet) | Expect an embed to be tappable by default: without it an embed is text, with the text cursor and no press highlight, and a tap on it is a tap on the message |
| A reaction to `ChatMentionActivated` and `ChatHashtagActivated` (through `onInteraction` or a listener), using the `id` of a `ChatResolvedMentionActivated` to open a user | Read a mention's label as who it is, or look for mentions among `ChatLinkActivated` |
| `ChatSelectionController(spoilerClock: scope.clock)`, the asset cache's `PlaybackClock`, so the dust moves on the shared clock and its pause layers | Run a ticker of its own for the dust (without the clock the dust stands still), or persist what `ChatSelectionController.spoilers` holds: reveal state is in memory |
| `copyWriter` reading `ChatTextCopy.content` by style bit (`MD$Style.mention`, `image`, `spoiler`) when it keeps formatting on the clipboard | Detect a mention by its URL, or expect `plainText` to carry markdown: it is the revealed text with an embed's alt |

## Emoji-only bodies

`ChatEmojiBody` is the second body the viewport ships: a bubble-less message
of nothing but emoji, laid out as Telegram Android does. The host classifies
the text once, when it builds the message (`EmojiOnlyText.of` in
`content_model`), and shows this body instead of `ChatMarkdownBody`; the
viewport never re-detects.

| Layout | When | Paints |
| --- | --- | --- |
| Sticker | One item and the host resolved it to a document (`sticker:`) | A square of `min(screen width, height) x 0.5 x 0.625` (112.5 dp on a phone) in a 10 dp inset; a custom emoji's sticker loops, a unicode emoji's plays once |
| Text | Anything else | Squares of the font step the count gives (`ChatEmojiSizes`: 81.6 down to 22.8 dp, a custom-only message one step larger, box = font + 4 dp), a unicode emoji as a glyph; the text scale plays no part |

The body registers with the facade as a **non-text body**
(`ChatSelectionController.putNonTextBody`): there is nothing to select, a long
press is message selection, and Copy is the message's own. A tap on the
sticker is `ChatInlineHit.sticker` / `ChatStickerActivated`, always, when it
lands on the drawn sticker (and nowhere beside it, unless the host sets
`ChatStickerTapPolicy.replayTapSlop`); the body then plays the sticker again
under its tap policy, never rewinding a pass that is running. A tap on a
custom emoji is `ChatInlineHit.embed` with `handlesEmbedHits`, as in a markdown
body.

### Host contract

| The host provides | The host must not |
| --- | --- |
| `EmojiOnlyText.of(richText)` once per message, plus the facts only it has: no media (a link preview counts as media), the large-emoji setting and the chat's permission | Ask the body to classify, or show it for a message that has media |
| `embedFactory`, one stable function over its cache (`(content, preset) => ContentEmbed(scope: scope, content: content, preset: preset)`) | Pass `InlineEmbedResolver`: it sizes from text metrics, and this body sizes by count with `AssetPresets.emojiOnly` / `emojiSticker` |
| `sticker:` (the animated-emoji pack's document for a unicode emoji, the custom emoji's own document) | Pass a document for more than one item |
| `playback:` (`ChatStickerPlayback`: loop, once then the first or the last frame, still; null is the reference default per emoji) from its animation settings, and `playLedger:` (`ChatStickerPlayLedger`), its played-once memory per open chat | Keep that memory in the cache or the body: it is per chat screen, not per entry or per mount |
| `isActive:` (row visibility, app lifecycle, route focus, power policy combined) | Expect the body to read them: an inactive row costs no ticks, shows no sticker rectangle and drops a remote interaction |
| `tapPolicy:` only to change the replay tap slop (zero on both strategies) or the mobile long press | Widen the slop without confirming the claim that a tap near the sticker replays: no reference client does |
| A listener for `ChatStickerActivated` (the emoji, message id, `stickerRect`, monotonic `tapTime`) to build an interaction effect and a peer broadcast on, and `ChatSelectionController.playRemoteInteraction(messageId)` for one that arrives (null: drop it, send no acknowledgement) | Expect the viewport to draw the effect or send anything; it ships the seams |
| The time pill, reactions, reply and forward header, placed by `ChatEmojiBody.layoutKindFor` (beside a sticker, above text) and `hasHeader` (text wraps at 65 % of the row's width under a header) | Expect the body to draw chrome, or to be wrapped in a bubble |
| `semanticsLabel` with the message's plain text when it has it | Rely on the default label for a custom emoji: `EmojiOnly` keeps no text for one |

## Example

```sh
cd example
flutter run --dart-define-from-file=../config/development.supabase.json
```

Start the local demo backend first: `./scripts/dev.sh`.
