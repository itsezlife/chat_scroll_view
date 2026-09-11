# chat_md_selection

Optional bridge between chat **message selection** and markdown **text
selection**. Register message bodies, pick a **selection policy**, and let the
controller keep character ranges on one **text selection subject**.

Mobile and desktop/web differ on entry and Copy. That split lives in
[ChatMdSelectionPolicy]. Mobile nests text under message selection; desktop
arms markdown gestures for direct entry when message membership is empty and
keeps the range after Copy. This package does not show copy toasts — listen
for Copy success and show feedback in the app if you want it.

## Quick start

```dart
final messages = ChatSelectionController();
final mdSelection = ChatMdSelectionController(
  messageSelection: messages,
  // Optional. Omit for ChatMdSelectionPolicy.forPlatform().
  policy: const ChatMdSelectionPolicy.mobile(),
  onCopySuccess: (text) {
    // App-side feedback only.
  },
);

// Per message body:
mdSelection.putBody(messageId, Markdown.fromString(body));

// In the tree:
ChatMdSelectionScope(
  controller: mdSelection,
  child: ChatMdBody(
    controller: mdSelection,
    messageId: messageId,
  ),
);
```

Wrap the list in [ChatMdSelectionScope], paint rows with [ChatMdBody]. Span
yield is wired at construction when the policy claims it. You can also call
[ChatMdSelectionController.enterTextSelection] (with a global point for a word,
or without for select-all). Default toolbar Copy goes through
[ChatMdSelectionController.copyTextSelection].