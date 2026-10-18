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
secondary click are not. While a message selection is live a tap toggles the
row and reveals nothing, and a press held longer than 500 ms reveals nothing
([ADR 037](docs/adr/037-spoiler-and-mention-inline-styles.md)).

### Host contract

| The host provides | The host must not |
| --- | --- |
| One stable `InlineEmbedResolver` per body setup (`ContentEmbedResolver` over its `AssetCacheScope`, or its own composition by scheme) as `ChatMarkdownBody.embedResolver` | Build a new resolver per build (the engine resolves every embed again), or send a bare emoji character expecting an embed: only `![alt](scheme:id)` is one |
| `ChatSelectionController(handlesEmbedHits: true)` when `ChatEmbedActivated` means something (a sticker preview, a pack sheet) | Expect an embed to be tappable by default: without it an embed is text, with the text cursor and no press highlight, and a tap on it is a tap on the message |
| A reaction to `ChatMentionActivated` and `ChatHashtagActivated` (through `onInteraction` or a listener), using the `id` of a `ChatResolvedMentionActivated` to open a user | Read a mention's label as who it is, or look for mentions among `ChatLinkActivated` |
| `ChatSelectionController(spoilerClock: scope.clock)`, the asset cache's `PlaybackClock`, so the dust moves on the shared clock and its pause layers | Run a ticker of its own for the dust (without the clock the dust stands still), or persist what `ChatSelectionController.spoilers` holds: reveal state is in memory |
| `ChatSelectionController.spoilers.tapTimeout = null` on a desktop or web host whose pointer is a mouse (a click has no hold limit) | Set `spoilers.tapReveals` yourself: the facade writes it from `isSelectionMode`, and your value would not survive the next selection change |
| `copyWriter` reading `ChatTextCopy.content` by style bit (`MD$Style.mention`, `image`, `spoiler`) when it keeps formatting on the clipboard: a selected hidden spoiler arrives with its `spoiler` bit, and the rich clipboard pastes it back as a spoiler | Detect a mention by its URL, or expect `plainText` to carry markdown: it is the characters (a spoiler's included) with an embed's alt |
| A call to `spoilers.reveal(messageId)` from `onInteraction` only if the product follows iOS and reveals on selection | Expect a text selection over a hidden spoiler to reveal it: the facade selects it hidden and paints the selection under the particles |
| `MarkdownThemeData.emojiScale` from `ChatEmojiPolicy.inTextEmojiScale` (1 on Android and iOS, 1.2 on desktop) so a unicode emoji in a bubble sits beside a custom emoji at one size; `emojiRuns: (_) => const []` on the theme to turn the enlargement off | Expect a unicode emoji in a sentence to be drawn at the font size: the body sets each colour emoji at the font's height (ascent plus descent) times the scale, and leaves a text glyph (`©`, a bare `❤`, a digit) alone |

## Emoji-only bodies

`ChatEmojiBody` is the second body the viewport ships: a bubble-less message
of nothing but emoji, laid out by the platform's `ChatEmojiPolicy` (`$Android`,
`$Ios`, `$Desktop`: three families that differ in sizes, inset, count cap, wrap
and mirroring, picked once with `ChatEmojiPolicy.forPlatform`). The host classifies
the text once, when it builds the message (`EmojiOnlyText.of` in
`content_model`), and shows this body instead of `ChatMarkdownBody`; the
viewport never re-detects.

| Layout | When | Paints |
| --- | --- | --- |
| Sticker | One item and the host resolved it to a document (`sticker:`) | A square the policy sizes (Android `min(screen width, height) x 0.5 x 0.625`, 112.5 dp on a phone, no inset; iOS 112 pt in a 10 pt inset; desktop 112 px); a custom emoji's sticker loops, a unicode emoji's plays once |
| Text | Anything else | Squares of the font step the policy gives (Android `ChatEmojiSizes`: 81.6 down to 22.8 dp, a custom-only message one step larger, box = font + 4 dp; iOS 94 pt down to 19; desktop 38 px images), a unicode emoji as a glyph; the text scale plays no part |

