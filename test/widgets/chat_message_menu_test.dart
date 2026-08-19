import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _items = <ChatMessageMenuItem>[
  ChatMessageMenuItem(id: 'edit', label: 'Edit', icon: Icons.edit_outlined),
  ChatMessageMenuItem(
    id: 'delete',
    label: 'Delete',
    icon: Icons.delete_outline,
    isDestructive: true,
  ),
];

Future<void> _openMenu(
  WidgetTester tester, {
  required void Function(ChatMessageMenuResult? result) onDone,
  List<String> reactions = const <String>['👍', '❤️'],
  Listenable? presence,
  bool Function()? isPresent,
  bool keepKeyboardVisible = true,
  FocusNode? composerFocus,
  ChatMessageMenuThemeData? menuTheme,
  ChatMessageMenuItemBuilder? itemBuilder,
  ChatMessageMenuBuilder? menuBuilder,
  List<ChatMessageMenuItem> items = _items,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[?menuTheme]),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            if (composerFocus != null)
              TextField(focusNode: composerFocus, autofocus: true),
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final result = await showChatMessageMenu(
                    context: context,
                    messageRect: const Rect.fromLTWH(40, 120, 200, 48),
                    items: items,
                    tapGlobal: const Offset(140, 140),
                    reactions: reactions,
                    keepKeyboardVisible: keepKeyboardVisible,
                    presence: presence,
                    isPresent: isPresent,
                    itemBuilder: itemBuilder,
                    menuBuilder: menuBuilder,
                  );
                  onDone(result);
                },
                child: const Text('Open'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  tearDown(ChatPreImeBackBinding.debugReset);

  testWidgets('choosing an item completes with that itemId', (tester) async {
    ChatMessageMenuResult? result;
    await _openMenu(tester, onDone: (value) => result = value);

    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pump();

    expect(result, const ChatMessageMenuResult.item('edit'));
    expect(find.text('Edit'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('choosing a reaction completes with that reaction', (
    tester,
  ) async {
    ChatMessageMenuResult? result;
    await _openMenu(tester, onDone: (value) => result = value);

    expect(find.text('👍'), findsOneWidget);
    await tester.tap(find.text('👍'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, const ChatMessageMenuResult.reaction('👍'));
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('empty reactions omit the reaction strip', (tester) async {
    await _openMenu(tester, onDone: (_) {}, reactions: const <String>[]);

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('👍'), findsNothing);
    expect(find.text('❤️'), findsNothing);
  });

  testWidgets(
    'few reactions wrap to content, hang past the action card, and stay short',
    (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        reactions: const <String>['👍', '❤️'],
      );

      final reactions = tester.getRect(find.byType(ChatMessageMenuReactions));
      final actions = tester.getRect(find.byType(ChatMessageMenuActionList));
      expect(reactions.width, lessThan(actions.width));
      expect(reactions.right - actions.right, 48);
      expect(reactions.height, 44);
      expect(
        tester.getCenter(find.text('❤️')).dx,
        greaterThan(tester.getCenter(find.text('👍')).dx),
      );
    },
  );

  testWidgets('many reactions hang past both sides of the action card', (
    tester,
  ) async {
    await _openMenu(
      tester,
      onDone: (_) {},
      reactions: const <String>['👍', '❤️', '🔥', '🥰', '👏', '😁', '🤔', '🎉'],
    );

    final reactions = tester.getRect(find.byType(ChatMessageMenuReactions));
    final actions = tester.getRect(find.byType(ChatMessageMenuActionList));
    expect(actions.left - reactions.left, 24);
    expect(reactions.right - actions.right, 48);
  });

  testWidgets('hole tap dismisses with null', (tester) async {
    ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
      'sentinel',
    );
    await _openMenu(tester, onDone: (value) => result = value);

    expect(find.text('Edit'), findsOneWidget);
    // Slot rect is (40,120,200×48); menu top is at the tap (y=140).
    await tester.tapAt(const Offset(100, 125));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, isNull);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('pointer down on the scrim dismisses without a completed tap', (
    tester,
  ) async {
    ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
      'sentinel',
    );
    await _openMenu(tester, onDone: (value) => result = value);

    expect(find.text('Edit'), findsOneWidget);
    final gesture = await tester.startGesture(const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();

    expect(result, isNull);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('scrim tap dismisses with null', (tester) async {
    ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
      'sentinel',
    );
    await _openMenu(tester, onDone: (value) => result = value);

    expect(find.text('Edit'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, isNull);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('Escape dismisses with null', (tester) async {
    ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
      'sentinel',
    );
    await _openMenu(tester, onDone: (value) => result = value);

    expect(find.text('Edit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, isNull);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('overlay back dismisses with null', (tester) async {
    ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
      'sentinel',
    );
    await _openMenu(tester, onDone: (value) => result = value);

    expect(find.text('Edit'), findsOneWidget);
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, isNull);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('system back dismisses even when the page PopScope cannot pop', (
    tester,
  ) async {
    ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
      'sentinel',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PopScope(
          canPop: false,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showChatMessageMenu(
                    context: context,
                    messageRect: const Rect.fromLTWH(40, 120, 200, 48),
                    items: _items,
                    tapGlobal: const Offset(140, 140),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Edit'), findsOneWidget);
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, isNull);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('presence abort dismisses with null and does not retarget', (
    tester,
  ) async {
    final presence = ChangeNotifier();
    var present = true;
    ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
      'sentinel',
    );

    await _openMenu(
      tester,
      onDone: (value) => result = value,
      presence: presence,
      isPresent: () => present,
    );
    expect(find.text('Edit'), findsOneWidget);

    present = false;
    presence.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, isNull);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('keepKeyboardVisible restores the previous focus node', (
    tester,
  ) async {
    final composerFocus = FocusNode();
    addTearDown(composerFocus.dispose);

    await _openMenu(tester, onDone: (_) {}, composerFocus: composerFocus);

    expect(find.text('Edit'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(composerFocus.hasFocus, isTrue);
  });

  testWidgets('menu theme restyles the action card fill', (tester) async {
    const fill = Color(0xFF112233);
    await _openMenu(
      tester,
      onDone: (_) {},
      menuTheme: const ChatMessageMenuThemeData(cardColor: fill),
    );

    final card = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(ChatMessageMenuCard),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.color, fill);
  });

  testWidgets('itemBuilder replaces package action rows', (tester) async {
    await _openMenu(
      tester,
      onDone: (_) {},
      itemBuilder: (context, item, onSelect) => Text('custom-${item.id}'),
    );

    expect(find.text('custom-edit'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('menuBuilder can wrap default chrome', (tester) async {
    await _openMenu(
      tester,
      onDone: (_) {},
      menuBuilder: (context, slots) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[const Text('extra-slot'), slots.actionList],
      ),
    );

    expect(find.text('extra-slot'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('destructive rows do not insert a divider', (tester) async {
    await _openMenu(tester, onDone: (_) {});

    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('explicit divider entry paints a divider', (tester) async {
    await _openMenu(
      tester,
      onDone: (_) {},
      items: const <ChatMessageMenuItem>[
        ChatMessageMenuItem(
          id: 'edit',
          label: 'Edit',
          icon: Icons.edit_outlined,
        ),
        ChatMessageMenuItem.divider(),
        ChatMessageMenuItem(
          id: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline,
          isDestructive: true,
        ),
      ],
    );

    expect(find.byType(Divider), findsOneWidget);
  });
}
