import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A package's own closed operations, as every emitting package declares.
enum _TestOp implements DiagnosticOp { started, failed }

/// One line [ChatDiagnostics.developer] wrote.
typedef _Line = ({
  String message,
  String name,
  int level,
  Object? error,
  StackTrace? stackTrace,
});

ChatEvent _event({
  ChatEventLevel level = ChatEventLevel.info,
  ChatEventCategory category = ChatEventCategory.outbox,
  DiagnosticOp op = _TestOp.started,
  ChatCorrelation correlation = ChatCorrelation.none,
  Map<String, Object> fields = const {},
  Object? error,
  StackTrace? stackTrace,
}) => ChatEvent(
  time: DateTime.utc(2026, 11, 26),
  level: level,
  category: category,
  op: op,
  correlation: correlation,
  fields: fields,
  error: error,
  stackTrace: stackTrace,
);

void main() {
  test('the process-wide policy is silent until the host sets one', () {
    expect(ChatDiagnostics.current, isA<ChatDiagnosticsSilent>());
  });

  group('silent', () {
    const diagnostics = ChatDiagnostics.silent();

    test('is enabled for no level', () {
      for (final level in ChatEventLevel.values) {
        expect(diagnostics.isEnabled(level), isFalse, reason: level.name);
      }
    });

    test('builds no fields', () {
      var built = 0;
      for (final level in ChatEventLevel.values) {
        diagnostics.emit(
          level,
          ChatEventCategory.media,
          _TestOp.started,
          fields: () {
            built++;
            return const {'count': 1};
          },
        );
      }
      expect(built, 0);
    });

    test('drops a reported event', () {
      expect(() => diagnostics.report(_event()), returnsNormally);
    });
  });

  group('developer', () {
    late List<_Line> lines;
    late ChatDiagnostics diagnostics;

    setUp(() {
      lines = [];
      diagnostics = ChatDiagnostics.developer(
        log:
            (
              message, {
              required name,
              required level,
              error,
              stackTrace,
              time,
            }) => lines.add((
              message: message,
              name: name,
              level: level,
              error: error,
              stackTrace: stackTrace,
            )),
      );
    });

    test('logs under one name per category', () {
      for (final category in ChatEventCategory.values) {
        diagnostics.report(_event(category: category));
      }
      expect(lines.map((line) => line.name), [
        for (final category in ChatEventCategory.values)
          'chat.${category.name}',
      ]);
    });

    test('maps each level onto a rising log level', () {
      for (final level in ChatEventLevel.values) {
        expect(diagnostics.isEnabled(level), isTrue, reason: level.name);
        diagnostics.report(_event(level: level));
      }
      final levels = lines.map((line) => line.level).toList();
      expect(levels, orderedEquals([...levels]..sort()));
      expect(levels.toSet(), hasLength(ChatEventLevel.values.length));
    });

    test('writes the op, ids and fields, and passes the error on', () {
      final stackTrace = StackTrace.current;
      diagnostics.report(
        _event(
          op: _TestOp.failed,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'm7',
          ),
          fields: const {'attempt': 2, 'reason': 'timeout'},
          error: StateError('boom'),
          stackTrace: stackTrace,
        ),
      );
      final line = lines.single;
      expect(line.message, contains('failed'));
      expect(line.message, contains('chatId=c1'));
      expect(line.message, contains('clientMessageId=m7'));
      expect(line.message, contains('attempt=2'));
      expect(line.message, contains('reason=timeout'));
      expect(line.error, isA<StateError>());
      expect(line.stackTrace, same(stackTrace));
    });

    test('swallows a throwing log', () {
      final throwing = ChatDiagnostics.developer(
        log:
            (
              message, {
              required name,
              required level,
              error,
              stackTrace,
              time,
            }) => throw StateError('sink down'),
      );
      expect(() => throwing.report(_event()), returnsNormally);
    });
  });

  group('onEvent', () {
    test('receives every event a call site emits, fields built once', () {
      final received = <ChatEvent>[];
      final diagnostics = ChatDiagnostics.onEvent(received.add);
      var built = 0;

      for (final level in ChatEventLevel.values) {
        diagnostics.emit(
          level,
          ChatEventCategory.rebase,
          _TestOp.failed,
          correlation: const ChatCorrelation(scrollId: '42'),
          fields: () {
            built++;
            return {'level': level};
          },
        );
      }

      expect(built, ChatEventLevel.values.length);
      expect(received.map((event) => event.level), ChatEventLevel.values);
      final first = received.first;
      expect(first.category, ChatEventCategory.rebase);
      expect(first.op, _TestOp.failed);
      expect(first.correlation, const ChatCorrelation(scrollId: '42'));
      expect(first.fields, {'level': ChatEventLevel.trace});
    });

    test('swallows a throwing callback', () {
      final diagnostics = ChatDiagnostics.onEvent(
        (_) => throw StateError('host bug'),
      );
      expect(() => diagnostics.report(_event()), returnsNormally);
      expect(
        () => diagnostics.emit(
          ChatEventLevel.error,
          ChatEventCategory.save,
          _TestOp.failed,
        ),
        returnsNormally,
      );
    });

    test('below its minimum level, drops events and builds no fields', () {
      final received = <ChatEvent>[];
      final diagnostics = ChatDiagnostics.onEvent(
        received.add,
        minLevel: ChatEventLevel.warning,
      );
      var built = 0;

      for (final level in ChatEventLevel.values) {
        diagnostics.emit(
          level,
          ChatEventCategory.capabilities,
          _TestOp.started,
          fields: () {
            built++;
            return const {};
          },
        );
      }
      diagnostics.report(_event(level: ChatEventLevel.debug));

      expect(diagnostics.isEnabled(ChatEventLevel.info), isFalse);
      expect(diagnostics.isEnabled(ChatEventLevel.warning), isTrue);
      expect(built, 2);
      expect(received.map((event) => event.level), [
        ChatEventLevel.warning,
        ChatEventLevel.error,
      ]);
    });
  });

  group('ChatEvent', () {
    test('is equal by value', () {
      final stackTrace = StackTrace.current;
      ChatEvent build() => _event(
        correlation: const ChatCorrelation(mediaKey: 'k', jobId: 'j'),
        fields: {'bytes': 10, 'ok': true, 'kind': _TestOp.started},
        error: 'e',
        stackTrace: stackTrace,
      );
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(build(), isNot(_event()));
      expect(
        _event(fields: {'bytes': 10}),
        isNot(_event(fields: {'bytes': 11})),
      );
    });

    test('keeps its own copy of the fields', () {
      final fields = <String, Object>{'count': 1};
      final event = _event(fields: fields);
      fields['count'] = 2;
      expect(event.fields, {'count': 1});
      expect(() => event.fields['count'] = 3, throwsUnsupportedError);
    });

    test('takes numbers, booleans, enum values and short strings', () {
      expect(
        () => _event(
          fields: {
            'count': 3,
            'ratio': 0.5,
            'ok': false,
            'level': ChatEventLevel.debug,
            'reason': 'x' * 64,
          },
        ),
        returnsNormally,
      );
    });

    test('rejects a string longer than 64 characters', () {
      expect(
        () => _event(fields: {'reason': 'x' * 65}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a nested map or a list', () {
      expect(
        () => _event(
          fields: {
            'nested': {'a': 1},
          },
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => _event(
          fields: {
            'list': const [1],
          },
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ChatCorrelation', () {
    test('is equal by value and none carries no id', () {
      expect(
        const ChatCorrelation(chatId: 'a', mediaItemId: 'i'),
        const ChatCorrelation(chatId: 'a', mediaItemId: 'i'),
      );
      expect(
        const ChatCorrelation(chatId: 'a'),
        isNot(const ChatCorrelation(chatId: 'b')),
      );
      expect(ChatCorrelation.none.entries, isEmpty);
      expect(ChatCorrelation.none.isEmpty, isTrue);
      expect(const ChatCorrelation(jobId: 'j').isEmpty, isFalse);
    });
  });
}
