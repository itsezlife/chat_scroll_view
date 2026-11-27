/// The diagnostics journal keeps every event in a ring that survives a kill.
///
/// **Seam:** [DiagnosticsJournal] over a [JournalStore] (memory, and the
/// files of the VM), read back through its records and a second journal
/// over the same store.
library;

import 'dart:io';

import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/environment_specific/journal_store_vm.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/journal_store.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_record.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx/mpx.dart' show CacheDiagnosticsBridge;
import 'package:mpx_core/mpx_core.dart'
    show MediaKey, MpxDiagnostics, MpxEvent, MpxEventLevel;
import 'package:mpx_core/mpx_core.dart' as mpx show DiagnosticOp;

enum _Op implements DiagnosticOp { tick, failed }

enum _MediaOp implements mpx.DiagnosticOp {
  jobStarted;

  @override
  String get category => 'transfer';
}

ChatEvent _event(
  int n, {
  ChatEventLevel level = ChatEventLevel.info,
  ChatCorrelation correlation = ChatCorrelation.none,
}) => ChatEvent(
  time: DateTime.utc(2026, 11, 27, 12, 0, n),
  level: level,
  category: ChatEventCategory.media,
  op: level == ChatEventLevel.error ? _Op.failed : _Op.tick,
  correlation: correlation,
  fields: {'n': n},
);

List<Object?> _ns(DiagnosticsJournal journal) => [
  for (final record in journal.records) record.fields['n'],
];

