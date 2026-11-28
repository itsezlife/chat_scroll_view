import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_upload_transport.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/fake_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/fake_server_script_sheet.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/outbox_debug_actions.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/outbox_debug_panel.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_view.dart';
import 'package:chat_scroll_view_example/src/features/logs/view/journal_page.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

void main() {
  const chat = 'c1';
  const secret = 'meet me at the usual place';
  const url = 'https://example.com/private/path';

  late RecordingDiagnostics diagnostics;
  late FakeChatServer server;
  late DemoOutbox demo;
  late DemoOutboxChat bound;
  late _FakeEngine engine;
  late int exits;
  late OutboxDebugActions actions;
  late DiagnosticsJournal journal;
  late DemoUploadTransport transport;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    server = FakeChatServer(peerDelay: Duration.zero);
    demo = DemoOutbox(transfers: FakeOutboxTransfers(), server: server);
    engine = _FakeEngine();
    exits = 0;
    actions = OutboxDebugActions(engine: engine, exit: () => exits++);
    journal = DiagnosticsJournal.memory();
    transport = DemoUploadTransport(latency: Duration.zero);
  });

  tearDown(() async {
    actions.dispose();
    journal.dispose();
    await demo.dispose();
  });

  // A failed send stays in the provisional tail, so the snapshot has a row.
  Future<String> failedSend(WidgetTester tester, String text) async {
    server.script(chat, FakeServerScript.reject);
    final message = bound.sendText(text)!;
    await tester.pump();
    await tester.pump();
    return message.clientMessageId;
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bound = demo.chat(chat);
    await bound.attach(GeneratedChatDataSource(messageCount: 5));
    await tester.pumpWidget(
      ChromeThemeScope(
        palette: const ChromePalette.dark(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  OutboxDebugPanel.route(
                    outbox: demo,
                    chatId: chat,
                    actions: actions,
                    journal: journal,
                    transport: transport,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> refresh(WidgetTester tester) =>
      tester.pump(OutboxDebugPanel.defaultRefresh);

  List<Object?> reported() => [
    for (final event in diagnostics.events)
      if (event.op == OutboxDebugOp.debugAction) event.fields['action'],
  ];

  testWidgets('reads the chrome face', (tester) async {
    await open(tester);
    expectChromeText(tester, within: find.byType(OutboxDebugPanel));
  });

  testWidgets("shows the outbox's tail beside the engine's snapshot", (
    tester,
  ) async {
    await open(tester);
    final clientMessageId = await failedSend(tester, 'hello');
    await refresh(tester);

    expect(
      find.byKey(OutboxDebugPanel.rowKey(clientMessageId)),
      findsOneWidget,
    );
    expect(find.textContaining(clientMessageId), findsOneWidget);
    expect(find.textContaining('failed'), findsWidgets);
    expect(find.textContaining('sequentialServerIds'), findsOneWidget);
    expect(find.text('file'), findsOneWidget, reason: 'the journal store');
    expect(find.text('chat.send'), findsOneWidget, reason: 'the publishers');
  });

  testWidgets('updates when either snapshot changes', (tester) async {
    await open(tester);
    expect(find.byKey(OutboxDebugPanel.counterKey('partsInFlight')), findsOne);
    expect(_counter(tester, 'partsInFlight'), '0');

    engine.partsInFlight = 3;
    final clientMessageId = await failedSend(tester, 'later');
    await refresh(tester);

    expect(_counter(tester, 'partsInFlight'), '3');
    expect(
      find.byKey(OutboxDebugPanel.rowKey(clientMessageId)),
      findsOneWidget,
    );
  });

  testWidgets('counts parts in flight, retries, rebases by reason, conflicts '
      'and restores', (tester) async {
    engine
      ..partsInFlight = 2
      ..partRetries = 4;
    await open(tester);
    await failedSend(tester, 'one');
    // A peer's message lands before the failed row: the tail moves up.
    server.postPeer(chat);
    await tester.pump();
    await refresh(tester);

    expect(_counter(tester, 'partsInFlight'), '2');
    expect(_counter(tester, 'partRetries'), '4');
    expect(_counter(tester, 'retries'), '0');
    expect(_counter(tester, 'conflicts'), '0');
    expect(_counter(tester, 'restores'), '0');
    expect(
      _counter(tester, 'rebases'),
      contains('incoming 1'),
      reason: "the peer's message moved the tail",
    );
  });

  testWidgets('shows no user content: no message text and no URL', (
    tester,
  ) async {
    await open(tester);
    await failedSend(tester, '$secret $url');
    await refresh(tester);

    expect(find.textContaining('usual place'), findsNothing);
    expect(find.textContaining('example.com'), findsNothing);
  });

  testWidgets('each action reaches its hook, and a kill ends the process '
      '3 s later', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(OutboxDebugPanel.cutKey));
    await tester.pump();
    expect(engine.cuts, [true]);

    await tester.tap(find.byKey(OutboxDebugPanel.interruptKey));
    await tester.pump();
    expect(engine.interruptions, 1);

    await tester.tap(find.byKey(OutboxDebugPanel.killKey));
    await tester.pump(const Duration(milliseconds: 2900));
    expect(exits, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(exits, 1);

    expect(reported(), ['cutNetwork', 'systemInterruption', 'killIn3s']);
  });

  testWidgets('a burst of taps on an action acts once', (tester) async {
    await open(tester);

    for (final key in [
      OutboxDebugPanel.cutKey,
      OutboxDebugPanel.interruptKey,
      OutboxDebugPanel.killKey,
    ]) {
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.pump(const Duration(seconds: 3));

    expect(engine.cuts, [true]);
    expect(engine.interruptions, 1);
    expect(exits, 1);
    expect(reported(), ['cutNetwork', 'systemInterruption', 'killIn3s']);
  });

  testWidgets("the transport's switches fail its next call and change its "
      'latency', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(OutboxDebugPanel.failNextKey));
    await tester.pump();
    expect(transport.failNext, 1);

    await tester.tap(find.byKey(OutboxDebugPanel.latencyKey(1000)));
    await tester.pump();
    expect(transport.latency, const Duration(milliseconds: 1000));
  });

  testWidgets("opens the fake server's script sheet", (tester) async {
    await open(tester);

    await tester.tap(find.byKey(FakeServerScriptSheet.openKey));
    await tester.pumpAndSettle();

    expect(find.byType(FakeServerScriptSheet), findsOneWidget);
  });

  testWidgets('a row of the tail opens the logs of its message', (
    tester,
  ) async {
    await open(tester);
    final clientMessageId = await failedSend(tester, 'hello');
    await refresh(tester);

    await tester.tap(find.byKey(OutboxDebugPanel.rowKey(clientMessageId)));
    await tester.pumpAndSettle();

    final page = tester.widget<JournalPage>(find.byType(JournalPage));
    expect(page.filter?.ids, {JournalIdKind.clientMessageId: clientMessageId});
  });
}

String _counter(WidgetTester tester, String name) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(OutboxDebugPanel.counterKey(name)),
        matching: find.byKey(OutboxDebugPanel.valueKey),
      ),
    )
    .data!;

final class _FakeEngine implements TransferDebugHooks {
  final List<bool> cuts = [];
  int interruptions = 0;
  int partsInFlight = 0;
  int partRetries = 0;

  @override
  TransfersDebugSnapshot snapshot() => TransfersDebugSnapshot(
    jobs: const [],
    online: cuts.isEmpty || !cuts.last,
    journal: const JournalDebugSnapshot(
      store: 'file',
      bytes: 2048,
      recordsSinceCompaction: 3,
    ),
    uploads: UploadsDebugSnapshot(
      lanes: const {
        UploadLane.small: UploadLaneDebugSnapshot(queued: 0),
        UploadLane.big: UploadLaneDebugSnapshot(queued: 1),
      },
      partsInFlight: partsInFlight,
      partRetries: partRetries,
      restartsFromZero: 0,
    ),
    publish: PublishDebugSnapshot(
      jobs: const [],
      publishers: const ['chat.send'],
    ),
  );

  @override
  void cutNetwork({required bool cut}) => cuts.add(cut);

  @override
  int simulateSystemInterruption() {
    interruptions++;
    return 0;
  }
}
