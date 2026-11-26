import 'dart:io';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

enum _TestOp implements DiagnosticOp { queued, sent, failed }

void main() {
  group('RecordingDiagnostics', () {
    late RecordingDiagnostics diagnostics;

    setUp(() {
      diagnostics = RecordingDiagnostics()
        ..emit(
          ChatEventLevel.info,
          ChatEventCategory.outbox,
          _TestOp.queued,
          correlation: const ChatCorrelation(chatId: 'c', clientMessageId: 'a'),
          fields: () => const {'items': 2},
        )
        ..emit(
          ChatEventLevel.debug,
          ChatEventCategory.media,
          _TestOp.sent,
          correlation: const ChatCorrelation(
            chatId: 'c',
            clientMessageId: 'b',
            mediaKey: 'k1',
          ),
        )
        ..emit(
          ChatEventLevel.error,
          ChatEventCategory.outbox,
          _TestOp.failed,
          correlation: const ChatCorrelation(chatId: 'd', clientMessageId: 'a'),
        );
    });

    test('records every event in order, at every level', () {
      expect(ChatEventLevel.values.every(diagnostics.isEnabled), isTrue);
      expect(diagnostics.events.map((event) => event.op), [
        _TestOp.queued,
        _TestOp.sent,
        _TestOp.failed,
      ]);
    });

    test('finds events by category and by op', () {
      expect(
        diagnostics.whereCategory(ChatEventCategory.outbox).map((e) => e.op),
        [_TestOp.queued, _TestOp.failed],
      );
      expect(diagnostics.whereOp(_TestOp.sent), hasLength(1));
    });

    test('finds events by correlation id, every given id matching', () {
      expect(
        diagnostics.whereCorrelated(clientMessageId: 'a').map((e) => e.op),
        [_TestOp.queued, _TestOp.failed],
      );
      expect(
        diagnostics
            .whereCorrelated(chatId: 'c', clientMessageId: 'a')
            .map((e) => e.op),
        [_TestOp.queued],
      );
      expect(
        diagnostics.whereCorrelated(mediaKey: 'k1').single.op,
        _TestOp.sent,
      );
      expect(diagnostics.whereCorrelated(jobId: 'none'), isEmpty);
    });

    test('clear forgets the recorded events', () {
      diagnostics.clear();
      expect(diagnostics.events, isEmpty);
    });
  });

  group('isChatEvent', () {
    final event = ChatEvent(
      time: DateTime.utc(2026),
      level: ChatEventLevel.warning,
      category: ChatEventCategory.linkPreview,
      op: _TestOp.failed,
      correlation: const ChatCorrelation(scrollId: '9'),
      fields: const {'host': 'example.org', 'status': 404},
    );

    test('matches the given parts and ignores the rest', () {
      expect(event, isChatEvent(op: _TestOp.failed));
      expect(
        event,
        isChatEvent(
          level: ChatEventLevel.warning,
          category: ChatEventCategory.linkPreview,
          op: _TestOp.failed,
          correlation: const ChatCorrelation(scrollId: '9'),
          fields: containsPair('status', 404),
        ),
      );
    });

    test('reports a mismatch', () {
      expect(event, isNot(isChatEvent(op: _TestOp.sent)));
      expect(event, isNot(isChatEvent(level: ChatEventLevel.error)));
      expect(event, isNot(isChatEvent(fields: {'status': 404})));
    });
  });

  group('RecordingDiagnostics.install', () {
    test('installs a recorder as the process-wide policy', () {
      final previous = ChatDiagnostics.current;
      // Tear-downs run last-registered first: the install's restore, then
      // this check.
      addTearDown(() => expect(ChatDiagnostics.current, same(previous)));
      final installed = RecordingDiagnostics.install();

      expect(ChatDiagnostics.current, same(installed));
      ChatDiagnostics.current.emit(
        ChatEventLevel.info,
        ChatEventCategory.capabilities,
        _TestOp.queued,
      );
      expect(installed.events, hasLength(1));
    });

    test(
      'restores the previous policy after a failing test',
      () async {
        final result = await Process.run(Platform.resolvedExecutable, [
          'test',
          '--reporter',
          'expanded',
          '--no-color',
          'test/testing/fixtures/install_restores_after_failure.dart',
        ]);
        final out = result.stdout as String;

        // The fixture's first test installs a recorder and fails; its second
        // test passes only if the policy it found at the start is back.
        expect(out, contains('+1 -1: Some tests failed.'), reason: out);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
