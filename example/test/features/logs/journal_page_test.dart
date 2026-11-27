/// The Logs screen filters the journal by level, category and correlation
/// id, opens on one message's events, and exports a file of plain records.
///
/// **Seams:** [JournalViewController] over a [DiagnosticsJournal] (filters,
/// export), [JournalPage] as its route pushes it (chrome text, the export
/// button's guard, the capabilities at the top), and the message menu's
/// "Logs of this message" row.
library;

import 'dart:async';
import 'dart:convert';

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chat_scroll_view_example/src/features/logs/controller/journal_view_controller.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_record.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_view.dart';
import 'package:chat_scroll_view_example/src/features/logs/view/journal_page.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:listen/listen.dart' as listen;

enum _Op implements DiagnosticOp { shown, failed }

void _emit(
  DiagnosticsJournal journal, {
  ChatEventLevel level = ChatEventLevel.info,
  ChatEventCategory category = ChatEventCategory.media,
  ChatCorrelation correlation = ChatCorrelation.none,
  Object? error,
}) => journal.chatDiagnostics.emit(
  level,
  category,
  level == ChatEventLevel.error ? _Op.failed : _Op.shown,
  correlation: correlation,
  error: error,
);

/// A share sheet that takes its time: it is up until [close].
final class _ShareSheet {
  final files = <JournalExportFile>[];
  Completer<void> _open = Completer<void>();

  Future<void> share(JournalExportFile file, {Rect? origin}) {
    files.add(file);
    return _open.future;
  }

  void close() {
    _open.complete();
    _open = Completer<void>();
  }
}

