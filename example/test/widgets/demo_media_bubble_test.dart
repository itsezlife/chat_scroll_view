/// The demo's media messages in a chat list: their items and cards render
/// through the message media bubble, and a tap on each reaches the host.
///
/// **Seam:** `DemoMessageBubble` rows of a mounted `ChatScrollView` whose
/// body host carries a `ChatMediaHost` with recording callbacks, over a
/// `ContentAssetScope` with a `FakeAssetProducer`; a received preview
/// without a page is looked up through a `FakeLinkPreviewResolver`.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_media_messages.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_photos.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_media_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_media_bubble.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/testing.dart';

final class _Source extends ChatDataSource {
  _Source(List<IChatMessage> messages) {
    messages.forEach(upsertMessage);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: messages.length - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

final _page = LinkPreview(
  url: Uri.parse('https://site.example/a'),
  siteName: 'Site',
  title: 'A page',
  description: const RichText.plain('About the page.'),
);

void main() {
  late ContentAssetScope scope;
  late ValueNotifier<LargeEmojiPolicy> emoji;
  late MessageMediaState state;
  late FakeLinkPreviewResolver resolver;
  late List<MediaViewerRequest> opened;
  late List<(int, LinkPreviewHitPart)> cards;

  setUp(() {
    scope = ContentAssetScope.withMedia(producer: FakeAssetProducer());
    emoji = ValueNotifier(const LargeEmojiPolicy(enabled: true));
    state = MessageMediaState();
    resolver = FakeLinkPreviewResolver();
    opened = [];
    cards = [];
    addTearDown(scope.dispose);
    addTearDown(emoji.dispose);
    addTearDown(state.dispose);
  });

  Future<ChatMediaHost> pump(
    WidgetTester tester,
    List<DemoMediaMessage> messages,
  ) async {
    final media = ChatMediaHost(
      chatId: 'chat-1',
      resolver: resolver,
      policy: const MessageMediaPolicy.android(),
      onOpenViewer: (context, request, items) => opened.add(request),
      onLinkPreview: (id, part, page) => cards.add((id, part)),
    );
    addTearDown(media.dispose);
    final host = ChatBodyHost(assets: scope, policy: emoji, media: media);
    final selection = ChatSelectionController(chatId: 'chat-1');
    final controller = ChatScrollController()..jumpTo(messages.length - 1);
    final source = _Source([
      for (final (id, message) in messages.indexed)
        message.toMessage(id: id, sender: 'Alice', time: DateTime.utc(2026)),
    ]);
    addTearDown(selection.dispose);
    addTearDown(controller.dispose);
    addTearDown(source.dispose);
    tester.view
      ..physicalSize = const Size(420, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: child!,
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
    await tester.pump(const Duration(seconds: 1));
    return media;
  }

  Finder cellOf(String id) => find.byKey(ValueKey(MediaItemId(id)));

  testWidgets('an album renders a cell per item, and a tap on one opens the '
      'viewer on the album at its index', (tester) async {
    await pump(tester, [
      DemoMediaMessage(
        body: 'Three',
        parts: [
          for (final photo in [
            DemoPhotos.harbour,
            DemoPhotos.cliff,
            DemoPhotos.meadow,
          ])
            (descriptor: photo.descriptor, kind: null, spoiler: false),
        ],
      ),
    ]);

    expect(find.byType(DemoMediaBubble), findsOneWidget);
    expect(find.byType(MessageMediaBubbleLayout), findsOneWidget);
    for (final id in ['0.0', '0.1', '0.2']) {
      expect(cellOf(id), findsOneWidget, reason: id);
    }

    await tester.tapAt(
      tester.getRect(cellOf('0.1')).topLeft + const Offset(8, 8),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(opened, hasLength(1));
    final request = opened.single;
    expect(request.messageId, 0);
    expect(request.items, [
      const MediaItemId('0.0'),
      const MediaItemId('0.1'),
      const MediaItemId('0.2'),
    ]);
    expect(request.index, 1);
    expect(request.originRect, tester.getRect(cellOf('0.1')));
  });

  testWidgets('a card the sender attached renders, and a tap on it reaches '
      'the host with its part', (tester) async {
    await pump(tester, [
      DemoMediaMessage(
        body: 'Read https://site.example/a',
        linkPreview: MessageLinkPreview(
          options: LinkPreviewOptions(url: _page.url),
          page: _page,
        ),
      ),
    ]);

    expect(find.text('A page'), findsOneWidget);
    await tester.tap(find.text('A page'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(cards, hasLength(1));
    expect(cards.single.$1, 0);
    expect(cards.single.$2.zone, LinkPreviewZone.body);
    expect(resolver.calls, isEmpty);
  });

  testWidgets('a preview without a page is looked up once and drawn when it '
      'loads', (tester) async {
    resolver.answer([_page.url], _page);
    await pump(tester, [
      DemoMediaMessage(
        body: 'Looked up: https://site.example/a',
        linkPreview: MessageLinkPreview(
          options: LinkPreviewOptions(url: _page.url),
        ),
      ),
    ]);
    expect(find.text('A page'), findsNothing);
    expect(resolver.calls, [
      [_page.url],
    ]);

    resolver.completeAll();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('A page'), findsOneWidget);
    // A rebuild asks again for nothing.
    await tester.pump(const Duration(seconds: 1));
    expect(resolver.calls, hasLength(1));
  });

  testWidgets('a hidden spoiler takes the first tap, which the chat state '
      'remembers', (tester) async {
    await pump(tester, [
      DemoMediaMessage(
        parts: [
          (descriptor: DemoPhotos.lagoon.descriptor, kind: null, spoiler: true),
        ],
      ),
    ]);

    await tester.tap(cellOf('0.0'));
    await tester.pump(const Duration(seconds: 1));

    expect(state.isSpoilerRevealed(const MediaItemId('0.0')), isTrue);
    expect(opened, isEmpty);
  });

  test('every demo media message carries ids from its message, file names '
      'and media types', () {
    for (final (id, template) in DemoMediaMessages.all.indexed) {
      final message = template.toMessage(
        id: id,
        sender: 'Alice',
        time: DateTime.utc(2026),
      );
      expect(message.hasMedia, isTrue, reason: '$id');
      for (final (index, item) in message.media.indexed) {
        expect(item.id, MediaItemId('$id.$index'));
        expect(item.descriptor.fileName, isNotNull, reason: '$id.$index');
        expect(item.descriptor.mimeType, isNotNull, reason: '$id.$index');
      }
    }
  });
}