The **text layout is selectable text**, as a markdown body is: it registers a
text model with the facade (`putBody`, one paragraph made from the items) and
its render object is the selection surface of that model, so drag, double click
or long press (one emoji), select-all, shift-select, handles, the toolbar and
Copy (plain, and structured through `ChatTextCopy.content`, a custom emoji
being an image span that names its document) are the markdown body's own,
under the same selection policy. The **sticker layout is not text**: a long
press is message selection and Copy is the message's own. Both register as a
**non-text body** (`ChatSelectionController.putNonTextBody`) for the
activatable parts. A tap on the
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
| `ChatEmojiPolicy.forPlatform(desktopRegularLimit: n)` (or `ChatEmojiPolicy.desktop(regularLimit: n)`) when the user may move the desktop cap on enlarged regular emoji, 3 by default and counted over every item of a message that is not all custom emoji; the same policy goes to the body and to the host's own `admits` check | Pass a cap to Android or iOS (they have no cap and ignore it), or cap custom-emoji-only lines (they never are) |
| `embedFactory`, one stable function over its cache (`(content, preset) => ContentEmbed(scope: scope, content: content, preset: preset)`) | Pass `InlineEmbedResolver`: it sizes from text metrics, and this body sizes by count with `AssetPresets.emojiOnly` / `emojiSticker` |
| `sticker:` (the animated-emoji pack's document for a unicode emoji, the custom emoji's own document) | Pass a document for more than one item |
| `playback:` (`ChatStickerPlayback`: loop, once then the first or the last frame, still; null is the reference default per emoji) from its animation settings, and `playLedger:` (`ChatStickerPlayLedger`), its played-once memory per open chat | Keep that memory in the cache or the body: it is per chat screen, not per entry or per mount |
| `isActive:` (row visibility, app lifecycle, route focus, power policy combined) | Expect the body to read them: an inactive row costs no ticks, shows no sticker rectangle and drops a remote interaction |
| `tapPolicy:` only to change the replay tap slop (zero on both strategies) or the mobile long press | Widen the slop without confirming the claim that a tap near the sticker replays: no reference client does |
| A listener for `ChatStickerActivated` (the emoji, message id, `stickerRect`, monotonic `tapTime`) to build an interaction effect and a peer broadcast on, and `ChatSelectionController.playRemoteInteraction(messageId)` for one that arrives (null: drop it, send no acknowledgement) | Expect the viewport to draw the effect or send anything; it ships the seams |
| The time pill, reactions, reply and forward header, placed per platform from `ChatEmojiBody.geometryFor` (the box, text rectangle and trailing edge, last line, art rectangle, the strip of `bottomReserve`) and `ChatEmojiPolicy.headerPlacementFor`; `hasHeader` when a header narrows the text's wrap by the policy's rule | Expect the body to draw chrome, to be wrapped in a bubble, or put Android's chrome on every platform |
| The time pill (and any status chrome) wrapped in `ChatMessageTapBarrier`, so a mouse click on it is not a message tap: no selection toggle, no drag-select, no idle tap, no sticker tap under it. A secondary click still reaches `onSecondaryMessageTap`, a tap still dismisses text selection, touch is never barred. The click then does nothing, unless the host puts a mouse-only detector inside the barrier: the reference desktop client selects the message on a click on its time, which `ChatSelectionController.toggle` does (ADR 012, Status chrome). A desktop host shows the pill of an emoji-only message while the pointer is on the whole row (the viewport's cell), not the emoji box | Put a detector in the row to stop the viewport (its selection pointer listens above the gesture arena), bar the body itself, or hover-reveal the pill from a region as small as the emoji box |
| `semanticsLabel` with the message's plain text when it has it | Rely on the default label for a custom emoji built by hand: its text is `EmojiOnlyItem.alt`, empty unless `EmojiOnlyText.of` read it |
| Nothing more for text selection: the body registers its own text and the facade's gestures, handles and Copy apply. `selectableText: false` only when the product keeps the iOS and Desktop reference rule (their large emoji are not text; only Android selects them) | Register a markdown body for the same message id as well, or expect a selection to hold the spaces and tabs between emoji (`EmojiOnly` drops them): it holds the emoji and the line breaks |

## Example

```sh
cd example
flutter run --dart-define-from-file=../config/development.supabase.json
```

Start the local demo backend first: `./scripts/dev.sh`.
