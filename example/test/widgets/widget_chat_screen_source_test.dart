import 'package:catalog_assets/catalog_assets.dart' show PlaybackPauseLayer;
import 'package:chat_composer/chat_composer.dart' show ComposerView;
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/backend_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_backend_error.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:content_model/content_model.dart'
    as model
    show Entity, EntityKind, RichText;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

import '../support/fake_soft_keyboard.dart';
import '../support/test_services.dart';

/// The chat screen runs from a generated, backend-free message source.
///
/// The acceptance scenario for the panel over the real chat screen
/// (`integration_test/panel_over_chat_test.dart`) depends on this: it has no
/// backend and no bundled comments asset to lean on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;
  late GeneratedChatDataSource source;
  late FakeSoftKeyboard keyboard;

  setUp(() async {
    keyboard = FakeSoftKeyboard();
    source = GeneratedChatDataSource(messageCount: 200);
  });

  tearDown(() async {
    await keyboard.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        softKeyboard: keyboard,
        chatDataSourceLoader: () async => source,
      ),
    );
    // Open position resolves over a few async hops, then the first layout.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('shows the generated messages without a backend', (tester) async {
    await pumpApp(tester);

    expect(find.byType(DemoBackendError), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ChatScrollView), findsOneWidget);
    expect(find.byType(DemoMessageBubble), findsWidgets);
  });

  testWidgets('a dialog opened over the chat holds the shared clock until it '
      'closes', (tester) async {
    await pumpApp(tester);
    final clock = services.assets.clock;
    expect(clock.pausedLayers, isEmpty);

    final shown = showDialog<void>(
      context: tester.element(find.byType(ChatScrollView)),
      builder: (_) => const AlertDialog(content: Text('over the chat')),
    );
    await tester.pumpAndSettle();
    expect(clock.pausedLayers, {PlaybackPauseLayer.overlayShown});

    Navigator.of(tester.element(find.text('over the chat'))).pop();
    await shown;
    await tester.pumpAndSettle();
    expect(clock.pausedLayers, isEmpty);
  });

  testWidgets('the composer panel button opens the catalogue panel', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(PanelCatalogViewport), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>(ChatComposerActions.panel)),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(PanelCatalogViewport), findsOneWidget);
  });

  group('over a backend chat', () {
    final sentBodies = <String>[];

    // A chat of three stored messages; a send is stored as given and comes
    // back as message 4.
    Future<Map<String, dynamic>> invoke(
      String name,
      Map<String, dynamic> body,
    ) async {
      Map<String, Object?> message(int id, String content) => {
        'id': id,
        'chat_id': 1,
        'sender_id': 2,
        'created_at': 1583108356 + id,
        'updated_at': 1583108356 + id,
        'kind': 0,
        'flags': 0,
        'reply_to_id': null,
        'content': content,
        'rich_content': null,
        'extra': {'legacy_sender': 'alice'},
      };
      switch (name) {
        case 'load_chat':
          return {
            'chat': {
              'id': 1,
              'last_message': {'id': 3},
            },
          };
        case 'get_read_state':
          return {'last_read_message_id': 3};
        case 'update_read_state':
          return <String, dynamic>{};
        case 'load_messages':
          return {
            'messages': [
              message(1, 'see https://one.example now'),
              message(2, '[docs](https://flutter.dev) and https://two.example'),
              message(3, 'nothing to link here'),
            ],
            'has_older': false,
            'has_newer': false,
            'oldest_id': 1,
            'newest_id': 3,
            'requested_from': body['from_id'],
            'requested_to': body['to_id'],
          };
        case 'send_message':
          sentBodies.add(body['content']! as String);
          return {'message': message(4, body['content']! as String)};
      }
      fail('unexpected $name');
    }

    late AppServices services;
    BackendChatDataSource? source;

    setUp(sentBodies.clear);

    // The test backend's placeholder client starts an auth refresh timer when
    // it is first made; made inside a widget test's fake clock it would be
    // left pending. Make it here, on the real one.
    setUpAll(() => BackendChatDataSource.forTest(invoke: invoke).dispose());

    Future<void> openChat(WidgetTester tester) async {
      await tester.pumpWidget(
        ChatDemoApp(
          services: services,
          softKeyboard: FakeSoftKeyboard(),
          chatDataSourceLoader: () async =>
              source = await BackendChatDataSource.connectForTest(invoke),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> leaveChat(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    ComposerView composerView(WidgetTester tester) =>
        tester.widget<ComposerView>(find.byType(ComposerView));

    testWidgets('a message is detected once as it is materialised, never on '
        'mount', (tester) async {
      services = (await tester.runAsync(createTestServices))!;
      addTearDown(services.dispose);
      final before = ChatBodyMarkdown.detectionRuns;

      await openChat(tester);
      final afterOpen = ChatBodyMarkdown.detectionRuns;

      // Three messages arrive; the one with a link is trusted and not run.
      expect(afterOpen - before, 2);
      expect(
        source!.getMessage(1)?.text,
        'see [https://one.example](https://one.example) now',
      );
      expect(
        source!.getMessage(2)?.text,
        '[docs](https://flutter.dev) and https://two.example',
      );

      // Every message mounts again at another size; none is detected again.
      tester.view
        ..physicalSize = const Size(500, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ChatBodyMarkdown.detectionRuns, afterOpen);
    });

    testWidgets('a send is detected, encoded and replaced by the stored '
        'body', (tester) async {
      services = (await tester.runAsync(createTestServices))!;
      addTearDown(services.dispose);
      await openChat(tester);

      composerView(tester).controller.insertText('look https://a.b @al');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>(ChatComposerActions.primary)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      const wire = 'look [https://a.b](https://a.b) [@al](username:al)';
      expect(sentBodies, [wire]);
      expect(source!.getMessage(4)?.text, wire);
    });

    testWidgets('the unsent text survives leaving the chat and reopening it, '
        'and a send clears it', (tester) async {
      services = (await tester.runAsync(createTestServices))!;
      addTearDown(services.dispose);
      await openChat(tester);
      composerView(tester).controller.restore(
        model.RichText('make it loud', const [
          model.Entity(8, 4, model.EntityKind.bold),
        ]),
      );
      await tester.pump();

      await leaveChat(tester);
      await openChat(tester);

      expect(
        composerView(tester).controller.richText,
        model.RichText('make it loud', const [
          model.Entity(8, 4, model.EntityKind.bold),
        ]),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>(ChatComposerActions.primary)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await leaveChat(tester);
      await openChat(tester);

      expect(composerView(tester).controller.richText.plain, isEmpty);
    });
  });
}
