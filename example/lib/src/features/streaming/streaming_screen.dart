import 'dart:async';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';

/// The reply of plain mode: markup stays literal, `[Nn]` becomes a mark.
const streamingDemoPlainReply = '''
# not a heading, *not italic*, **not bold**, _not either_

Candidates: [N1] and [N12] fit the brief.
Last line.
''';

final _markHook = ChatInlineHook(
  pattern: RegExp(r'\[N\d+\]'),
  build: (match, start) => MD$Span(
    start: start,
    end: start + match.group(0)!.length,
    text: match.group(0)!,
    style: MD$Style.chip,
    extra: <String, Object?>{
      'type': 'chip',
      'target': 'mark:${match.group(0)}',
      'muted': false,
    },
  ),
);

/// The reply the demo streams, a few characters at a time.
const streamingDemoReply = '''
# Streaming into a row

The row's message object never changes while this text grows: the tile
listens to a **ChatStreamingBodyController**, and the viewport only relayouts.

- deltas are coalesced to one update per frame
- the text stays selectable while it streams
- `settle` swaps in the final text, then the host runs one `updateMessage`

```dart
controller.append(delta);
controller.settle(finalText);
```
''';

/// A demo chat row: one fixed object per id, whoever speaks.
@immutable
class StreamingDemoMessage implements IChatMessage {
  /// Creates a row of [id] spoken by [sender] with [text] (the settled text
  /// of an assistant row, or the whole text of the user's).
  const StreamingDemoMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
  });

  @override
  final int id;

  @override
  final String sender;

  /// The text of the row once it is final.
  final String text;

  @override
  final DateTime createdAt;

  @override
  DateTime get updatedAt => createdAt;
}

/// In-memory source: a short history plus rows the demo inserts.
class StreamingDemoDataSource extends ChatDataSource {
  /// Seeds one user message.
  StreamingDemoDataSource() {
    final first = StreamingDemoMessage(
      id: 1,
      sender: 'me',
      text: 'Stream me a reply.',
      createdAt: DateTime(2026),
    );
    upsertMessage(first);
    seedBoundaries(
      oldestKnownId: 1,
      newestKnownId: 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Streams [streamingDemoReply] into a row on Send, then settles it with one
/// `updateMessage`.
class StreamingScreen extends StatefulWidget {
  /// Creates the screen.
  const StreamingScreen({super.key});

  @override
  State<StreamingScreen> createState() => StreamingScreenState();
}

/// Public so a test can read the live state.
class StreamingScreenState extends State<StreamingScreen> {
  /// The in-memory source.
  final source = StreamingDemoDataSource();

  /// Viewport controller.
  final scroll = ChatScrollController();

  /// Selection facade.
  final selection = ChatSelectionController();

  /// Text source of the live row, or null while none streams.
  ChatStreamingBodyController? body;

  /// Id of the live row.
  int? liveId;

  Timer? _timer;
  int _nextId = 2;

  /// Whether the next reply streams in plain mode with the `[Nn]` hook.
  bool plain = false;

  String get _reply => plain ? streamingDemoPlainReply : streamingDemoReply;

  /// Whether a reply is streaming.
  bool get busy => _timer != null;

  /// Inserts the user row and the live row, then streams the reply.
  void send() {
    if (busy) return;
    final now = DateTime.now();
    final userId = _nextId++;
    final replyId = _nextId++;
    final reply = _reply;
    final live = ChatStreamingBodyController(
      plain: plain,
      inlineHook: plain ? _markHook : null,
    );
    setState(() {
      body = live;
      liveId = replyId;
    });
    source.insertMessages([
      StreamingDemoMessage(
        id: userId,
        sender: 'me',
        text: 'Stream me a reply.',
        createdAt: now,
      ),
      StreamingDemoMessage(
        id: replyId,
        sender: 'assistant',
        text: '',
        createdAt: now,
      ),
    ]);
    var offset = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      final end = (offset + 6).clamp(0, reply.length);
      live.append(reply.substring(offset, end));
      offset = end;
      if (offset < reply.length) return;
      timer.cancel();
      _timer = null;
      // The final text wins, then the row is swapped once.
      live.settle(reply);
      source.updateMessage(
        StreamingDemoMessage(
          id: replyId,
          sender: 'assistant',
          text: reply,
          createdAt: now,
        ),
      );
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    body?.dispose();
    scroll.dispose();
    selection.dispose();
    source.dispose();
    super.dispose();
  }

  Widget _tile(
    BuildContext context,
    int id,
    IChatMessage? message,
    ChatMessageStatus status,
    MessageRunLayout run,
  ) {
    if (message is! StreamingDemoMessage) return const SizedBox(height: 48);
    final mine = message.sender == 'me';
    final live = id == liveId ? body : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(mine ? 64 : 8, 3, mine ? 8 : 32, 3),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: mine ? const Color(0xFF2F6FED) : const Color(0xFF2B2F36),
            borderRadius: const BorderRadius.all(Radius.circular(14)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white, fontSize: 15),
              child: live == null
                  ? Text(message.text)
                  : ChatStreamingBody(
                      controller: selection,
                      messageId: id,
                      body: live,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF17191D),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                FilledButton(
                  key: const ValueKey('streaming-send'),
                  onPressed: busy ? null : send,
                  child: const Text('Send'),
                ),
                const SizedBox(width: 12),
                const Text('Plain', style: TextStyle(color: Colors.white)),
                Switch(
                  key: const ValueKey('streaming-plain'),
                  value: plain,
                  onChanged: busy ? null : (v) => setState(() => plain = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ChatScrollView(
              reverse: true,
              dataSource: source,
              controller: scroll,
              selectionController: selection,
              isSelfMessage: (m) => m.sender == 'me',
              messageBuilder: _tile,
            ),
          ),
        ],
      ),
    ),
  );
}
