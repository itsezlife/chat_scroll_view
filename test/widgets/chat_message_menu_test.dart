import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  ChatMessageMenuTransitionBuilder? transitionBuilder,
  ChatMessageMenuSurfaceBuilder? surfaceBuilder,
  List<ChatMessageMenuItem> items = _items,
  ChatMessageMenuPresentation presentation = ChatMessageMenuPresentation.sheet,
  ChatSelectionPolicy? selectionPolicy,
  Offset tapGlobal = const Offset(140, 140),
  Rect messageRect = const Rect.fromLTWH(40, 120, 200, 48),
  Rect? surfaceRect,
  ShapeBorder? surfaceShape,
  Rect? visibleRect,
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
                  final result = await ChatMessageMenu.show(
                    context: context,
                    messageRect: messageRect,
                    surfaceRect: surfaceRect,
                    surfaceShape: surfaceShape,
                    visibleRect: visibleRect,
                    items: items,
                    tapGlobal: tapGlobal,
                    reactions: reactions,
                    keepKeyboardVisible: keepKeyboardVisible,
                    presence: presence,
                    isPresent: isPresent,
                    presentation: presentation,
                    selectionPolicy: selectionPolicy,
                    itemBuilder: itemBuilder,
                    menuBuilder: menuBuilder,
                    transitionBuilder: transitionBuilder,
                    surfaceBuilder: surfaceBuilder,
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

  testWidgets('a route pushed on the result survives the leave animation', (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await ChatMessageMenu.show(
                  context: context,
                  messageRect: const Rect.fromLTWH(40, 120, 200, 48),
                  items: _items,
                );
                if (result != const ChatMessageMenuResult.item('delete')) {
                  return;
                }
                if (!context.mounted) return;
                confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Confirm delete?'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Yes'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm delete?'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(find.text('Confirm delete?'), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
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
                  result = await ChatMessageMenu.show(
                    context: context,
                    messageRect: const Rect.fromLTWH(40, 120, 200, 48),
                    items: _items,
                    tapGlobal: const Offset(140, 140),
                    presentation: ChatMessageMenuPresentation.sheet,
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

  group('the action card', () {
    const long = 'Copy Selected as Text, all of it';

    testWidgets('is as wide as its widest row: a longer label widens it '
        'instead of ellipsizing', (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        items: const <ChatMessageMenuItem>[
          ChatMessageMenuItem(id: 'a', label: 'Copy', icon: Icons.copy),
          ChatMessageMenuItem(id: 'b', label: long, icon: Icons.copy),
        ],
      );

      final label = tester.renderObject<RenderParagraph>(find.text(long));
      expect(label.didExceedMaxLines, isFalse);
      expect(
        tester.getSize(find.byType(ChatMessageMenuCard)).width,
        greaterThan(ChatMessageMenuCard.defaultMinWidth),
      );
    });

    testWidgets('is never narrower than 200', (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        items: const <ChatMessageMenuItem>[
          ChatMessageMenuItem(id: 'a', label: 'Copy', icon: Icons.copy),
        ],
      );

      expect(
        tester.getSize(find.byType(ChatMessageMenuCard)).width,
        ChatMessageMenuCard.defaultMinWidth,
      );
    });

    testWidgets('ellipsizes a row only past the screen', (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        items: <ChatMessageMenuItem>[
          ChatMessageMenuItem(id: 'a', label: long * 6, icon: Icons.copy),
        ],
      );

      expect(
        tester
            .renderObject<RenderParagraph>(find.text(long * 6))
            .didExceedMaxLines,
        isTrue,
      );
      final card = tester.getRect(find.byType(ChatMessageMenuCard));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(800));
    });

    testWidgets('stretches every row across the card, short labels too, '
        'under a host surface that loosens its child', (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        items: const <ChatMessageMenuItem>[
          ChatMessageMenuItem(id: 'a', label: 'Copy', icon: Icons.copy),
          ChatMessageMenuItem(id: 'b', label: 'Pin', icon: Icons.push_pin),
        ],
        // A surface as a glass is built: a stack, which lays out its child
        // loosely.
        surfaceBuilder: (context, radius, rows) => Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF00FF00))),
            rows,
          ],
        ),
      );

      final card = tester.getRect(find.byType(ChatMessageMenuCard));
      expect(card.width, ChatMessageMenuCard.defaultMinWidth);
      for (final label in ['Copy', 'Pin']) {
        final row = find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first;
        expect(tester.getRect(row).width, card.width, reason: label);
      }
    });

    testWidgets('the reaction strip takes the same host surface, at its '
        'own corners', (tester) async {
      final radii = <double>[];
      await _openMenu(
        tester,
        onDone: (_) {},
        surfaceBuilder: (context, radius, child) {
          radii.add(radius);
          return ColoredBox(
            key: ValueKey('surface-$radius'),
            color: const Color(0xFF00FF00),
            child: child,
          );
        },
      );

      expect(radii, containsAll(<double>[12, 22]));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('surface-22.0')),
          matching: find.text('👍'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('takes the host surface around its rows', (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        surfaceBuilder: (context, radius, rows) => ColoredBox(
          key: const ValueKey('host-surface'),
          color: const Color(0xFF00FF00),
          child: rows,
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('host-surface')),
          matching: find.text('Edit'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ChatMessageMenuCard),
          // The package fill; the rows keep their transparent ink layers.
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.type != MaterialType.transparency &&
                widget.color != Colors.transparent,
          ),
        ),
        findsNothing,
      );
    });
  });

  group('a press anywhere outside the menu dismisses it', () {
    for (final (name, at) in <(String, Offset Function(Rect card))>[
      ('left of the card', (card) => card.centerLeft - const Offset(6, 0)),
      ('right of the card', (card) => card.centerRight + const Offset(6, 0)),
      ('below the card', (card) => card.bottomCenter + const Offset(0, 6)),
    ]) {
      testWidgets(name, (tester) async {
        var done = false;
        ChatMessageMenuResult? result = const ChatMessageMenuResult.item('x');
        await _openMenu(
          tester,
          onDone: (value) {
            done = true;
            result = value;
          },
          tapGlobal: const Offset(400, 140),
        );
        final card = tester.getRect(find.byType(ChatMessageMenuCard));

        await tester.tapAt(at(card));
        await tester.pump();

        expect(done, isTrue);
        expect(result, isNull);
        await tester.pump(const Duration(milliseconds: 350));
      });
    }
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

  group('transitionBuilder', () {
    late List<ChatMessageMenuTransition> played;
    VoidCallback? hide;

    Widget builder(
      BuildContext context,
      ChatMessageMenuTransition transition,
      Widget menu,
    ) {
      played.add(transition);
      hide = transition.onHidden;
      return menu;
    }

    setUp(() {
      played = [];
      hide = null;
    });

    testWidgets('plays the host\'s motion from the corner at the pointer, '
        'and the session waits for its leave', (tester) async {
      ChatMessageMenuResult? result;
      await _openMenu(
        tester,
        onDone: (value) => result = value,
        presentation: ChatMessageMenuPresentation.popup,
        transitionBuilder: builder,
      );

      final shown = played.last;
      expect(shown.visible, isTrue);
      expect(shown.presentation, ChatMessageMenuPresentation.popup);
      expect(shown.rows, _items.length);
      expect(shown.origin, Alignment.topLeft);

      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(result, const ChatMessageMenuResult.item('edit'));
      expect(played.last.visible, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Edit'), findsOneWidget, reason: 'until it is hidden');

      hide!();
      await tester.pump();
      await tester.pump();
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('a sheet, hanging left of the press, plays from its right '
        'corner, and says whether it has reactions', (tester) async {
      await _openMenu(tester, onDone: (_) {}, transitionBuilder: builder);

      expect(played.last.origin.x, 1);
      expect(played.last.hasReactions, isTrue);
    });
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

  group('scrim hole', () {
    testWidgets('without a surface the hole is the rounded slot', (
      tester,
    ) async {
      await _openMenu(tester, onDone: (_) {});

      expect(
        find.byType(ChatMessageMenuScrim),
        paints..path(
          includes: const <Offset>[Offset(8, 8), Offset(41, 121)],
          excludes: const <Offset>[Offset(100, 144), Offset(236, 144)],
        ),
      );
    });

    testWidgets('a surface hole follows its shape, not the slot', (
      tester,
    ) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        messageRect: const Rect.fromLTWH(0, 100, 400, 80),
        surfaceRect: const Rect.fromLTWH(40, 110, 200, 56),
        surfaceShape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(18),
            bottomEnd: Radius.circular(18),
          ),
        ),
      );

      expect(
        find.byType(ChatMessageMenuScrim),
        paints..path(
          includes: const <Offset>[
            // Slot, but outside the surface.
            Offset(300, 130),
            Offset(20, 170),
            // Rounded start-top and end-bottom corners.
            Offset(41, 111),
            Offset(239, 165),
          ],
          excludes: const <Offset>[
            Offset(140, 138),
            // Square end-top and start-bottom corners.
            Offset(239, 111),
            Offset(41, 165),
          ],
        ),
      );
    });

    testWidgets('the surface hole is clipped to the visible rect', (
      tester,
    ) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        messageRect: const Rect.fromLTWH(0, 100, 400, 80),
        surfaceRect: const Rect.fromLTWH(40, 110, 200, 56),
        surfaceShape: const RoundedRectangleBorder(),
        visibleRect: const Rect.fromLTRB(0, 0, 400, 140),
      );

      expect(
        find.byType(ChatMessageMenuScrim),
        paints..path(
          includes: const <Offset>[Offset(140, 150)],
          excludes: const <Offset>[Offset(140, 130)],
        ),
      );
    });
  });

  group('message menu presentation', () {
    test('forPolicy maps mobile to sheet and desktop to popup', () {
      expect(
        ChatMessageMenuPresentation.forPolicy(
          const ChatSelectionPolicy.mobile(),
        ),
        ChatMessageMenuPresentation.sheet,
      );
      expect(
        ChatMessageMenuPresentation.forPolicy(
          const ChatSelectionPolicy.desktop(),
        ),
        ChatMessageMenuPresentation.popup,
      );
    });

    testWidgets('sheet presentation paints the scrim', (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        presentation: ChatMessageMenuPresentation.sheet,
      );

      expect(find.byType(ChatMessageMenuScrim), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('a second secondary click on the message closes the popup', (
      tester,
    ) async {
      var done = false;
      ChatMessageMenuResult? result = const ChatMessageMenuResult.item('x');
      await _openMenu(
        tester,
        onDone: (value) {
          done = true;
          result = value;
        },
        presentation: ChatMessageMenuPresentation.popup,
      );

      await tester.tapAt(const Offset(60, 140), buttons: kSecondaryButton);
      await tester.pump();
      expect(done, isTrue);
      expect(result, isNull);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('a popup card is 156 at least and 300 at most', (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        presentation: ChatMessageMenuPresentation.popup,
        reactions: const <String>[],
        items: const <ChatMessageMenuItem>[
          ChatMessageMenuItem(id: 'a', label: 'Copy', icon: Icons.copy),
        ],
      );
      expect(tester.getSize(find.byType(ChatMessageMenuCard)).width, 156);
    });

    testWidgets('a popup card ellipsizes past 300', (tester) async {
      const long = 'A label far longer than any desktop menu allows, and more';
      await _openMenu(
        tester,
        onDone: (_) {},
        presentation: ChatMessageMenuPresentation.popup,
        reactions: const <String>[],
        items: const <ChatMessageMenuItem>[
          ChatMessageMenuItem(id: 'a', label: long, icon: Icons.copy),
        ],
      );
      expect(tester.getSize(find.byType(ChatMessageMenuCard)).width, 300);
      expect(
        tester.renderObject<RenderParagraph>(find.text(long)).didExceedMaxLines,
        isTrue,
      );
    });

    testWidgets('popup presentation omits the scrim', (tester) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        presentation: ChatMessageMenuPresentation.popup,
      );

      expect(find.byType(ChatMessageMenuScrim), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('desktop policy defaults to popup without an override', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  ChatMessageMenu.show(
                    context: context,
                    messageRect: const Rect.fromLTWH(40, 120, 200, 48),
                    items: _items,
                    tapGlobal: const Offset(140, 140),
                    selectionPolicy: const ChatSelectionPolicy.desktop(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(ChatMessageMenuScrim), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('mobile policy defaults to sheet without an override', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  ChatMessageMenu.show(
                    context: context,
                    messageRect: const Rect.fromLTWH(40, 120, 200, 48),
                    items: _items,
                    tapGlobal: const Offset(140, 140),
                    selectionPolicy: const ChatSelectionPolicy.mobile(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(ChatMessageMenuScrim), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('explicit presentation overrides selection policy', (
      tester,
    ) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        presentation: ChatMessageMenuPresentation.sheet,
        selectionPolicy: const ChatSelectionPolicy.desktop(),
      );

      expect(find.byType(ChatMessageMenuScrim), findsOneWidget);
    });

    testWidgets('popup outside tap dismisses with null', (tester) async {
      ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
        'sentinel',
      );
      await _openMenu(
        tester,
        onDone: (value) => result = value,
        presentation: ChatMessageMenuPresentation.popup,
      );

      expect(find.text('Edit'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(result, isNull);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('popup Escape dismisses with null', (tester) async {
      ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
        'sentinel',
      );
      await _openMenu(
        tester,
        onDone: (value) => result = value,
        presentation: ChatMessageMenuPresentation.popup,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(result, isNull);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('popup presence abort dismisses with null', (tester) async {
      final presence = ChangeNotifier();
      var present = true;
      ChatMessageMenuResult? result = const ChatMessageMenuResult.item(
        'sentinel',
      );

      await _openMenu(
        tester,
        onDone: (value) => result = value,
        presentation: ChatMessageMenuPresentation.popup,
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
    });

    testWidgets('popup choosing an item still completes with itemId', (
      tester,
    ) async {
      ChatMessageMenuResult? result;
      await _openMenu(
        tester,
        onDone: (value) => result = value,
        presentation: ChatMessageMenuPresentation.popup,
      );

      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(result, const ChatMessageMenuResult.item('edit'));
    });

    testWidgets('popup may omit reactions without a second product', (
      tester,
    ) async {
      await _openMenu(
        tester,
        onDone: (_) {},
        presentation: ChatMessageMenuPresentation.popup,
        reactions: const <String>[],
      );

      expect(find.byType(ChatMessageMenuScrim), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('👍'), findsNothing);
    });

    testWidgets('a popup opens 5 right of the pointer, below it', (
      tester,
    ) async {
      const tap = Offset(220, 140);
      await _openMenu(
        tester,
        onDone: (_) {},
        presentation: ChatMessageMenuPresentation.popup,
        tapGlobal: tap,
      );

      expect(
        tester.getTopLeft(find.byType(ChatMessageMenuColumn)),
        tap + const Offset(5, 0),
      );
    });
  });
}
