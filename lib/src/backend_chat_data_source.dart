import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/demo_config.dart';
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Invokes a demo Edge Function and returns parsed JSON (test override supported).
typedef EdgeFunctionInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> body,
    );

/// Supabase-backed [ChatDataSource] for the demo (Edge Functions + Realtime).
class BackendChatDataSource extends ChatDataSource {
  /// Creates a new [BackendChatDataSource] instance.
  BackendChatDataSource({
    required SupabaseClient client,
    this.chatId = DemoConfig.demoChatId,
    this.requestTimeout = const Duration(seconds: 10),
    EdgeFunctionInvoker? invokeOverride,
    bool subscribeRealtime = true,
  }) : _client = client,
       _invokeOverride = invokeOverride {
    if (subscribeRealtime && invokeOverride == null) {
      _subscribeRealtime();
    }
  }

  /// Creates a new [BackendChatDataSource] instance for testing.
  @visibleForTesting
  factory BackendChatDataSource.forTest({
    required EdgeFunctionInvoker invoke,
    int chatId = 1,
  }) => BackendChatDataSource(
    client: _placeholderClient,
    chatId: chatId,
    invokeOverride: invoke,
    subscribeRealtime: false,
  );

  /// Connect via `load_chat` and seed newest boundary from `last_message.id`.
  static Future<BackendChatDataSource> connect({
    required SupabaseClient client,
    int? chatId,
  }) async {
    final source = BackendChatDataSource(
      client: client,
      chatId: chatId ?? DemoConfig.demoChatId,
    );
    await source._loadChatAndSeedBoundaries();
    return source;
  }

  /// Connects to the test backend and seeds boundaries.
  @visibleForTesting
  static Future<BackendChatDataSource> connectForTest(
    EdgeFunctionInvoker invoke, {
    int chatId = 1,
  }) async {
    final source = BackendChatDataSource.forTest(
      invoke: invoke,
      chatId: chatId,
    );
    await source._loadChatAndSeedBoundaries();
    return source;
  }

  static final SupabaseClient _placeholderClient = SupabaseClient(
    'http://127.0.0.1:54321',
    'test-anon-key',
  );

  final SupabaseClient _client;

  /// The chat id.
  final int chatId;

  /// The request timeout.
  final Duration requestTimeout;

  /// The invoke override.
  final EdgeFunctionInvoker? _invokeOverride;

  RealtimeChannel? _channel;

  Future<void> _loadChatAndSeedBoundaries() async {
    final body = await _invokeJson(
      'load_chat',
      body: <String, dynamic>{'chat_id': chatId},
    );
    final error = body['error'];
    if (error is Map<String, Object?>) {
      final slug = error['slug'];
      if (slug == 'chat_not_found' || slug == 'service_unavailable') {
        throw BackendConnectionException(
          'Supabase is not seeded.\n'
          'Run: supabase db reset',
        );
      }
      throw BackendConnectionException(_formatError(error));
    }

    final chat = body['chat'];
    if (chat is! Map<String, Object?>) {
      throw BackendConnectionException('load_chat returned no chat');
    }

    final lastMessage = chat['last_message'];
    if (lastMessage is! Map<String, Object?>) {
      seedBoundaries(reachedOldest: true, reachedNewest: true);
      return;
    }

    final newestId = lastMessage['id'];
    if (newestId is! int) {
      seedBoundaries(reachedOldest: true, reachedNewest: true);
      return;
    }

    seedBoundaries(newestKnownId: newestId, reachedNewest: true);
  }

