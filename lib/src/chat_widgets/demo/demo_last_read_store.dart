import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';

/// Fixed conversation key for the single demo chat backed by [BackendChatDataSource].
const demoConversationId = 'demo';

/// Vertical alignment for off-tail last-read open (`0` = top, `0.5` = center).
const kDemoLastReadOpenAlignment = 0.5;

typedef MessageLookup = IChatMessage? Function(int id);

/// Resolves the message id to pass to [ChatScrollController.jumpTo] on open.
int resolveOpenAnchor({
  required int? storedLastRead,
  required int? newestKnownId,
  required int? oldestKnownId,
  required MessageLookup getMessage,
}) {
  if (newestKnownId == null) return 0;
  if (storedLastRead == null) return newestKnownId;
  if (storedLastRead >= newestKnownId) return newestKnownId;

  final oldest = oldestKnownId ?? 0;
  if (storedLastRead < oldest) return oldest;

  if (getMessage(storedLastRead) != null) return storedLastRead;

  // Walk backward only through loaded messages to recover from a confirmed
  // deletion. If nothing in [oldest, storedLastRead) is loaded yet
  // (metadata-only connect), trust the stored id — the viewport fetch
  // loads the surrounding chunk on jumpTo.
  for (var id = storedLastRead - 1; id >= oldest; id--) {
    if (getMessage(id) != null) return id;
  }
  return storedLastRead;
}
