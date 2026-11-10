import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_editability.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_message_body.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OneMessageSource extends ChatDataSource {
  _OneMessageSource({String content = 'hello'}) {
    upsertMessages(<IChatMessage>[
      UserChatMessage(
        id: 1,
        sender: 'User',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        content: content,
      ),
    ]);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

List<String> _actionIds(List<ChatMessageMenuItem> items) => [
  for (final item in items)
    if (item case ChatMessageMenuAction(:final id)) id,
];

Map<String, String> _actionLabels(List<ChatMessageMenuItem> items) => {
  for (final item in items)
    if (item case ChatMessageMenuAction(:final id, :final label)) id: label,
};

ChatMessageMenuRequest _request({
  required int messageId,
  ChatMessageMenuPointState pointState = ChatMessageMenuPointState.inside,
  ChatMessageMenuMembership membership = ChatMessageMenuMembership.idle,
  bool hasTextSelection = false,
  bool overlapsTextSelection = false,
  String? selectedTextSnapshot,
  List<int>? selectUpToIds,
  ChatInlineHit? inlineHit,
}) => ChatMessageMenuRequest(
  messageId: messageId,
  slotGlobal: const Rect.fromLTWH(0, 0, 100, 40),
  tapGlobal: const Offset(10, 10),
  pointState: pointState,
  membership: membership,
  hasTextSelection: hasTextSelection || overlapsTextSelection,
  overlapsTextSelection: overlapsTextSelection,
  selectedTextSnapshot: selectedTextSnapshot,
  selectUpToIds: selectUpToIds,
  inlineHit: inlineHit,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('present frames the request surface, clipped to the band', (
    tester,
  ) async {
    final dataSource = _OneMessageSource();
    final selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.mobile(),
    );
    addTearDown(dataSource.dispose);
    addTearDown(selection.dispose);
    final menu = MessageMenu(
      dataSource: dataSource,
      selection: selection,
      actions: MessageMenuActions(onDelete: (_) {}, onEdit: (_) {}),
      clipboard: FakeRichClipboard(),
    );
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
    );
    const request = ChatMessageMenuRequest(
      messageId: 1,
      slotGlobal: Rect.fromLTWH(0, 100, 400, 80),
      tapGlobal: Offset(140, 130),
      surfaceGlobal: Rect.fromLTWH(40, 110, 200, 56),
      surfaceShape: shape,
      bandGlobal: Rect.fromLTRB(0, 60, 400, 500),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => menu.present(context, request),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();

    final scrim = tester.widget<ChatMessageMenuScrim>(
      find.byType(ChatMessageMenuScrim),
    );
    expect(scrim.hole, request.surfaceGlobal);
    expect(scrim.holeShape, shape);
    expect(scrim.holeClip, request.bandGlobal);
  });

  group('the Edit row', () {
    // A long press opens the menu of the message under the finger; whether it
    // offers Edit is the host's rule for what the message is.
    Future<void> openMenu(WidgetTester tester, String content) async {
      final dataSource = _OneMessageSource(content: content);
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(dataSource.dispose);
      addTearDown(selection.dispose);
      final menu = MessageMenu(
        dataSource: dataSource,
        selection: selection,
        actions: MessageMenuActions(onDelete: (_) {}, onEdit: (_) {}),
        clipboard: FakeRichClipboard(),
        canEdit: (id) => switch (dataSource.getMessage(id)) {
          final message? => MessageEditability.canEdit(message),
          null => false,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => menu.present(context, _request(messageId: 1)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('is offered on a text message', (tester) async {
      await openMenu(tester, 'hello');

      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('is not offered on a sticker or a GIF, the rest stays', (
      tester,
    ) async {
      for (final item in [
        VideoStickerPack.stickers.first,
        VideoStickerPack.gifs.first,
      ]) {
        await openMenu(tester, StickerMessageBody.of(item));

        expect(find.text('Edit'), findsNothing, reason: item.name);
        expect(find.text('Delete'), findsOneWidget, reason: item.name);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group(r'MessageMenuCatalog ($Mobile)', () {
    const policy = ChatSelectionPolicy.mobile();

    test('idle: Reply→Copy→Forward→Pin→Edit→Delete; no Select', () {
      expect(
        _actionIds(MessageMenuCatalog.itemsFor(_request(messageId: 1), policy)),
        <String>[
          MessageMenuActionId.reply,
          MessageMenuActionId.copy,
          MessageMenuActionId.forward,
          MessageMenuActionId.pin,
          MessageMenuActionId.edit,
          MessageMenuActionId.delete,
        ],
      );
    });

    test('outside still keeps full idle rows', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(messageId: 1, pointState: ChatMessageMenuPointState.outside),
          policy,
        ),
      );
      expect(ids, contains(MessageMenuActionId.reply));
      expect(ids, isNot(contains(MessageMenuActionId.select)));
    });

    test(
      'idle: live text omits whole-message Copy (text chrome owns range)',
      () {
        final ids = _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 1,
              hasTextSelection: true,
              overlapsTextSelection: true,
              selectedTextSnapshot: 'hi',
            ),
            policy,
          ),
        );
        expect(ids, isNot(contains(MessageMenuActionId.copySelected)));
        expect(ids, isNot(contains(MessageMenuActionId.copy)));
        expect(ids, isNot(contains(MessageMenuActionId.select)));
      },
    );

    test('upon-selected: bulk labels + Reply; no Select', () {
      final items = MessageMenuCatalog.itemsFor(
        _request(
          messageId: 2,
          membership: ChatMessageMenuMembership.uponSelected,
        ),
        policy,
      );
      expect(_actionIds(items), <String>[
        MessageMenuActionId.reply,
        MessageMenuActionId.copy,
        MessageMenuActionId.forward,
        MessageMenuActionId.delete,
        MessageMenuActionId.clearSelection,
      ]);
      final labels = _actionLabels(items);
      expect(labels[MessageMenuActionId.copy], 'Copy Selected as Text');
      expect(labels[MessageMenuActionId.forward], 'Forward Selected');
      expect(labels[MessageMenuActionId.delete], 'Delete Selected');
      expect(labels[MessageMenuActionId.clearSelection], 'Clear Selection');
    });

    test('link hit prefixes Copy link', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(
            messageId: 1,
            inlineHit: const ChatInlineHit.link(
              messageId: 1,
              title: 'ex',
              url: 'https://example.com',
            ),
          ),
          policy,
        ),
      );
      expect(ids.first, MessageMenuActionId.copyLink);
    });

    test('reactions strip is non-empty', () {
      expect(MessageMenuCatalog.reactionsFor(policy), isNotEmpty);
    });
  });

  group(r'MessageMenuCatalog ($Desktop)', () {
    const policy = ChatSelectionPolicy.desktop();

    test('idle inside: Select at end; Edit before Pin/Copy', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(_request(messageId: 1), policy),
      );
      expect(ids.last, MessageMenuActionId.select);
      expect(
        ids.indexOf(MessageMenuActionId.edit),
        lessThan(ids.indexOf(MessageMenuActionId.pin)),
      );
      expect(
        ids.indexOf(MessageMenuActionId.pin),
        lessThan(ids.indexOf(MessageMenuActionId.copy)),
      );
    });

    test('outside: Select only', () {
      expect(
        _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 1,
              pointState: ChatMessageMenuPointState.outside,
            ),
            policy,
          ),
        ),
        <String>[MessageMenuActionId.select],
      );
    });

    test('membership elsewhere without chain: Select only', () {
      expect(
        _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 2,
              membership: ChatMessageMenuMembership.elsewhere,
            ),
            policy,
          ),
        ),
        <String>[MessageMenuActionId.select],
      );
    });

    test('membership elsewhere with chain: Select + Select up to', () {
      expect(
        _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 5,
              membership: ChatMessageMenuMembership.elsewhere,
              selectUpToIds: const <int>[3, 4, 5],
            ),
            policy,
          ),
        ),
        <String>[MessageMenuActionId.select, MessageMenuActionId.selectUpTo],
      );
    });

    test('over-selection: bulk labels + Reply; no Select', () {
      final items = MessageMenuCatalog.itemsFor(
        _request(
          messageId: 2,
          membership: ChatMessageMenuMembership.uponSelected,
        ),
        policy,
      );
      expect(_actionIds(items), <String>[
        MessageMenuActionId.reply,
        MessageMenuActionId.copy,
        MessageMenuActionId.forward,
        MessageMenuActionId.delete,
        MessageMenuActionId.clearSelection,
      ]);
      final labels = _actionLabels(items);
      expect(labels[MessageMenuActionId.copy], 'Copy Selected as Text');
      expect(labels[MessageMenuActionId.forward], 'Forward Selected');
      expect(labels[MessageMenuActionId.delete], 'Delete Selected');
    });

    test('text upon: Copy Selected Text; no whole-message Copy', () {
      final items = MessageMenuCatalog.itemsFor(
        _request(
          messageId: 1,
          overlapsTextSelection: true,
          selectedTextSnapshot: 'hi',
        ),
        policy,
      );
      final ids = _actionIds(items);
      expect(ids, contains(MessageMenuActionId.copySelected));
      expect(ids, isNot(contains(MessageMenuActionId.copy)));
      expect(ids, contains(MessageMenuActionId.select));
      expect(
        ids.indexOf(MessageMenuActionId.reply),
        lessThan(ids.indexOf(MessageMenuActionId.copySelected)),
      );
      expect(
        _actionLabels(items)[MessageMenuActionId.copySelected],
        'Copy Selected Text',
      );
    });

    test('text selected but not upon: neither Copy nor Copy Selected Text', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(messageId: 1, hasTextSelection: true),
          policy,
        ),
      );
      expect(ids, isNot(contains(MessageMenuActionId.copy)));
      expect(ids, isNot(contains(MessageMenuActionId.copySelected)));
      expect(ids, contains(MessageMenuActionId.reply));
      expect(ids, contains(MessageMenuActionId.select));
    });

    test('link hit prefixes Copy link', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(
            messageId: 1,
            inlineHit: const ChatInlineHit.link(
              messageId: 1,
              title: 'ex',
              url: 'https://example.com',
            ),
          ),
          policy,
        ),
      );
      expect(ids.first, MessageMenuActionId.copyLink);
    });

    test('excludeActionIds drops Reply and Forward', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(messageId: 1),
          policy,
          excludeActionIds: const [
            MessageMenuActionId.reply,
            MessageMenuActionId.forward,
          ],
        ),
      );
      expect(ids, isNot(contains(MessageMenuActionId.reply)));
      expect(ids, isNot(contains(MessageMenuActionId.forward)));
      expect(ids, contains(MessageMenuActionId.copy));
      expect(ids, contains(MessageMenuActionId.select));
    });

    test('reactions strip is empty (hover strip elsewhere)', () {
      expect(MessageMenuCatalog.reactionsFor(policy), isEmpty);
    });
  });

  group('content rows', () {
    const sticker = MessageMenuContent.sticker(
      key: ContentKey.document('s1'),
      pack: PackId('cats'),
      packInstalled: true,
      favourite: false,
    );
    const favourite = MessageMenuContent.sticker(
      key: ContentKey.document('s1'),
      pack: PackId('cats'),
      packInstalled: false,
      favourite: true,
    );
    const gif = MessageMenuContent.gif(key: ContentKey.document('g1'));

    List<String> ids(
      ChatSelectionPolicy policy,
      MessageMenuContent content, {
      TargetPlatform platform = TargetPlatform.android,
    }) => _actionIds(
      MessageMenuCatalog.itemsFor(
        _request(messageId: 1),
        policy,
        content: content,
        platform: platform,
      ),
    );

    test('Android: the sticker rows follow Copy, the pack before the '
        'favourite', () {
      const policy = ChatSelectionPolicy.mobile();
      expect(ids(policy, sticker), <String>[
        MessageMenuActionId.reply,
        MessageMenuActionId.copy,
        MessageMenuActionId.viewPack,
        MessageMenuActionId.addFavourite,
        MessageMenuActionId.forward,
        MessageMenuActionId.pin,
        MessageMenuActionId.edit,
        MessageMenuActionId.delete,
      ]);
      final labels = _actionLabels(
        MessageMenuCatalog.itemsFor(
          _request(messageId: 1),
          policy,
          content: favourite,
          platform: TargetPlatform.android,
        ),
      );
      expect(labels[MessageMenuActionId.viewPack], 'Add to Stickers');
      expect(labels[MessageMenuActionId.removeFavourite], 'Delete from Favorites');
    });

    test('Android: a GIF offers Save to GIFs after Copy', () {
      final rows = ids(const ChatSelectionPolicy.mobile(), gif);
      expect(rows.indexOf(MessageMenuActionId.saveGif), 2);
      expect(
        _actionLabels(
          MessageMenuCatalog.itemsFor(
            _request(messageId: 1),
            const ChatSelectionPolicy.mobile(),
            content: gif,
            platform: TargetPlatform.android,
          ),
        )[MessageMenuActionId.saveGif],
        'Save to GIFs',
      );
    });

    test('iOS: the favourite row comes first, the pack after Pin', () {
      final rows = ids(
        const ChatSelectionPolicy.mobile(),
        sticker,
        platform: TargetPlatform.iOS,
      );
      expect(rows.first, MessageMenuActionId.addFavourite);
      expect(
        rows.indexOf(MessageMenuActionId.viewPack),
        rows.indexOf(MessageMenuActionId.pin) + 1,
      );
      final gifRows = ids(
        const ChatSelectionPolicy.mobile(),
        gif,
        platform: TargetPlatform.iOS,
      );
      expect(
        gifRows.indexOf(MessageMenuActionId.saveGif),
        gifRows.indexOf(MessageMenuActionId.pin) + 1,
      );
    });

    test('desktop: after Pin, the pack then the favourite; the pack row '
        'adds a pack that is not installed', () {
      const policy = ChatSelectionPolicy.desktop();
      final rows = ids(policy, sticker, platform: TargetPlatform.macOS);
      final pin = rows.indexOf(MessageMenuActionId.pin);
      expect(rows[pin + 1], MessageMenuActionId.viewPack);
      expect(rows[pin + 2], MessageMenuActionId.addFavourite);
      String label(MessageMenuContent content, String id) => _actionLabels(
        MessageMenuCatalog.itemsFor(
          _request(messageId: 1),
          policy,
          content: content,
          platform: TargetPlatform.macOS,
        ),
      )[id]!;
      expect(label(sticker, MessageMenuActionId.viewPack), 'View sticker set');
      expect(label(favourite, MessageMenuActionId.viewPack), 'Add stickers');
      expect(
        label(favourite, MessageMenuActionId.removeFavourite),
        'Remove from Favorites',
      );
      expect(label(gif, MessageMenuActionId.saveGif), 'Save GIF');
    });

    test('a sticker without a pack has no pack row; a selection has no '
        'content rows', () {
      const loose = MessageMenuContent.sticker(
        key: ContentKey.document('s2'),
        pack: null,
        packInstalled: false,
        favourite: false,
      );
      expect(
        ids(const ChatSelectionPolicy.mobile(), loose),
        isNot(contains(MessageMenuActionId.viewPack)),
      );
      expect(
        _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 1,
              membership: ChatMessageMenuMembership.uponSelected,
            ),
            const ChatSelectionPolicy.mobile(),
            content: sticker,
          ),
        ),
        isNot(contains(MessageMenuActionId.addFavourite)),
      );
    });
  });
}
