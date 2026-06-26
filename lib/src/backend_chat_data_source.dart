import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/demo_config.dart';
import 'package:http/http.dart' as http;

/// HTTP-backed [ChatDataSource] for the local demo backend.
class BackendChatDataSource extends ChatDataSource {
  BackendChatDataSource({
    required this.baseUrl,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration requestTimeout;

  int? _totalMessages;

  /// Connect to backend, load conversation metadata, seed newest boundary.
  static Future<BackendChatDataSource> connect({
    String? baseUrl,
    http.Client? client,
  }) async {
    final source = BackendChatDataSource(
      baseUrl: baseUrl ?? DemoConfig.backendUrl,
      client: client,
    );
    await source._loadConversationMetadata();
    return source;
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri).timeout(requestTimeout);
    } on TimeoutException {
      throw BackendConnectionException(
        'Timed out after ${requestTimeout.inSeconds}s requesting $uri\n'
        'Is ./scripts/dev.sh running? '
        'USB Android device: use "main.dart (Android device)" (your Mac LAN IP). '
        'Emulator: use "main.dart (Android emulator)" (10.0.2.2).',
      );
    }
  }

  Future<void> _loadConversationMetadata() async {
    final uri = Uri.parse('$baseUrl/api/conversation');
    final response = await _get(uri);
    if (response.statusCode != 200) {
      Error.throwWithStackTrace(
        BackendConnectionException(
          'GET /api/conversation failed (${response.statusCode}): ${response.body}',
        ),
        StackTrace.current,
      );
    }
    final json = jsonDecode(response.body) as Map<String, Object?>;
    final total = json['totalMessages']! as int;
    _totalMessages = total;

    if (total == 0) {
      seedBoundaries(reachedOldest: true, reachedNewest: true);
      return;
    }

    seedBoundaries(newestKnownId: total - 1, reachedNewest: true);
  }

  int? get totalMessages => _totalMessages;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/messages',
    ).replace(queryParameters: {'fromId': '$fromId', 'toId': '$toId'});
    final response = await _get(uri);
    if (response.statusCode != 200) {
      Error.throwWithStackTrace(
        BackendConnectionException(
          'GET /api/messages failed (${response.statusCode}): ${response.body}',
        ),
        StackTrace.current,
      );
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;
    final list = (body['messages']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final meta = body['rangeMeta']! as Map<String, Object?>;

    final messages = <IChatMessage>[
      for (final item in list) UserChatMessage.fromJson(item),
    ];

    _applyBoundaryUpdate(messages, meta);
    return messages;
  }

  void _applyBoundaryUpdate(
    List<IChatMessage> messages,
    Map<String, Object?> meta,
  ) {
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

    final hasOlder = meta['hasOlder']! as bool;
    final hasNewer = meta['hasNewer']! as bool;

    seedBoundaries(
      oldestKnownId: hasOlder ? oldest : meta['oldestId'] as int?,
      newestKnownId: hasNewer ? newest : meta['newestId'] as int?,
      // Only set terminal flags when the server confirms an edge; omit when
      // more pages exist so connect()-seeded reachedNewest is not cleared.
      reachedOldest: hasOlder ? null : true,
      reachedNewest: hasNewer ? null : true,
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// Thrown when the demo backend is unreachable or returns an error status.
class BackendConnectionException implements Exception {
  BackendConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
