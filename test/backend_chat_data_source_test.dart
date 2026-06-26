import 'dart:convert';

import 'package:chatscrollview/src/backend_chat_data_source.dart';
import 'package:chatscrollview/src/demo_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('BackendChatDataSource', () {
    test('fetchRange maps messages and updates boundaries', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/messages');
        expect(request.url.queryParameters['fromId'], '64');
        expect(request.url.queryParameters['toId'], '127');
        return http.Response(
          jsonEncode({
            'messages': [
              {
                'id': 64,
                'sender': 'alice',
                'content': 'hello',
                'createdAt': '2020-03-02T00:19:16Z',
              },
            ],
            'rangeMeta': {
              'requestedFrom': 64,
              'requestedTo': 127,
              'oldestId': 0,
              'newestId': 999,
              'totalMessages': 1000,
              'hasOlder': true,
              'hasNewer': true,
            },
          }),
          200,
        );
      });

      final source = BackendChatDataSource(
        baseUrl: 'http://127.0.0.1:8080',
        client: client,
      );
      source.seedBoundaries(newestKnownId: 999, reachedNewest: true);

      final messages = await source.fetchRange(fromId: 64, toId: 127);

      expect(messages, hasLength(1));
      expect(messages.first.id, 64);
      expect(messages.first.sender, 'alice');
      expect(source.oldestKnownId, 64);
      expect(source.reachedOldest, isFalse);
      expect(source.reachedNewest, isTrue);

      source.dispose();
    });

    test('terminal oldest boundary sets reachedOldest', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'messages': [
              {
                'id': 0,
                'sender': 'bob',
                'content': 'first',
                'createdAt': '2020-03-02T00:19:16Z',
              },
            ],
            'rangeMeta': {
              'requestedFrom': 0,
              'requestedTo': 63,
              'oldestId': 0,
              'newestId': 99,
              'totalMessages': 100,
              'hasOlder': false,
              'hasNewer': true,
            },
          }),
          200,
        );
      });

      final source = BackendChatDataSource(
        baseUrl: DemoConfig.backendUrl,
        client: client,
      );
      source.seedBoundaries(newestKnownId: 99, reachedNewest: true);

      await source.fetchRange(fromId: 0, toId: 63);

      expect(source.reachedOldest, isTrue);
      expect(source.oldestKnownId, 0);

      source.dispose();
    });

    test('non-200 throws BackendConnectionException', () async {
      final client = MockClient(
        (_) async => http.Response('not found', 404),
      );
      final source = BackendChatDataSource(
        baseUrl: DemoConfig.backendUrl,
        client: client,
      );

      expect(
        () => source.fetchRange(fromId: 0, toId: 10),
        throwsA(isA<BackendConnectionException>()),
      );

      source.dispose();
    });

    test('connect seeds newest boundary from metadata', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/conversation') {
          return http.Response(
            jsonEncode({
              'title': 'Test',
              'totalMessages': 500,
              'chunkSize': 64,
              'senders': ['a'],
            }),
            200,
          );
        }
        fail('unexpected request: ${request.url}');
      });

      final source = await BackendChatDataSource.connect(
        baseUrl: 'http://127.0.0.1:8080',
        client: client,
      );

      expect(source.totalMessages, 500);
      expect(source.newestKnownId, 499);
      expect(source.reachedNewest, isTrue);
      expect(source.reachedOldest, isFalse);
      expect(source.oldestKnownId, isNull);

      source.dispose();
    });
  });
}
