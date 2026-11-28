/// The demo chat sends through the outbox against the fake server, as the
/// app runs it: the chat screen over a generated history, the outbox over
/// a fake transfer engine whose jobs a test moves.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/fake_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

import '../../../support/fake_soft_keyboard.dart';
import '../../../support/test_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chat = 'chat';
  const history = 200;

  late FakeSoftKeyboard keyboard;
  late FakeOutboxTransfers transfers;
  late GeneratedChatDataSource source;

  setUp(() {
    keyboard = FakeSoftKeyboard();
    transfers = FakeOutboxTransfers();
    source = GeneratedChatDataSource(messageCount: history);
  });

  tearDown(() async {
    await keyboard.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<AppServices> pumpApp(WidgetTester tester) async {
    final services = (await tester.runAsync(
      () => createTestServices(outboxTransfers: transfers),
    ))!;
    addTearDown(services.dispose);
    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        softKeyboard: keyboard,
        chatDataSourceLoader: () async => source,
      ),
    );
    await settle(tester);
    return services;
  }

  Future<void> sendFromComposer(WidgetTester tester, String text) async {
    // The composer's field is a leaf package's type, which a host does not
    // name.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'ComposerField',
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.testTextInput.enterText(text);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>(ChatComposerActions.primary)),
    );
    await settle(tester);
  }

  OutgoingMessage outgoing(AppServices services) {
    final id = transfers.requests.last.idempotencyKey!;
    return services.outbox.outbox.byClientMessageId(chat, id)!;
  }

  // A message's body is painted, not a text widget: its bubble is found by
  // the message it draws.
  Finder bubbleOf(String text) => find.byWidgetPredicate(
    (widget) => switch (widget) {
      DemoMessageBubble(message: UserChatMessage(:final content)) =>
        content.contains(text),
      _ => false,
    },
  );

  PlannedSend photo(String id) =>
      PlannedSend.single(AttachItems.photo(id), form: SendForm.media);

  const prepared = PreparedMedia(
    kind: PreparedKind.photo,
    path: '/p1.jpg',
    isOriginal: false,
    byteSize: 100,
  );

  testWidgets('a text sent at the tail shows its row and reaches sent', (
    tester,
  ) async {
    final services = await pumpApp(tester);

    await sendFromComposer(tester, 'hello outbox');

    expect(bubbleOf('hello outbox'), findsOneWidget);
    expect(outgoing(services).status, const OutgoingStatus.sent());
    expect(outgoing(services).position, history);
    expect(source.newestKnownId, history, reason: 'no twin from the echo');
    expect(source.identityOf!(source.getMessage(history)!), isNull);
  });

  testWidgets('a peer posting during an upload rebases the row with no twin '
      'and no jump', (tester) async {
    final services = await pumpApp(tester);
    services.outbox.server.script(chat, FakeServerScript.peer);

    services.outbox
        .chat(chat)
        .sendPlanned(
          [photo('p1')],
          bodies: ['an outgoing photo'],
          prepared: {const AttachItemId('p1'): prepared},
        );
    await settle(tester);
    final bubble = bubbleOf('an outgoing photo');
    final before = tester.getRect(bubble);
    expect(outgoing(services).status, const OutgoingStatus.uploading());

    // The armed peer posts a moment after the upload starts.
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    expect(bubbleOf('A peer replies'), findsOneWidget);
    expect(outgoing(services).position, history + 1);
    expect(
      tester.getRect(bubble).bottom,
      moreOrLessEquals(before.bottom, epsilon: 0.5),
      reason: 'at the tail the outgoing bubble keeps its place',
    );

    transfers.setState(
      transfers.jobs.single.id,
      const PublishJobState.publishing(),
    );
    await settle(tester);

    expect(outgoing(services).status, const OutgoingStatus.sent());
    expect(bubbleOf('an outgoing photo'), findsOneWidget);
    expect(source.newestKnownId, history + 1);
  });

  testWidgets('a conflict ends sent at the server id', (tester) async {
    final services = await pumpApp(tester);
    services.outbox.server.script(chat, FakeServerScript.conflict);

    await sendFromComposer(tester, 'after a conflict');

    expect(outgoing(services).status, const OutgoingStatus.sent());
    expect(outgoing(services).position, history + 1);
    expect(bubbleOf('A peer was first'), findsOneWidget);
    expect(bubbleOf('after a conflict'), findsOneWidget);
  });

  testWidgets('a rejection shows the message failed', (tester) async {
    final services = await pumpApp(tester);
    services.outbox.server.script(chat, FakeServerScript.reject);

    await sendFromComposer(tester, 'rejected one');

    expect(
      outgoing(services).status,
      const OutgoingStatus.failed(OutgoingFailure.rejected('demo.rejected')),
    );
    expect(bubbleOf('rejected one'), findsOneWidget);
  });

  testWidgets('after a restart pendingFor restores the rows', (tester) async {
    final first = await pumpApp(tester);
    first.outbox
        .chat(chat)
        .sendPlanned(
          [photo('p1')],
          bodies: ['sent before the restart'],
          prepared: {const AttachItemId('p1'): prepared},
        );
    await settle(tester);
    final clientMessageId = transfers.requests.single.idempotencyKey!;
    await tester.pumpWidget(const SizedBox());
    first.dispose();
    await tester.pump();

    // The next run: the engine's journal, the history as the server has it.
    source = GeneratedChatDataSource(messageCount: history);
    final services = await pumpApp(tester);

    final restored = services.outbox.outbox.byClientMessageId(
      chat,
      clientMessageId,
    )!;
    expect(restored.status, const OutgoingStatus.uploading());
    expect(restored.position, history);
    expect(bubbleOf('sent before the restart'), findsOneWidget);
    expect(find.byType(ChatScrollView), findsOneWidget);
  });
}
