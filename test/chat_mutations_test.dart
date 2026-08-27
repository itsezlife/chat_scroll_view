import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_mutations.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_data_source_ext.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chat_message.dart';

IChatMessage _msg(int id, {String content = 'm'}) => UserChatMessage(
  id: id,
  sender: 'u',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: '$content$id',
);

class _SpyDataSource extends ChatDataSource {
  _SpyDataSource({this.fetchHandler}) {
    _seedDefaultBoundaries(this);
  }

  final Future<List<IChatMessage>> Function({
    required int fromId,
    required int toId,
  })?
  fetchHandler;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    if (fetchHandler != null) {
      return fetchHandler!(fromId: fromId, toId: toId);
    }
    return const <IChatMessage>[];
  }
}

void _seedDefaultBoundaries(_SpyDataSource ds) {
  ds.seedBoundaries(
    oldestKnownId: 0,
    newestKnownId: 99,
    reachedOldest: true,
    reachedNewest: true,
  );
}

void main() {
  group('insertMessage', () {
    test('emits one insert mutation and one data-changed', () {
      final ds = _SpyDataSource();
      final mutations = <ChatMutation>[];
      var dataChanges = 0;
      ds
        ..addMutationListener(mutations.add)
        ..addDataListener(() => dataChanges++);

      ds.insertMessage(_msg(100));

      expect(mutations, hasLength(1));
      expect(mutations.single, isA<InsertMutation>());
      expect((mutations.single as InsertMutation).messageId, 100);
      expect(dataChanges, 1);
      expect(ds.getMessage(100)?.id, 100);
      expect(ds.newestKnownId, 100);
    });

    test('upsertMessages for same id emits zero mutations', () {
      final ds = _SpyDataSource();
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);

      ds
        ..insertMessage(_msg(50))
        ..upsertMessages([_msg(50, content: 'merged')]);

      expect(mutations, hasLength(1));
      expect(mutations.single, isA<InsertMutation>());
    });

    test(
      'newest-only seed then tail insert keeps oldest null and advances newest',
      () {
        final ds = _SpyDataSource()
          ..seedBoundaries(
            oldestKnownId: null,
            newestKnownId: 10004,
            reachedOldest: false,
            reachedNewest: true,
          );

        ds.insertMessage(_msg(10005));

        expect(ds.oldestKnownId, isNull);
        expect(ds.newestKnownId, 10005);
        expect(ds.reachedNewest, isTrue);
        expect(ds.reachedOldest, isFalse);
      },
    );

    test(
      'newest-only seed then older insert seeds oldest without moving newest',
      () {
        final ds = _SpyDataSource()
          ..seedBoundaries(
            oldestKnownId: null,
            newestKnownId: 10004,
            reachedOldest: false,
            reachedNewest: true,
          );

        ds.insertMessage(_msg(10000));

        expect(ds.oldestKnownId, 10000);
        expect(ds.newestKnownId, 10004);
        expect(ds.reachedNewest, isTrue);
      },
    );
  });

  group('insertMessages batch', () {
    test(
      'emits one batch mutation with ascending ids and one data-changed',
      () {
        final ds = _SpyDataSource();
        final mutations = <ChatMutation>[];
        var dataChanges = 0;
        ds
          ..addMutationListener(mutations.add)
          ..addDataListener(() => dataChanges++);

        final batch = List.generate(10, (i) => _msg(100 + i));
        ds.insertMessages(batch.reversed);

        expect(mutations, hasLength(1));
        final mutation = mutations.single as InsertBatchMutation;
        expect(mutation.ids, List.generate(10, (i) => 100 + i));
        expect(mutation.operationId, isNonZero);
        expect(dataChanges, 1);
        expect(ds.getMessage(109)?.id, 109);
        expect(ds.newestKnownId, 109);
      },
    );

    test('insertMessages emits mutation; upsertMessages same ids silent', () {
      final ds = _SpyDataSource();
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);

      final batch = List.generate(10, (i) => _msg(200 + i));
      ds.insertMessages(batch);
      expect(mutations, hasLength(1));
      expect(mutations.single, isA<InsertBatchMutation>());

      ds.upsertMessages(batch.map((m) => _msg(m.id, content: 'merged')));
      expect(mutations, hasLength(1));
    });
  });

  group('updateMessages batch', () {
    test(
      'emits one batch mutation with ascending ids and one data-changed',
      () {
        final ds = _SpyDataSource();
        final mutations = <ChatMutation>[];
        var dataChanges = 0;
        ds
          ..addMutationListener(mutations.add)
          ..addDataListener(() => dataChanges++);
        for (var i = 10; i <= 12; i++) {
          ds.insertMessage(_msg(i));
        }

        final batch = [
          _msg(12, content: 'e'),
          _msg(10, content: 'e'),
          _msg(11, content: 'e'),
        ];
        ds.updateMessages(batch);

        expect(mutations, hasLength(4)); // 3 inserts + 1 batch update
        final mutation = mutations.last as UpdateBatchMutation;
        expect(mutation.ids, <int>[10, 11, 12]);
        expect(mutation.operationId, isNonZero);
        expect(dataChanges, 4);
        expect((ds.getMessage(11)! as UserChatMessage).content, 'e11');
      },
    );

    test('updateMessages emits mutation; upsertMessages same ids silent', () {
      final ds = _SpyDataSource();
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);
      for (var i = 20; i <= 22; i++) {
        ds.insertMessage(_msg(i));
      }

      final batch = List.generate(3, (i) => _msg(20 + i, content: 'u'));
      ds.updateMessages(batch);
      expect(mutations.last, isA<UpdateBatchMutation>());

      ds.upsertMessages(batch.map((m) => _msg(m.id, content: 'merged')));
      expect(mutations.whereType<UpdateBatchMutation>(), hasLength(1));
    });

    test('skips absent ids idempotently', () {
      final ds = _SpyDataSource()
        ..insertMessage(_msg(30))
        ..insertMessage(_msg(31));
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);

      ds.removeMessages([30]);
      ds.updateMessages([_msg(30, content: 'nope'), _msg(31, content: 'ok')]);

      expect(mutations.last, isA<UpdateBatchMutation>());
      expect((mutations.last as UpdateBatchMutation).ids, <int>[31]);
    });
  });

  group('updateMessage', () {
    test('replaces instance and emits one update mutation', () {
      final ds = _SpyDataSource()..insertMessage(_msg(10));
      final mutations = <ChatMutation>[];
      var dataChanges = 0;
      ds
        ..addMutationListener(mutations.add)
        ..addDataListener(() => dataChanges++);

      final updated = _msg(10, content: 'edited');
      ds.updateMessage(updated);

      expect(mutations.single, isA<UpdateMutation>());
      expect(dataChanges, 1);
      expect(identical(ds.getMessage(10), updated), isTrue);
    });

    test('no-op on absent id', () {
      final ds = _SpyDataSource()..insertMessage(_msg(5));
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);

      ds.removeMessages([5]);
      expect(mutations, hasLength(1));

      expect(
        () => ds.updateMessage(_msg(5, content: 'nope')),
        throwsAssertionError,
      );
      expect(mutations, hasLength(1));
    });
  });

  group('removeMessages batch', () {
    test(
      'one batch mutation with descending ids regardless of caller order',
      () {
        final ds = _SpyDataSource();
        final mutations = <ChatMutation>[];
        var dataChanges = 0;
        ds
          ..addMutationListener(mutations.add)
          ..addDataListener(() => dataChanges++);
        ds
          ..insertMessage(_msg(97))
          ..insertMessage(_msg(98))
          ..insertMessage(_msg(99));

        ds.removeMessages(<int>[98, 99, 97]);

        expect(mutations, hasLength(4)); // 3 inserts + 1 batch
        final batch = mutations.last as RemoveBatchMutation;
        expect(batch.ids, <int>[99, 98, 97]);
        expect(batch.operationId, isNonZero);
        expect(ds.pendingRemovalIds, <int>{97, 98, 99});
        expect(dataChanges, 4);
        expect(ds.newestKnownId, 96);
      },
    );

    test('staging cleared by finalizeRemoval without second mutation', () {
      final ds = _SpyDataSource()..insertMessage(_msg(42));
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);

      ds.removeMessages([42]);
      expect(ds.getStagedRemovalMessage(42)?.id, 42);
      expect(ds.getMessage(42), isNull);

      ds.finalizeRemoval(42);
      expect(ds.pendingRemovalIds, isEmpty);
      expect(mutations, hasLength(1)); // batch only
    });

    test('skips unknown and already-staged ids idempotently', () {
      final ds = _SpyDataSource()..insertMessage(_msg(10));
      final mutations = <ChatMutation>[];

      ds
        ..addMutationListener(mutations.add)
        ..removeMessages([10, 999, 10]);

      expect(mutations.last, isA<RemoveBatchMutation>());
      expect((mutations.last as RemoveBatchMutation).ids, <int>[10]);
      expect(mutations, hasLength(1));
    });
  });

  group('neighbor walks', () {
    test('skips chain of three consecutive absent ids', () {
      final ds = _SpyDataSource()
        ..insertMessage(_msg(5))
        ..insertMessage(_msg(9));
      ds.removeMessages([6, 7, 8]);

      expect(ds.getPreviousPresentMessage(9)?.id, 5);
      expect(ds.getNextPresentMessage(5)?.id, 9);
      expect(ds.getMessage(7), isNull);
      expect(ds.statusOf(7).isAbsent, isTrue);
    });

    test('supports sender-run probe after single absent gap', () {
      final ds = _SpyDataSource()
        ..insertMessage(_msg(10))
        ..insertMessage(_msg(11))
        ..insertMessage(_msg(12));
      ds.removeMessages([11]);

      expect(ds.getMessage(11), isNull);
      expect(ds.getPreviousPresentMessage(12)?.id, 10);
    });
  });

  group('fetch and invalidate silence', () {
    test('upsertMessage and invalidate emit zero mutations', () {
      final ds = _SpyDataSource();
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);

      ds
        ..upsertMessage(_msg(1))
        ..upsertMessages([_msg(2), _msg(3)])
        ..invalidate();

      expect(mutations, isEmpty);
    });
  });

  group('insert during pending removal', () {
    test('non-blocking with correct mutation order and boundaries', () {
      final ds = _SpyDataSource();
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);
      ds
        ..insertMessage(_msg(98))
        ..insertMessage(_msg(99));

      ds.removeMessages([99]);
      ds.insertMessage(_msg(100));

      expect(mutations, hasLength(4));
      expect(mutations[2], isA<RemoveBatchMutation>());
      expect(mutations[3], isA<InsertMutation>());
      expect(ds.newestKnownId, 100);
      expect(ds.pendingRemovalIds, <int>{99});
      expect(ds.getMessage(100)?.id, 100);
    });

    test('nextInsertId skips staged tail ids after newest retracts', () {
      final ds = _SpyDataSource()
        ..insertMessage(_msg(98))
        ..insertMessage(_msg(99));
      ds.removeMessages([98, 99]);
      expect(ds.newestKnownId, lessThan(98));
      expect(ds.pendingRemovalIds, containsAll(<int>[98, 99]));
      expect(ds.nextInsertId, 100);
      ds.insertMessage(_msg(ds.nextInsertId));
      expect(ds.newestKnownId, 100);
    });
  });

  group('off-tree batch ids', () {
    test('includes never-loaded ids in one batch mutation', () {
      final ds = _SpyDataSource()..insertMessage(_msg(50));
      final mutations = <ChatMutation>[];
      ds.addMutationListener(mutations.add);

      ds.removeMessages([50, 51, 52]);

      expect((mutations.single as RemoveBatchMutation).ids, <int>[52, 51, 50]);
      expect(ds.pendingRemovalIds, <int>{50, 51, 52});
      expect(ds.statusOf(51).isAbsent, isTrue);
      expect(ds.statusOf(52).isAbsent, isTrue);
      expect(ds.getStagedRemovalMessage(50), isNotNull);
      expect(ds.getStagedRemovalMessage(51), isNull);

      ds
        ..finalizeRemoval(51)
        ..finalizeRemoval(52)
        ..finalizeRemoval(50);
      expect(ds.pendingRemovalIds, isEmpty);
    });
  });

  group('fetch merge respects local deletes', () {
    test('does not resurrect removed message from fetchRange payload', () async {
      final ds = _SpyDataSource(
        fetchHandler: ({required fromId, required toId}) async =>
            <IChatMessage>[_msg(10), _msg(11)],
      )
        ..insertMessage(_msg(10))
        ..insertMessage(_msg(11));

      ds.removeMessages([10, 11]);
      expect(ds.getMessage(10), isNull);
      expect(ds.getMessage(11), isNull);

      // Simulate engine LRU eviction before a later refetch.
      ds.chunks.clear();

      ds.requestChunks(0, 0);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ds.getMessage(10), isNull);
      expect(ds.getMessage(11), isNull);
      expect(ds.pendingRemovalIds, containsAll(<int>[10, 11]));
    });
  });

  group('mutation listener dedup', () {
    test('same listener registered once fires once', () {
      final ds = _SpyDataSource();
      var count = 0;
      void listener(ChatMutation _) => count++;
      ds
        ..addMutationListener(listener)
        ..addMutationListener(listener)
        ..insertMessage(_msg(1));

      expect(count, 1);
    });
  });
}
