import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_editability.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_message_body.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/message_menu_chrome.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
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

const _tap = Offset(500, 300);

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
      ChromeThemeScope(
        palette: const ChromePalette.dark(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => menu.present(context, request),
                child: const Text('Open'),
              ),
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
        ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      menu.present(context, _request(messageId: 1)),
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
      expect(
        labels[MessageMenuActionId.removeFavourite],
        'Delete from Favorites',
      );
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

  group('the Android message menu', () {
    // A long press at [tap] on a one-message chat, under the app's chrome
    // theme (tests run as Android).
    Future<void> open(
      WidgetTester tester, {
      Offset tap = _tap,
      bool settle = true,
    }) async {
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
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => menu.present(
                    context,
                    ChatMessageMenuRequest(
                      messageId: 1,
                      slotGlobal: Rect.fromLTWH(0, tap.dy - 30, 800, 80),
                      tapGlobal: tap,
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
      await tester.pump();
      if (settle) {
        await tester.pump(const Duration(seconds: 1));
      } else {
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    Rect cardRect(WidgetTester tester) =>
        tester.getRect(find.byType(ChatMessageMenuCard).first);

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    testWidgets('its card is the scrim menu glass, its rows the chrome\'s: '
        '48 tall, label 43 after the icon\'s start, 18 in', (tester) async {
      await open(tester);

      final card = find.byType(ChatMessageMenuCard).first;
      expect(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is GlassSurface &&
                widget.material == GlassMaterial.messageMenu,
          ),
        ),
        findsOneWidget,
      );
      final row = find.ancestor(
        of: find.text('Copy'),
        matching: find.byType(MessageMenuRow),
      );
      expect(tester.getSize(row).height, 48);
      expect(
        tester.getTopLeft(find.text('Copy')).dx - tester.getTopLeft(row).dx,
        18 + 43,
      );
      expect(tester.getSize(card).width, greaterThanOrEqualTo(200));
    });

    testWidgets('its rows draw label and icon in the text colour, the '
        'Delete row too', (tester) async {
      await open(tester);

      for (final label in ['Copy', 'Delete']) {
        final row = find
            .ancestor(
              of: find.text(label),
              matching: find.byType(MessageMenuRow),
            )
            .first;
        final icon = tester.widget<Icon>(
          find.descendant(of: row, matching: find.byType(Icon)),
        );
        expect(icon.color, const ChromePalette.dark().onSurface, reason: label);
        expect(
          tester.widget<Text>(find.text(label)).style?.color,
          const ChromePalette.dark().onSurface,
          reason: label,
        );
      }
    });

    testWidgets('its reaction strip comes in on its own: scaled up from its '
        'end, opening from it, over 250 ms', (tester) async {
      await open(tester, settle: false);

      final enter = find.byType(MessageMenuStripEnter);
      expect(enter, findsOneWidget);
      final scale = tester.widget<Transform>(
        find.descendant(of: enter, matching: find.byType(Transform)).first,
      );
      expect(scale.transform.storage[0], lessThan(1));
      expect(scale.alignment, const Alignment(0.75, 0));

      await tester.pump(const Duration(milliseconds: 300));
      // Whole and at rest: no scale but 1 anywhere in it.
      for (final transform in tester.widgetList<Transform>(
        find.descendant(of: enter, matching: find.byType(Transform)),
      )) {
        expect(transform.transform.storage[0], 1);
      }
      expect(
        tester.getSize(find.byType(ChatMessageMenuReactions)),
        tester.getSize(enter),
      );
    });

    testWidgets('its reaction strip is the same glass', (tester) async {
      await open(tester);

      final glass = find.byWidgetPredicate(
        (widget) =>
            widget is GlassSurface &&
            widget.material == GlassMaterial.messageMenu,
      );
      expect(
        find.ancestor(
          of: find.byType(ChatMessageMenuReactions),
          matching: glass,
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ChatMessageMenuReactions),
          matching: glass,
        ),
        findsOneWidget,
      );
    });

    testWidgets('it pops from its bottom right corner, its rows never '
        'scaling apart from the card, and its card ends 64 left of the press', (
      tester,
    ) async {
      await open(tester);

      final appear = tester.widget<ChromeAppear>(find.byType(ChromeAppear));
      expect(appear.motion, const AppearMotion.zoom());
      expect(appear.origin, Alignment.bottomRight);
      expect(find.byType(AppearContent), findsNothing);
      final card = tester.getRect(find.byType(ChatMessageMenuCard).first);
      expect(card.right, closeTo(_tap.dx - 64, 0.01));
    });

    for (final (name, at) in <(String, Offset Function(Rect card))>[
      ('left of it', (card) => card.centerLeft - const Offset(8, 0)),
      ('at the screen edge', (card) => Offset(2, card.center.dy)),
      ('right of it', (card) => card.centerRight + const Offset(8, 0)),
    ]) {
      testWidgets('a press $name dismisses it', (tester) async {
        await open(tester);
        expect(find.text('Copy'), findsOneWidget);

        await tester.tapAt(at(cardRect(tester)));
        await settle(tester);
        expect(find.text('Copy'), findsNothing);
      });
    }
  });

  testWidgets('a second secondary click where the menu was opened closes it '
      '(desktop)', (tester) async {
    final dataSource = _OneMessageSource();
    final selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.desktop(),
    );
    addTearDown(dataSource.dispose);
    addTearDown(selection.dispose);
    final menu = MessageMenu(
      dataSource: dataSource,
      selection: selection,
      actions: MessageMenuActions(onDelete: (_) {}, onEdit: (_) {}),
      clipboard: FakeRichClipboard(),
    );
    const click = Offset(300, 200);
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
                    slotGlobal: Rect.fromLTWH(0, 170, 800, 60),
                    tapGlobal: click,
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
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Select'), findsOneWidget);

    // The menu grows from the pointer: the second click lands on its edge.
    await tester.tapAt(click + const Offset(4, 4), buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Select'), findsNothing);
    expect(menu.isPresenting, isFalse);
  });

  testWidgets(
    'the desktop menu is the pointer menu with icons: its rows, card and '
    'motion, growing from the corner at the pointer',
    (tester) async {
      final dataSource = _OneMessageSource();
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(dataSource.dispose);
      addTearDown(selection.dispose);
      final menu = MessageMenu(
        dataSource: dataSource,
        selection: selection,
        actions: MessageMenuActions(onDelete: (_) {}, onEdit: (_) {}),
        clipboard: FakeRichClipboard(),
      );
      const click = Offset(300, 200);
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: const ChromePalette.dark(),
          pointerMenu: PointerMenuTokens.night,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => menu.present(
                    context,
                    const ChatMessageMenuRequest(
                      messageId: 1,
                      slotGlobal: Rect.fromLTWH(0, 170, 800, 60),
                      tapGlobal: click,
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
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final row = find
          .ancestor(
            of: find.text('Select'),
            matching: find.byType(MessageMenuPointerRow),
          )
          .first;
      final label = tester.getRect(find.text('Select'));
      final rowRect = tester.getRect(row);
      // The label 54 in, 8 above and below it.
      expect(label.left - rowRect.left, 54);
      expect(label.top - rowRect.top, 8);
      expect(rowRect.bottom - label.bottom, 8);
      final text = tester.widget<Text>(find.text('Select'));
      expect(text.style?.color, PointerMenuTokens.night.text);
      expect(text.style?.fontSize, 13);
      // The icon, 24, 15 in and 5 down, in the menu's bold colour.
      final icon = find.descendant(of: row, matching: find.byType(Icon));
      expect(tester.getTopLeft(icon) - rowRect.topLeft, const Offset(15, 5));
      expect(tester.widget<Icon>(icon).size, 24);
      expect(tester.widget<Icon>(icon).color, PointerMenuTokens.night.arrow);
      final appear = tester.widget<ChromeAppear>(find.byType(ChromeAppear));
      expect(appear.motion, const AppearMotion.grow());
      expect(appear.origin, Alignment.topLeft);
      final card = tester.getRect(find.byType(ChatMessageMenuCard));
      expect(card.topLeft, click + const Offset(5, 0));
      // The padding above the first row of a menu with icons.
      expect(
        tester.getTopLeft(find.byType(MessageMenuPointerRow).first).dy -
            card.top,
        5,
      );
      // As wide as its widest row, 156 at least.
      expect(card.width, greaterThanOrEqualTo(156));
      expect(
        find.descendant(
          of: find.byType(ChatMessageMenuCard),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox &&
                widget.color == PointerMenuTokens.night.background,
          ),
        ),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a hovered desktop row keeps its label: the over fill is painted under '
    'it, in the over text colour',
    (tester) async {
      final dataSource = _OneMessageSource();
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(dataSource.dispose);
      addTearDown(selection.dispose);
      final menu = MessageMenu(
        dataSource: dataSource,
        selection: selection,
        actions: MessageMenuActions(onDelete: (_) {}, onEdit: (_) {}),
        clipboard: FakeRichClipboard(),
      );
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: const ChromePalette.dark(),
          pointerMenu: PointerMenuTokens.night,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => menu.present(
                    context,
                    const ChatMessageMenuRequest(
                      messageId: 1,
                      slotGlobal: Rect.fromLTWH(0, 170, 800, 60),
                      tapGlobal: Offset(300, 200),
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
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Select')));
      await tester.pump();

      const over = PointerMenuTokens.night;
      final label = tester.widget<Text>(find.text('Select'));
      expect(label.style?.color, over.textOver);
      expect(label.style?.color, isNot(over.backgroundOver));
      final row = find
          .ancestor(
            of: find.text('Select'),
            matching: find.byType(MessageMenuPointerRow),
          )
          .first;
      expect(
        tester.renderObject(row),
        paints
          ..something(
            (method, arguments) =>
                method == #drawPaint &&
                // A paint keeps its colour in single precision.
                (arguments.single as Paint).color.toARGB32() ==
                    over.backgroundOver.toARGB32(),
          )
          ..paragraph(),
        reason: 'the fill first, then the label over it',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
