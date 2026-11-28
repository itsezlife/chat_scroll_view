/// The user's outgoing media message in the chat: its row carries the
/// items, so the bubble draws them with the message's send state and its
/// time pill follows the status; a failed one's error badge sits by the
/// time over the media and answers inside the media's own hit order; an
/// item dropped by its cross leaves the bubble.
///
/// **Seam:** `DemoMessageBubble` rows of a mounted `ChatScrollView` over a
/// chat bound to a `DemoOutbox` (fake transfers, the fake server), with a
/// body host carrying a `ChatMediaHost`; observed through the widget tree
/// and the selection facade's hit resolution.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_status_motion.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_media_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_error_badge.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart' show FakeLinkPreviewResolver;
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

void main() {
  const chat = 'c1';
  const history = 3;

  late ContentAssetScope scope;
  late ValueNotifier<LargeEmojiPolicy> emoji;
  late MessageMediaState state;
  late FakeOutboxTransfers transfers;
  late DemoChatServer server;
  late DemoOutbox demo;
  late GeneratedChatDataSource source;
  late DemoOutboxChat bound;
  late ChatSelectionController selection;

  setUp(() {
    scope = ContentAssetScope.withMedia(producer: FakeAssetProducer());
    emoji = ValueNotifier(const LargeEmojiPolicy(enabled: true));
    state = MessageMediaState();
    transfers = FakeOutboxTransfers();
    server = DemoChatServer(peerDelay: Duration.zero);
    demo = DemoOutbox(transfers: transfers, server: server);
    source = GeneratedChatDataSource(messageCount: history);
    addTearDown(scope.dispose);
    addTearDown(emoji.dispose);
    addTearDown(state.dispose);
    addTearDown(demo.dispose);
  });

  PreparedMedia prepared(String path) => PreparedMedia(
    kind: PreparedKind.photo,
    path: path,
    isOriginal: false,
    byteSize: 100,
    dimensions: const MediaDimensions(400, 300),
  );

  Future<void> pump(WidgetTester tester) async {
    bound = demo.chat(chat);
    await tester.runAsync(() => bound.attach(source));
    final media = ChatMediaHost(
      chatId: chat,
      resolver: FakeLinkPreviewResolver(),
      policy: const MessageMediaPolicy.android(),
    );
    addTearDown(media.dispose);
    final host = ChatBodyHost(assets: scope, policy: emoji, media: media);
    selection = ChatSelectionController(chatId: chat);
    final controller = ChatScrollController();
    addTearDown(selection.dispose);
    addTearDown(controller.dispose);
    tester.view
      ..physicalSize = const Size(420, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: ChromeStringsScope(strings: demoChromeStrings, child: child!),
        ),
        home: ContentAssetProvider(
          scope: scope,
          child: MessageMediaStateScope(
            state: state,
            child: Scaffold(
              body: ChatScrollView(
                dataSource: source,
                controller: controller,
                selectionController: selection,
                messageBuilder: (context, id, message, status, runLayout) =>
                    switch (message) {
                      final message? => DemoMessageBubble(
                        message: message,
                        selection: selection,
                        host: host,
                        outbox: bound,
                      ),
                      null => const SizedBox(height: 40),
                    },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ({int id, List<MediaItemId> items}) sendAlbum() {
    final message = bound
        .sendPlanned(
          [
            PlannedSend.group([
              AttachItems.photo('p1', width: 400, height: 300),
              AttachItems.photo('p2', width: 400, height: 300),
            ], form: SendForm.media),
          ],
          bodies: [''],
          prepared: {
            const AttachItemId('p1'): prepared('/p1.jpg'),
            const AttachItemId('p2'): prepared('/p2.jpg'),
          },
        )
        .single!;
    return (
      id: message.position,
      items: [for (final item in message.items) item.id],
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Finder cellOf(MediaItemId id) => find.byKey(ValueKey(id));

  testWidgets('the bubble draws the items, sending, with the time pill '
      'following the status', (tester) async {
    await pump(tester);
    final sent = sendAlbum();
    await settle(tester);

    expect(cellOf(sent.items.first), findsOneWidget);
    expect(cellOf(sent.items.last), findsOneWidget);
    expect(
      tester
          .widget<MessageMediaBubbleLayout>(
            find.byType(MessageMediaBubbleLayout),
          )
          .sendState,
      MediaSendState.sending,
    );
    expect(
      tester
          .widget<DemoDeliveryMeta>(
            find.descendant(
              of: find.byType(MessageMediaBubbleLayout),
              matching: find.byType(DemoDeliveryMeta),
            ),
          )
          .delivery,
      DemoDelivery.sending,
    );
  });

  testWidgets("a failed one's badge sits over the media and answers in its "
      'hit order, ahead of the cell under it', (tester) async {
    await pump(tester);
    server.script(chat, DemoServerScript.reject);
    final sent = sendAlbum();
    await settle(tester);
    transfers.setState(
      transfers.jobs.single.id,
      const PublishJobState.publishing(),
    );
    await settle(tester);

    expect(bound.isFailedAt(sent.id), isTrue);
    expect(
      tester
          .widget<MessageMediaBubbleLayout>(
            find.byType(MessageMediaBubbleLayout),
          )
          .sendState,
      MediaSendState.failed,
    );
    final badge = find.byType(DemoErrorBadge);
    expect(badge, findsOneWidget);
    final media = tester.getRect(find.byType(MessageMediaView));
    expect(media.contains(tester.getCenter(badge)), isTrue);

    final onBadge = selection.resolveInlineHit(
      sent.id,
      tester.getCenter(badge),
    );
    expect(
      onBadge,
      isA<ChatInlineHit$BodyPart>()
          .having((h) => h.partId, 'part', isA<DemoErrorBadgePart>())
          .having((h) => h.role, 'role', ChatBodyPartRole.menu),
    );
    final onCell = selection.resolveInlineHit(
      sent.id,
      tester.getRect(cellOf(sent.items.first)).topLeft + const Offset(8, 8),
    );
    expect(
      onCell,
      isA<ChatInlineHit$BodyPart>().having(
        (h) => h.partId,
        'part',
        isA<MediaHitPart>(),
      ),
    );
  });

  testWidgets('an item dropped by its cross leaves the bubble', (tester) async {
    await pump(tester);
    final sent = sendAlbum();
    await settle(tester);

    transfers.cancelUpload(transfers.jobs.single.id, '${sent.items.first}');
    await settle(tester);

    expect(cellOf(sent.items.first), findsNothing);
    expect(cellOf(sent.items.last), findsOneWidget);
  });
}
