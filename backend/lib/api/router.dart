import 'dart:convert';

import 'package:chat_demo_backend/storage/message_repository.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

Handler createRouter(MessageRepository repository) {
  final router = Router();

  router.get('/health', (_) {
    return Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  router.get('/api/conversation', (_) {
    if (!repository.isSeeded) {
      return _notSeeded();
    }
    final conv = repository.getConversation()!;
    return Response.ok(
      jsonEncode(conv.toJson()),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  router.get('/api/messages', (Request request) {
    if (!repository.isSeeded) {
      return _notSeeded();
    }
    final fromParam = request.url.queryParameters['fromId'];
    final toParam = request.url.queryParameters['toId'];
    if (fromParam == null || toParam == null) {
      return _invalidRange('fromId and toId query parameters are required');
    }
    final fromId = int.tryParse(fromParam);
    final toId = int.tryParse(toParam);
    if (fromId == null ||
        toId == null ||
        fromId < 0 ||
        toId < 0 ||
        fromId > toId) {
      return _invalidRange(
        'fromId and toId must be non-negative integers with fromId <= toId',
      );
    }

    final result = repository.fetchRange(fromId: fromId, toId: toId);
    return Response.ok(
      jsonEncode({
        'messages': [for (final m in result.messages) m.toJson()],
        'rangeMeta': result.rangeMeta.toJson(),
      }),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  return router.call;
}

Response _notSeeded() => Response(
  404,
  body: jsonEncode({
    'error': 'not_seeded',
    'message': 'Database has no conversation data. Run: dart run bin/seed.dart',
  }),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Response _invalidRange(String message) => Response(
  400,
  body: jsonEncode({
    'error': 'invalid_range',
    'message': message,
  }),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
