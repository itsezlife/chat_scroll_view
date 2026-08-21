import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/comments_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';

/// Whether [message] body contains [query] (already lower-cased).
bool chatMessageMatchesQuery(IChatMessage message, String query) {
  final text = message.text;
  if (text == null) return false;
  return text.toLowerCase().contains(query);
}

/// Scans the full known id range — not only the viewport cache.
///
/// Prefer source-specific fast paths ([CommentsDataSource],
/// [GeneratedChatDataSource]); fall back to batched [ChatDataSource.fetchRange]
/// so unloaded chunks are still searched.
Future<List<int>> searchAllMessageIds(
  ChatDataSource dataSource,
  String rawQuery, {
  required bool Function() isCancelled,
}) async {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return const [];

  final ds = dataSource;
  if (ds is CommentsDataSource) {
    return ds.searchAllMessageIds(query, isCancelled: isCancelled);
  }
  if (ds is GeneratedChatDataSource) {
    return ds.searchAllMessageIds(query, isCancelled: isCancelled);
  }
  return _searchViaFetchRange(ds, query, isCancelled: isCancelled);
}

Future<List<int>> _searchViaFetchRange(
  ChatDataSource dataSource,
  String query, {
  required bool Function() isCancelled,
}) async {
  final oldest = dataSource.oldestKnownId;
  final newest = dataSource.newestKnownId;
  if (oldest == null || newest == null || oldest > newest) {
    return const [];
  }

  final hits = <int>[];
  const batch = 64;
  for (var from = oldest; from <= newest; from += batch) {
    if (isCancelled()) return hits;
    final to = (from + batch - 1).clamp(from, newest);

    // Prefer already-cached rows; fetch only when a slot in the batch is cold.
    var missing = false;
    for (var id = from; id <= to; id++) {
      if (dataSource.getMessage(id) == null) {
        missing = true;
        break;
      }
    }

    if (missing) {
      final loaded = await dataSource.fetchRange(fromId: from, toId: to);
      if (isCancelled()) return hits;
      for (final message in loaded) {
        if (chatMessageMatchesQuery(message, query)) {
          hits.add(message.id);
        }
      }
      continue;
    }

    for (var id = from; id <= to; id++) {
      final message = dataSource.getMessage(id);
      if (message != null && chatMessageMatchesQuery(message, query)) {
        hits.add(id);
      }
    }

    // Yield so a newer submit can supersede this scan.
    await Future<void>.delayed(Duration.zero);
  }
  return hits;
}
