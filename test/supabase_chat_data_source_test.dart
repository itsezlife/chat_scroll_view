import 'package:chatscrollview/src/backend_chat_data_source.dart';
import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:flutter_test/flutter_test.dart';

String? _userContent(IChatMessage? message) => switch (message) {
  UserChatMessage(:final content) => content,
  _ => null,
};

void main() {
  group('BackendChatDataSource (Supabase)', () {
    test('connect seeds newest boundary from load_chat last_message', () async {
      final source = await BackendChatDataSource.connectForTest(
        (name, body) async {
          expect(name, 'load_chat');
          expect(body['chat_id'], 1);
          return {
            'chat': {
              'id': 1,
              'kind': 1,
              'parent_id': null,
              'created_at': 1583108356,
              'updated_at': 1583108356,
              'title': 'Demo',
              'avatar_url': null,
              'last_message': {
                'id': 10004,
                'sender_id': 1,
                'created_at': 1583108356,
                'kind': 0,
                'flags': 0,
                'content_preview': 'hello',
              },
              'unread_count': 53,
              'member_count': 1,
            },
          };
        },
      );

      expect(source.newestKnownId, 10004);
      expect(source.reachedNewest, isTrue);
      expect(source.reachedOldest, isFalse);

      source.dispose();
    });

    test('connect maps chat_not_found to seed hint', () async {
      expect(
        () => BackendChatDataSource.connectForTest(
          (name, _) async {
            expect(name, 'load_chat');
            return {
              'error': {
                'code': 2000,
                'slug': 'chat_not_found',
                'message': 'missing',
                'retry_after_ms': 0,
                'extra': null,
              },
            };
          },
        ),
        throwsA(
          isA<BackendConnectionException>().having(
            (e) => e.message,
            'message',
            contains('supabase db reset'),
          ),
        ),
      );
    });

    test('fetchRange maps messages and updates boundaries', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, body) async {
          if (name == 'load_messages') {
            expect(body['from_id'], 65);
            expect(body['to_id'], 128);
            return {
              'messages': [
                {
                  'id': 65,
                  'chat_id': 1,
                  'sender_id': 1,
                  'created_at': 1583108356,
                  'updated_at': 1583108356,
                  'kind': 0,
                  'flags': 0,
                  'reply_to_id': null,
                  'content': 'hello',
                  'rich_content': null,
                  'extra': {'legacy_sender': 'alice'},
                },
              ],
              'has_more': false,
              'has_older': true,
              'has_newer': true,
              'oldest_id': 1,
              'newest_id': 10004,
              'requested_from': 65,
              'requested_to': 128,
            };
          }
          fail('unexpected $name');
        },
      );
      source.seedBoundaries(newestKnownId: 10004, reachedNewest: true);

      final messages = await source.fetchRange(fromId: 65, toId: 128);

      expect(messages, hasLength(1));
      expect(messages.first.id, 65);
      expect(messages.first.sender, 'alice');
      expect(source.oldestKnownId, 65);
      expect(source.reachedOldest, isFalse);
      expect(source.reachedNewest, isTrue);

      source.dispose();
    });

    test('terminal oldest boundary sets reachedOldest', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, _) async => {
          'messages': [
            {
              'id': 1,
              'chat_id': 1,
              'sender_id': 1,
              'created_at': 1583108356,
              'updated_at': 1583108356,
              'kind': 0,
              'flags': 0,
              'reply_to_id': null,
              'content': 'first',
              'rich_content': null,
              'extra': {'legacy_sender': 'bob'},
            },
          ],
          'has_more': false,
          'has_older': false,
          'has_newer': true,
          'oldest_id': 1,
          'newest_id': 10004,
          'requested_from': 1,
          'requested_to': 64,
        },
      );
      source.seedBoundaries(newestKnownId: 10004, reachedNewest: true);

      await source.fetchRange(fromId: 1, toId: 64);

      expect(source.reachedOldest, isTrue);
      expect(source.oldestKnownId, 1);

      source.dispose();
    });

    test('structured error throws BackendConnectionException with slug', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, _) async => {
          'error': {
            'code': 9000,
            'slug': 'malformed_frame',
            'message': 'bad range',
            'retry_after_ms': 0,
            'extra': null,
          },
        },
      );

      expect(
        () => source.fetchRange(fromId: 0, toId: 10),
        throwsA(
          isA<BackendConnectionException>().having(
            (e) => e.message,
            'message',
            contains('malformed_frame'),
          ),
        ),
      );

      source.dispose();
    });

    test('getLastReadMessageId invokes get_read_state', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, body) async {
          expect(name, 'get_read_state');
          expect(body['chat_id'], 1);
          expect(body['user_id'], 1);
          return {
            'chat_id': 1,
            'user_id': 1,
            'last_read_message_id': 9951,
            'updated_at': 1710000000,
          };
        },
      );

      expect(await source.getLastReadMessageId(), 9951);

      source.dispose();
    });

    test('getLastReadMessageId returns null when no row', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, _) async {
          expect(name, 'get_read_state');
          return {
            'chat_id': 1,
            'user_id': 1,
            'last_read_message_id': null,
            'updated_at': null,
          };
        },
      );

      expect(await source.getLastReadMessageId(), isNull);

      source.dispose();
    });

    test('updateLastReadMessageId invokes update_read_state', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, body) async {
          expect(name, 'update_read_state');
          expect(body['last_read_message_id'], 10004);
          return {
            'chat_id': 1,
            'user_id': 1,
            'last_read_message_id': 10004,
            'updated_at': 1710000001,
          };
        },
      );

      await source.updateLastReadMessageId(10004);

      source.dispose();
    });

    test('read-state error throws BackendConnectionException', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, _) async => {
          'error': {
            'code': 404,
            'slug': 'message_not_found',
            'message': 'missing',
            'retry_after_ms': 0,
            'extra': null,
          },
        },
      );

      expect(
        () => source.updateLastReadMessageId(9999),
        throwsA(isA<BackendConnectionException>()),
      );

      source.dispose();
    });

    test('sendMessage upserts message and advances newest boundary', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, body) async {
          expect(name, 'send_message');
          expect(body['content'], 'hello');
          return {
            'message': {
              'id': 10005,
              'chat_id': 1,
              'sender_id': 1,
              'created_at': 1583108356,
              'updated_at': 1583108356,
              'kind': 0,
              'flags': 0,
              'reply_to_id': null,
              'content': 'hello',
              'rich_content': null,
              'extra': {'legacy_sender': 'alice'},
            },
          };
        },
      );
      source.seedBoundaries(newestKnownId: 10004, reachedNewest: true);

      final message = await source.sendMessage('hello');

      expect(message.id, 10005);
      expect(message.content, 'hello');
      expect(_userContent(source.getMessage(10005)), 'hello');
      expect(source.newestKnownId, 10005);
      expect(source.reachedNewest, isTrue);

      source.dispose();
    });

    test('sendMessage error throws without advancing boundary', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, _) async {
          expect(name, 'send_message');
          return {
            'error': {
              'code': 503,
              'slug': 'service_unavailable',
              'message': 'down',
              'retry_after_ms': 0,
              'extra': null,
            },
          };
        },
      );
      source.seedBoundaries(newestKnownId: 10004, reachedNewest: true);

      expect(
        () => source.sendMessage('fail'),
        throwsA(isA<BackendConnectionException>()),
      );
      expect(source.newestKnownId, 10004);
      expect(source.getMessage(10005), isNull);

      source.dispose();
    });

    test('sendMessage persists through subsequent fetchRange', () async {
      final sent = {
        'id': 10005,
        'chat_id': 1,
        'sender_id': 1,
        'created_at': 1583108356,
        'updated_at': 1583108356,
        'kind': 0,
        'flags': 0,
        'reply_to_id': null,
        'content': 'persist me',
        'rich_content': null,
        'extra': {'legacy_sender': 'alice'},
      };

      final source = BackendChatDataSource.forTest(
        invoke: (name, body) async {
          if (name == 'send_message') {
            return {'message': sent};
          }
          if (name == 'load_messages') {
            expect(body['from_id'], 10000);
            return {
              'messages': [sent],
              'has_more': false,
              'has_older': true,
              'has_newer': false,
              'oldest_id': 1,
              'newest_id': 10005,
              'requested_from': 10000,
              'requested_to': 10005,
            };
          }
          fail('unexpected $name');
        },
      );
      source.seedBoundaries(newestKnownId: 10004, reachedNewest: true);

      await source.sendMessage('persist me');
      final messages = await source.fetchRange(fromId: 10000, toId: 10005);

      expect(messages, hasLength(1));
      expect(messages.first.id, 10005);
      expect(_userContent(messages.first), 'persist me');

      source.dispose();
    });

    test('realtime INSERT updates message and newest boundary', () async {
      final source = BackendChatDataSource.forTest(
        invoke: (name, _) async => fail('unexpected $name'),
      );
      source.seedBoundaries(newestKnownId: 10004, reachedNewest: true);

      source.applyRealtimeInsertForTest({
        'id': 10006,
        'chat_id': 1,
        'sender_id': 2,
        'created_at': 1583108356,
        'updated_at': 1583108356,
        'kind': 0,
        'flags': 0,
        'reply_to_id': null,
        'content': 'from peer',
        'rich_content': null,
        'extra': {'legacy_sender': 'bob'},
      });

      expect(_userContent(source.getMessage(10006)), 'from peer');
      expect(source.newestKnownId, 10006);

      source.dispose();
    });

    test('sendMessage and realtime INSERT for same id are idempotent', () async {
      final messageJson = {
        'id': 10005,
        'chat_id': 1,
        'sender_id': 1,
        'created_at': 1583108356,
        'updated_at': 1583108356,
        'kind': 0,
        'flags': 0,
        'reply_to_id': null,
        'content': 'once',
        'rich_content': null,
        'extra': {'legacy_sender': 'alice'},
      };

      final source = BackendChatDataSource.forTest(
        invoke: (name, _) async {
          expect(name, 'send_message');
          return {'message': messageJson};
        },
      );
      source.seedBoundaries(newestKnownId: 10004, reachedNewest: true);

      await source.sendMessage('once');
      source.applyRealtimeInsertForTest(messageJson);

      expect(_userContent(source.getMessage(10005)), 'once');
      var slotsWithId = 0;
      for (final chunk in source.chunks.values) {
        for (final message in chunk.messages) {
          if (message?.id == 10005) slotsWithId++;
        }
      }
      expect(slotsWithId, 1);

      source.dispose();
    });
  });
}
