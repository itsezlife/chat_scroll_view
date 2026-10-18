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
| `[@name](mention:id)`, `[@name](username:name)` | Mention colour, no underline | `ChatInlineHit.mention` / `ChatMentionActivated` (`kind` says which; a username has no id) |
| `[#tag](hashtag:tag)` | Mention colour, no underline | `ChatInlineHit.hashtag` / `ChatHashtagActivated` |
| `[text](https://...)` | Link colour, underline | `ChatInlineHit.link` / `ChatLinkActivated` |
| `\|\|text\|\|` | Hidden under moving dust until the message is revealed | A tap reveals the whole message and reports no hit |

A hit is read from the span's style bit, never from its URL: a mention is not
a link and an image is not a link. Anything inside a hidden spoiler reveals
instead of activating, and a text selection that enters a hidden spoiler
reveals the message ([ADR 037](docs/adr/037-spoiler-and-mention-inline-styles.md)).

### Host contract

| The host provides | The host must not |
| --- | --- |
| One stable `InlineEmbedResolver` per body setup (`ContentEmbedResolver` over its `AssetCacheScope`, or its own composition by scheme) as `ChatMarkdownBody.embedResolver` | Build a new resolver per build (the engine resolves every embed again), or send a bare emoji character expecting an embed: only `![alt](scheme:id)` is one |
| `ChatSelectionController(handlesEmbedHits: true)` when `ChatEmbedActivated` means something (a sticker preview, a pack sheet) | Expect an embed to be tappable by default: without it an embed is text, with the text cursor and no press highlight, and a tap on it is a tap on the message |
| A reaction to `ChatMentionActivated` and `ChatHashtagActivated` (through `onInteraction` or a listener), using `id` to open a user | Read a mention's label as who it is, or look for mentions among `ChatLinkActivated` |
| `ChatSelectionController(spoilerClock: scope.clock)`, the asset cache's `PlaybackClock`, so the dust moves on the shared clock and its pause layers | Run a ticker of its own for the dust (without the clock the dust stands still), or persist what `ChatSelectionController.spoilers` holds: reveal state is in memory |
| `copyWriter` reading `ChatTextCopy.content` by style bit (`MD$Style.mention`, `image`, `spoiler`) when it keeps formatting on the clipboard | Detect a mention by its URL, or expect `plainText` to carry markdown: it is the revealed text with an embed's alt |

## Example

```sh
cd example
flutter run --dart-define-from-file=../config/development.supabase.json
```

Start the local demo backend first: `./scripts/dev.sh`.