  void _subscribeRealtime() {
    _channel = _client
        .channel('demo-chat-$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            _applyRealtimeInsert(payload.newRecord);
          },
        )
        .subscribe();
  }

  /// Shared by Realtime subscription and tests (US5).
  void _applyRealtimeInsert(Map<String, Object?> record) {
    if (record.isEmpty) return;
    final message = _messageFromProtocolJson(Map<String, dynamic>.from(record));
    upsertMessage(message);
    final id = message.id;
    final newest = newestKnownId;
    if (newest == null || id > newest) {
      seedBoundaries(newestKnownId: id, reachedNewest: true);
    }
    notifyDataChanged();
  }

  /// Test hook for Realtime INSERT without a live channel.
  @visibleForTesting
  void applyRealtimeInsertForTest(Map<String, Object?> record) {
    _applyRealtimeInsert(record);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    // Scroll chunk math includes id 0; Postgres message ids start at 1.
    final apiFromId = math.max(1, fromId);
    // Lift toId only when the scroll range started below 1 — preserves
    // intentional invalid ranges (e.g. toId < fromId) for API validation.
    final apiToId = fromId < 1 ? math.max(apiFromId, toId) : toId;
    final limit = math.min(apiToId - apiFromId + 1, 256);
    final batch = await _invokeJson(
      'load_messages',
      body: <String, dynamic>{
        'chat_id': chatId,
        'from_id': apiFromId,
        'to_id': apiToId,
        'limit': limit,
      },
    );

    final error = batch['error'];
    if (error is Map<String, Object?>) {
      Error.throwWithStackTrace(
        BackendConnectionException(_formatError(error)),
        StackTrace.current,
      );
    }

    final list = (batch['messages'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<String, Object?>>();
    final messages = <IChatMessage>[
      for (final item in list) _messageFromProtocolJson(item),
    ];

    _applyBoundaryUpdate(
      messages,
      batch,
      scrollFromId: fromId,
      scrollToId: toId,
      apiFromId: apiFromId,
      apiToId: apiToId,
    );
    return messages;
  }

  /// Sends a text message via the `send_message` Edge Function.
  Future<UserChatMessage> sendMessage(String content) async {
    final body = await _invokeJson(
      'send_message',
      body: <String, dynamic>{
        'chat_id': chatId,
        'content': content,
        'sender_id': 1,
      },
    );

    final error = body['error'];
    if (error is Map<String, Object?>) {
      Error.throwWithStackTrace(
        BackendConnectionException(_formatError(error)),
        StackTrace.current,
      );
    }

    final messageJson = body['message']! as Map<String, Object?>;
    final message = _messageFromProtocolJson(messageJson);
    upsertMessage(message);
    final id = message.id;
    final newest = newestKnownId;
    seedBoundaries(
      newestKnownId: newest == null ? id : math.max(newest, id),
      reachedNewest: true,
    );
    notifyDataChanged();
    return message;
  }

  /// Fetches persisted last-read message id from Postgres (`get_read_state`).
  Future<int?> getLastReadMessageId() async {
    final body = await _invokeJson(
      'get_read_state',
      body: <String, dynamic>{'chat_id': chatId, 'user_id': 1},
    );

    final error = body['error'];
    if (error is Map<String, Object?>) {
      Error.throwWithStackTrace(
        BackendConnectionException(_formatError(error)),
        StackTrace.current,
      );
    }

    final id = body['last_read_message_id'];
    return id is int ? id : null;
  }

  /// Persists last-read at tail (`update_read_state`).
  Future<void> updateLastReadMessageId(int messageId) async {
    final body = await _invokeJson(
      'update_read_state',
      body: <String, dynamic>{
        'chat_id': chatId,
        'user_id': 1,
        'last_read_message_id': messageId,
      },
    );

    final error = body['error'];
    if (error is Map<String, Object?>) {
      Error.throwWithStackTrace(
        BackendConnectionException(_formatError(error)),
        StackTrace.current,
      );
    }
  }

  Future<Map<String, dynamic>> _invokeJson(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    if (_invokeOverride != null) {
      return _invokeOverride(functionName, body);
    }
    try {
      final response = await _client.functions
          .invoke(functionName, body: body)
          .timeout(requestTimeout);
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is String && data.isNotEmpty) {
        return jsonDecode(data) as Map<String, dynamic>;
      }
      return <String, dynamic>{};
    } on TimeoutException {
      throw BackendConnectionException(
        'Timed out after ${requestTimeout.inSeconds}s calling $functionName\n'
        'Is Supabase running locally?\n'
        '  supabase start\n'
        '  supabase db reset\n'
        '  supabase functions serve',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic> && details['error'] is Map) {
        throw BackendConnectionException(
          _formatError(details['error']! as Map<String, Object?>),
        );
      }
      throw BackendConnectionException(
        '$functionName failed (${e.status}): ${e.reasonPhrase ?? e.details}',
      );
    }
  }

  void _applyBoundaryUpdate(
    List<IChatMessage> messages,
    Map<String, Object?> meta, {
    required int scrollFromId,
    required int scrollToId,
    required int apiFromId,
    required int apiToId,
  }) {
    // `has_older` / `has_newer` in [meta] were computed for [apiFromId,
    // apiToId]. [scrollFromId] may be 0 (chunk-0 slot) while [apiFromId] is
    // 1 — missing scroll id 0 in [messages] is expected, not incomplete fetch.
    assert(() {
      final requestedFrom = meta['requested_from'];
      final requestedTo = meta['requested_to'];
      if (requestedFrom is int && requestedFrom != apiFromId) return false;
      if (requestedTo is int && requestedTo != apiToId) return false;
      return true;
    }(), 'load_messages meta range must match apiFromId/apiToId');

    final ids = messages.map((m) => m.id);
    final loadedMin = ids.isEmpty ? null : ids.reduce(math.min);
    final loadedMax = ids.isEmpty ? null : ids.reduce(math.max);

    var oldest = oldestKnownId;
    var newest = newestKnownId;
    if (loadedMin != null) {
      oldest = oldest == null ? loadedMin : math.min(oldest, loadedMin);
    }
    if (loadedMax != null) {
      newest = newest == null ? loadedMax : math.max(newest, loadedMax);
    }

    final hasOlder = meta['has_older'] == true;
    final hasNewer = meta['has_newer'] == true;
    final terminalOldest = meta['oldest_id'] as int?;
    final terminalNewest = meta['newest_id'] as int?;

    seedBoundaries(
      oldestKnownId: hasOlder ? oldest : terminalOldest,
      newestKnownId: hasNewer ? newest : terminalNewest,
      reachedOldest: hasOlder ? null : true,
      reachedNewest: hasNewer ? null : true,
    );
  }

  UserChatMessage _messageFromProtocolJson(Map<String, Object?> json) {
    final extra = json['extra'];
    final legacySender = extra is Map<String, Object?>
        ? extra['legacy_sender'] as String?
        : null;
    final senderId = json['sender_id'] as int? ?? 1;
    final createdAt = switch (json['created_at']) {
      final int createdSec => DateTime.fromMillisecondsSinceEpoch(
        createdSec * 1000,
        isUtc: true,
      ),
      final String createdAtStr =>
        DateTime.tryParse(createdAtStr) ?? DateTime.now().toUtc(),
      _ => DateTime.now().toUtc(),
    };
    final updatedAt = switch (json['updated_at']) {
      final int updatedSec => DateTime.fromMillisecondsSinceEpoch(
        updatedSec * 1000,
        isUtc: true,
      ),
      final String updatedAtStr => DateTime.tryParse(updatedAtStr) ?? createdAt,
      _ => createdAt,
    };

    return UserChatMessage(
      id: json['id']! as int,
      sender: legacySender ?? 'user$senderId',
      createdAt: createdAt,
      updatedAt: updatedAt,
      content: json['content']! as String,
    );
  }

  String _formatError(Map<String, Object?> error) {
    final slug = error['slug'];
    final message = error['message'];
    final base = slug != null ? '[$slug] $message' : '$message';
    if (slug == 'service_unavailable') {
      return '$base\nIs Supabase running?\n  supabase start\n  supabase db reset';
    }
    return base.toString();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      _client.removeChannel(channel);
      _channel = null;
    }
    super.dispose();
  }
}

/// Thrown when the demo backend is unreachable or returns an error status.
class BackendConnectionException implements Exception {
  /// Creates a new [BackendConnectionException] instance.
  BackendConnectionException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => message;
}