void main() {
  group('the filter', () {
    late DiagnosticsJournal journal;
    late JournalViewController controller;

    setUp(() {
      journal = DiagnosticsJournal.memory();
      controller = JournalViewController(
        journal: journal,
        share: (_, {origin}) async {},
      );
      addTearDown(journal.dispose);
      addTearDown(controller.dispose);
    });

    test('keeps the records of each correlation id, newest first', () {
      const ids = {
        JournalIdKind.chatId: ChatCorrelation(chatId: 'c1'),
        JournalIdKind.scrollId: ChatCorrelation(scrollId: '42'),
        JournalIdKind.clientMessageId: ChatCorrelation(clientMessageId: 'm1'),
        JournalIdKind.mediaItemId: ChatCorrelation(mediaItemId: 'i1'),
        JournalIdKind.mediaKey: ChatCorrelation(mediaKey: 'k1'),
        JournalIdKind.jobId: ChatCorrelation(jobId: 'j1'),
      };
      for (final correlation in ids.values) {
        _emit(journal, correlation: correlation);
        _emit(journal, correlation: correlation);
      }
      _emit(journal);
      // Another message of the same chat.
      _emit(
        journal,
        correlation: const ChatCorrelation(chatId: 'c1', scrollId: '7'),
      );

      for (final MapEntry(key: kind, value: correlation) in ids.entries) {
        final id = kind.of(correlation)!;
        controller.filterById(kind, id);
        final visible = controller.snapshot.visible;
        expect(visible, isNotEmpty, reason: kind.name);
        expect(
          visible.every((record) => kind.of(record.correlation) == id),
          isTrue,
          reason: kind.name,
        );
        controller.filterById(kind, '');
      }
      controller.filterById(JournalIdKind.scrollId, '42');
      expect(controller.snapshot.visible, hasLength(2));
      controller
        ..filterById(JournalIdKind.scrollId, '')
        ..filterById(JournalIdKind.chatId, 'c1');
      expect(controller.snapshot.visible, hasLength(3));
      expect(
        controller.snapshot.visible.first.correlation.scrollId,
        '7',
        reason: 'newest first',
      );
    });

    test('by level and category, counting each level under the rest', () {
      _emit(journal, category: ChatEventCategory.outbox);
      _emit(
        journal,
        level: ChatEventLevel.error,
        category: ChatEventCategory.outbox,
      );
      _emit(journal, level: ChatEventLevel.error);
      journal.bytesDiagnostics.report(
        const BytesLogEvent(
          level: BytesLogLevel.warning,
          message: 'stale',
          op: BytesLogOp.resolveStaleUsed,
        ),
      );

      controller.soloLevel(ChatEventLevel.error);
      expect(controller.snapshot.visible, hasLength(2));
      controller.soloCategory('outbox');
      expect(controller.snapshot.visible, hasLength(1));
      expect(controller.snapshot.countOf(ChatEventLevel.info), 1);
      controller
        ..soloLevel(ChatEventLevel.error)
        ..soloCategory('bytes');
      expect(controller.snapshot.visible.single.source, JournalSource.bytes);
      expect(controller.snapshot.categories, ['bytes', 'media', 'outbox']);
    });

    test('"logs of this message" keeps that message\'s records alone', () {
      _emit(journal, correlation: const ChatCorrelation(scrollId: '3'));
      _emit(journal, correlation: const ChatCorrelation(scrollId: '30'));
      _emit(journal);
      final ofMessage = JournalViewController(
        journal: journal,
        share: (_, {origin}) async {},
        filter: JournalFilter.ofMessage('3'),
      );
      addTearDown(ofMessage.dispose);

      expect(ofMessage.snapshot.visible.single.correlation.scrollId, '3');
      expect(ofMessage.filter.ids, {JournalIdKind.scrollId: '3'});
    });

    testWidgets('shows what arrived while paused only on resume, and counts '
        'it', (tester) async {
      final paused = JournalViewController(
        journal: journal,
        share: (_, {origin}) async {},
      );
      _emit(journal);
      await tester.pump(const Duration(milliseconds: 300));
      expect(paused.snapshot.visible, hasLength(1));

      paused.pause();
      _emit(journal);
      _emit(journal);
      await tester.pump(const Duration(milliseconds: 300));
      expect(paused.snapshot.visible, hasLength(1));
      expect(paused.newCount, 2);

      paused.resume();
      expect(paused.snapshot.visible, hasLength(3));
      expect(paused.newCount, 0);
      paused.dispose();
      journal.flush();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('the export', () {
    test('is a header line, then one JSON line per visible record, oldest '
        'first', () async {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);
      final sheet = _ShareSheet();
      final controller = JournalViewController(
        journal: journal,
        share: sheet.share,
        filter: JournalFilter.ofMessage('5'),
        clock: () => DateTime(2026, 11, 27, 9, 30, 15),
      );
      addTearDown(controller.dispose);
      for (var n = 0; n < 3; n++) {
        _emit(journal, correlation: const ChatCorrelation(scrollId: '5'));
      }
      _emit(journal, correlation: const ChatCorrelation(scrollId: '6'));
      controller.filterById(JournalIdKind.scrollId, '5');
      final recorder = RecordingDiagnostics.install();

      final done = controller.export();
      sheet.close();
      await done;

      final file = sheet.files.single;
      expect(file.name, 'chat_log_2026-11-27_09-30-15.jsonl');
      final [header, ...records] = const LineSplitter().convert(
        utf8.decode(file.bytes),
      );
      expect(
        jsonDecode(header),
        allOf(
          containsPair('journal', 1),
          containsPair('records', 3),
          containsPair('build', 'debug'),
          contains('platform'),
          containsPair('filter', containsPair('ids', {'scrollId': '5'})),
        ),
      );
      expect(records, hasLength(3));
      final times = [
        for (final line in records) JournalRecord.tryParse(line)!.time,
      ];
      expect(times, orderedEquals([...times]..sort()));
      expect(recorder.events, [
        isChatEvent(
          level: ChatEventLevel.info,
          category: ChatEventCategory.diagnostics,
          op: JournalOp.exported,
          fields: containsPair('records', 3),
        ),
      ]);
    });

    test('carries no user content: a message with text and a URL leaves '
        'neither in the file', () async {
      const text = 'Meet me at the north entrance';
      const url = 'https://files.example.com/u/1234/report.pdf?token=s3cr3t';
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);
      final sheet = _ShareSheet();
      final controller = JournalViewController(
        journal: journal,
        share: sheet.share,
      );
      addTearDown(controller.dispose);
      // The paths a message with that text and link goes through report it
      // by its ids; the failures carry the URL in their error, and the bytes
      // cache names it in its message.
      _emit(
        journal,
        category: ChatEventCategory.linkPreview,
        correlation: const ChatCorrelation(chatId: 'c1', scrollId: '9'),
      );
      _emit(
        journal,
        level: ChatEventLevel.error,
        category: ChatEventCategory.linkPreview,
        correlation: const ChatCorrelation(chatId: 'c1', scrollId: '9'),
        error: 'HttpException: Connection closed, uri = $url',
      );
      journal.bytesDiagnostics.report(
        const BytesLogEvent(
          level: BytesLogLevel.error,
          message: 'bytes store: write of $url for "$text" failed',
          op: BytesLogOp.writeThrough,
        ),
      );

      final done = controller.export();
      sheet.close();
      await done;

      final content = utf8.decode(sheet.files.single.bytes);
      expect(content, contains('files.example.com'));
      expect(content, isNot(contains('north entrance')));
      expect(content, isNot(contains('report.pdf')));
      expect(content, isNot(contains('/u/1234')));
      expect(content, isNot(contains('s3cr3t')));
    });

    test('a share that fails is reported', () async {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);
      final controller = JournalViewController(
        journal: journal,
        share: (_, {origin}) async => throw StateError('no sheet'),
      );
      addTearDown(controller.dispose);
      _emit(journal);
      final recorder = RecordingDiagnostics.install();

      await controller.export();

      expect(recorder.events, [
        isChatEvent(
          level: ChatEventLevel.error,
          op: JournalOp.exportFailed,
          error: isA<StateError>(),
        ),
      ]);
      expect(controller.isExporting, isFalse);
    });
  });

  group('the screen', () {
    Future<(DiagnosticsJournal, _ShareSheet)> pushLogs(
      WidgetTester tester, {
      JournalFilter? filter,
      listen.ValueListenable<ChatCapabilities>? capabilities,
    }) async {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);
      _emit(journal, correlation: const ChatCorrelation(scrollId: '4'));
      _emit(
        journal,
        level: ChatEventLevel.warning,
        correlation: const ChatCorrelation(scrollId: '4'),
      );
      journal.flush();
      final sheet = _ShareSheet();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: MaterialApp(
            navigatorKey: navigator,
            home: const SizedBox.expand(),
          ),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          JournalPage.route(
            journal: journal,
            filter: filter,
            capabilities: capabilities,
            share: sheet.share,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (journal, sheet);
    }

    testWidgets('reads the chrome face, and so does a record\'s details '
        'dialog', (tester) async {
      await pushLogs(tester);

      expect(find.text('media.shown'), findsNWidgets(2));
      expectChromeText(tester, within: find.byType(JournalPage));

      await tester.tap(find.text('media.shown').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expectChromeText(tester, within: find.byType(AlertDialog));
    });

    testWidgets('a burst of taps on export shares one file', (tester) async {
      final (_, sheet) = await pushLogs(tester);

      final export = find.byKey(const ValueKey('journal-export'));
      for (var i = 0; i < 5; i++) {
        await tester.tap(export);
      }
      await tester.pump();
      expect(sheet.files, hasLength(1));

      sheet.close();
      await tester.pump();
      await tester.tap(export);
      await tester.pump();
      expect(sheet.files, hasLength(2), reason: 'a later tap exports again');
      sheet.close();
      await tester.pumpAndSettle();
    });

    testWidgets("opened on a message from a chat, shows the chat's "
        'capabilities at the top', (tester) async {
      final capabilities = listen.ValueNotifier(
        const ChatCapabilities(
          sending: SendingCapabilities(
            stickers: Capability.denied(DenialReason.everyone()),
          ),
        ),
      );
      addTearDown(capabilities.dispose);
      await pushLogs(
        tester,
        filter: JournalFilter.ofMessage('4'),
        capabilities: capabilities,
      );

      final header = find.byKey(const ValueKey('journal-capabilities'));
      expect(header, findsOneWidget);
      expect(
        find.descendant(
          of: header,
          matching: find.textContaining('denied', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(InputChip, 'scrollId=4'), findsOneWidget);
      expect(find.text('Showing 2 of 2'), findsOneWidget);
    });
  });

  group('the message menu', () {
    testWidgets('offers "Logs of this message" when the host opens logs, and '
        'hands it the message', (tester) async {
      final dataSource = _OneMessageSource();
      addTearDown(dataSource.dispose);
      final opened = <int>[];
      Future<void> open({ValueChanged<int>? onMessageLogs}) async {
        final menu = MessageMenu(
          dataSource: dataSource,
          actions: MessageMenuActions(
            onDelete: (_) {},
            onEdit: (_) {},
            onMessageLogs: onMessageLogs,
          ),
          clipboard: FakeRichClipboard(),
        );
        await tester.pumpWidget(
          ChromeThemeScope(
            palette: const ChromePalette.dark(),
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => menu.present(
                      context,
                      const ChatMessageMenuRequest(
                        messageId: 1,
                        slotGlobal: Rect.fromLTWH(0, 0, 100, 40),
                        tapGlobal: Offset(10, 10),
                        pointState: ChatMessageMenuPointState.inside,
                        membership: ChatMessageMenuMembership.idle,
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump(const Duration(seconds: 1));
      }

      await open();
      expect(find.text('Logs of this message'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await open(onMessageLogs: opened.add);
      await tester.ensureVisible(find.text('Logs of this message'));
      await tester.tap(find.text('Logs of this message'));
      await tester.pumpAndSettle();
      expect(opened, [1]);
    });
  });
}

class _OneMessageSource extends ChatDataSource {
  _OneMessageSource() {
    upsertMessages(<IChatMessage>[
      UserChatMessage(
        id: 1,
        sender: 'User',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        content: 'hello',
      ),
    ]);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}