void main() {
  group('in memory', () {
    test('keeps the events in the order they came', () {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);

      for (var n = 0; n < 5; n++) {
        journal.addChatEvent(_event(n));
      }

      expect(_ns(journal), [0, 1, 2, 3, 4]);
      expect(journal.records.first, isA<JournalRecord>());
      expect(journal.records.first.category, 'media');
      expect(journal.records.first.op, 'tick');
    });

    test('drops the oldest events past its cap', () {
      final line = JournalRecord.fromChatEvent(_event(0)).encode().length + 1;
      // Room for three lines, not four.
      final journal = DiagnosticsJournal.memory(capBytes: line * 3 + 1);
      addTearDown(journal.dispose);

      for (var n = 0; n < 6; n++) {
        journal.addChatEvent(_event(n));
      }

      expect(_ns(journal), [3, 4, 5]);
      expect(journal.sizeBytes, lessThanOrEqualTo(journal.capBytes));
    });

    test('writes a warning or an error, and the batch before it, before it '
        'returns; the rest waits for the batch', () async {
      final store = MemoryJournalStore();
      final journal = DiagnosticsJournal(
        store: store,
        batchInterval: const Duration(milliseconds: 20),
      );
      addTearDown(journal.dispose);

      journal.addChatEvent(_event(0));
      expect(store.lines, isEmpty, reason: 'an info waits for the batch');

      journal.addChatEvent(_event(1, level: ChatEventLevel.error));
      expect(store.lines, hasLength(2));

      journal.addChatEvent(_event(2, level: ChatEventLevel.warning));
      expect(store.lines, hasLength(3));

      journal.addChatEvent(_event(3));
      expect(store.lines, hasLength(3));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(store.lines, hasLength(4), reason: 'the batch came due');
    });

    test('restores, after a restart, what the previous run kept, before what '
        'arrived since', () async {
      final store = MemoryJournalStore();
      final first = DiagnosticsJournal(store: store);
      for (var n = 0; n < 3; n++) {
        first.addChatEvent(
          _event(n, correlation: const ChatCorrelation(scrollId: '7')),
        );
      }
      first.flush();
      // The process dies: no close, no dispose. The torn last line of a
      // write the kill cut short is in the store too.
      store.append(['{"t":1,"l":"in']);

      final second = DiagnosticsJournal(store: store);
      addTearDown(second.dispose);
      second.addChatEvent(_event(9));
      final restored = await second.restore();

      expect(restored, 3);
      expect(_ns(second), [0, 1, 2, 9]);
      expect(second.records.first.correlation.scrollId, '7');
      expect(
        second.records.first.time.isAtSameMomentAs(
          DateTime.utc(2026, 11, 27, 12),
        ),
        isTrue,
      );
    });

    test('reports its opening with what it restored', () async {
      final store = MemoryJournalStore();
      final first = DiagnosticsJournal(store: store)
        ..addChatEvent(_event(0))
        ..addChatEvent(_event(1))
        ..flush();
      addTearDown(first.dispose);
      final recorder = RecordingDiagnostics.install();

      final second = DiagnosticsJournal(store: store);
      addTearDown(second.dispose);
      await second.restore();

      expect(recorder.events, [
        isChatEvent(
          level: ChatEventLevel.info,
          category: ChatEventCategory.diagnostics,
          op: JournalOp.opened,
          fields: allOf(
            containsPair('restored', 2),
            containsPair('skipped', 0),
            containsPair('persistent', false),
          ),
        ),
      ]);
    });

    test('a store that fails is reported once, and the journal goes on in '
        'memory', () {
      final recorder = RecordingDiagnostics.install();
      final journal = DiagnosticsJournal(store: _FailingStore());
      addTearDown(journal.dispose);
      // Routed back into the journal, as the host routes it: the report of
      // the failure must not fail again.
      ChatDiagnostics.current = ChatDiagnostics.onEvent((event) {
        recorder.report(event);
        journal.addChatEvent(event);
      });

      journal
        ..addChatEvent(_event(0, level: ChatEventLevel.error))
        ..addChatEvent(_event(1, level: ChatEventLevel.error));

      expect(recorder.whereOp(JournalOp.storeFailed), [
        isChatEvent(level: ChatEventLevel.warning, fields: {'lines': 1}),
      ]);
      expect(journal.isPersistent, isFalse);
      expect(journal.length, 3);
    });
  });

  group('bridges', () {
    test("the bytes cache's events, by operation and level, without the "
        'message', () {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);

      journal.bytesDiagnostics.report(
        const BytesLogEvent(
          level: BytesLogLevel.warning,
          message:
              'BytesResolver background revalidation failed for '
              'https://cdn.example.com/u/42/photo.jpg?token=secret',
          op: BytesLogOp.revalidateBackground,
        ),
      );

      final [record] = journal.records.toList();
      expect(record.source, JournalSource.bytes);
      expect(record.category, 'bytes');
      expect(record.op, 'revalidate_background');
      expect(record.level, ChatEventLevel.warning);
      expect(record.encode(), isNot(contains('photo')));
      expect(record.encode(), isNot(contains('secret')));
    });

    test("the media side's events, ids and tag kept, errors with URLs cut to "
        'their host', () {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);

      journal.mediaDiagnostics.report(
        MpxEvent(
          time: DateTime.utc(2026, 11, 28),
          level: MpxEventLevel.error,
          op: _MediaOp.jobStarted,
          jobId: 'job-1',
          itemId: 'item-2',
          mediaKey: const MediaKey.remote('photo-3'),
          tag: 'chat-4',
          fields: const {'bytes': 10},
          error: 'GET https://cdn.example.com/u/42/photo.jpg failed',
        ),
      );

      final [record] = journal.records.toList();
      expect(record.source, JournalSource.media);
      expect(record.category, 'transfer');
      expect(record.op, 'jobStarted');
      expect(record.level, ChatEventLevel.error);
      expect(record.correlation.jobId, 'job-1');
      expect(record.correlation.mediaItemId, 'item-2');
      expect(
        record.correlation.mediaKey,
        const MediaKey.remote('photo-3').encoded,
      );
      expect(record.fields, {'bytes': 10, 'tag': 'chat-4'});
      expect(record.error, 'GET https://cdn.example.com failed');
      expect(
        JournalRecord.tryParse(record.encode())?.source,
        JournalSource.media,
      );
    });

    test("the bytes cache's events through mpx's cache bridge, category "
        'cache, without the message', () {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);
      final previous = MpxDiagnostics.current;
      MpxDiagnostics.current = journal.mediaDiagnostics;
      addTearDown(() => MpxDiagnostics.current = previous);

      CacheDiagnosticsBridge.policy.report(
        const BytesLogEvent(
          level: BytesLogLevel.warning,
          message:
              'BytesResolver background revalidation failed for '
              'https://cdn.example.com/u/42/photo.jpg?token=secret',
          op: BytesLogOp.revalidateBackground,
        ),
      );

      final [record] = journal.records.toList();
      expect(record.source, JournalSource.media);
      expect(record.category, 'cache');
      expect(record.op, 'revalidateBackground');
      expect(record.level, ChatEventLevel.warning);
      expect(record.encode(), isNot(contains('photo')));
      expect(record.encode(), isNot(contains('secret')));
    });

    test('the chat packages\' events, enum fields by name, errors with URLs '
        'cut to their host', () {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);

      journal.chatDiagnostics.emit(
        ChatEventLevel.error,
        ChatEventCategory.linkPreview,
        _Op.failed,
        correlation: const ChatCorrelation(chatId: 'c1', scrollId: '3'),
        fields: () => {'level': ChatEventLevel.debug},
        error: 'GET https://example.com/a/b?q=1 failed: connection closed',
      );

      final [record] = journal.records.toList();
      expect(record.fields, {'level': 'debug'});
      expect(record.correlation.scrollId, '3');
      expect(record.error, contains('https://example.com'));
      expect(record.error, isNot(contains('/a/b')));
      expect(record.error, isNot(contains('q=1')));
    });
  });

  group('on disk', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('journal_test');
      addTearDown(() => directory.delete(recursive: true));
    });

    test('a warning is in the file when the call returns, and a journal over '
        'the same folder restores it', () async {
      final store = await FileJournalStore.open(directory, capBytes: 1 << 20);
      final first = DiagnosticsJournal(store: store)
        ..addChatEvent(_event(0))
        ..addChatEvent(_event(1, level: ChatEventLevel.warning));

      final written = File('${directory.path}/journal.1.jsonl');
      expect(written.readAsLinesSync(), hasLength(2));
      // Killed: the store is never closed.
      first.dispose();

      final again = DiagnosticsJournal(
        store: await FileJournalStore.open(directory, capBytes: 1 << 20),
      );
      addTearDown(again.dispose);
      await again.restore();

      expect(_ns(again), [0, 1]);
      expect(again.isPersistent, isTrue);
    });

    test('the files hold about the cap: the oldest lines go first', () async {
      final line = JournalRecord.fromChatEvent(_event(10)).encode().length + 1;
      final cap = line * 8;
      final store = await FileJournalStore.open(directory, capBytes: cap);
      final journal = DiagnosticsJournal(store: store, capBytes: cap);
      for (var n = 10; n < 40; n++) {
        journal
          ..addChatEvent(_event(n))
          ..flush();
      }
      await journal.close();
      journal.dispose();

      final kept = await (await FileJournalStore.open(
        directory,
        capBytes: cap,
      )).read();
      final size = kept.fold(0, (sum, line) => sum + line.length + 1);
      expect(size, lessThanOrEqualTo(cap));
      expect(kept, isNotEmpty);
      expect(JournalRecord.tryParse(kept.last)?.fields['n'], 39);
      expect(JournalRecord.tryParse(kept.first)?.fields['n'], greaterThan(10));
    });
  });
}

final class _FailingStore implements JournalStore {
  @override
  bool get isPersistent => true;

  @override
  Future<List<String>> read() async => const [];

  @override
  void append(List<String> lines) =>
      throw const FileSystemException('No space left on device');

  @override
  Future<void> close() async {}
}
