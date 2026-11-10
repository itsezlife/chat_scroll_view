/// The message menu's "contains emoji from N packs" entry: offered under the
/// actions of a message whose custom emoji come from packs, it names them and
/// asks the host to open them.
///
/// **Seam:** [MessageMenu.present] with [MessageEmojiPacks]; observed through
/// the menu on screen and [MessageMenuActions.onEmojiPacks].
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_emoji_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/message_menu_chrome.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' show Pack, PackId, PackKind;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _cats = PackId('cats');
const _dogs = PackId('dogs');

void main() {
  Future<List<List<PackId>>> openMenu(
    WidgetTester tester,
    List<PackId> packs, {
    ChatMessageMenuMembership membership = ChatMessageMenuMembership.idle,
    ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
  }) async {
    final dataSource = _OneMessageSource();
    final selection = ChatSelectionController(policy: policy);
    final source = FakePackSource([
      Pack(id: _cats, kind: PackKind.emoji, title: 'Cats', items: const []),
    ]);
    addTearDown(dataSource.dispose);
    addTearDown(selection.dispose);
    addTearDown(source.dispose);
    final shown = <List<PackId>>[];
    final menu = MessageMenu(
      dataSource: dataSource,
      selection: selection,
      actions: MessageMenuActions(
        onDelete: (_) {},
        onEdit: (_) {},
        onEmojiPacks: shown.add,
      ),
      clipboard: FakeRichClipboard(),
      emojiPacks: MessageEmojiPacks(of: (_) => packs, source: source),
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
                  ChatMessageMenuRequest(
                    messageId: 1,
                    slotGlobal: const Rect.fromLTWH(0, 100, 300, 40),
                    tapGlobal: const Offset(10, 110),
                    membership: membership,
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
    await tester.pumpAndSettle();
    return shown;
  }

  testWidgets('names one pack by its title and opens it', (tester) async {
    final shown = await openMenu(tester, [_cats]);

    final entry = find.text(
      'This message contains emoji from Cats pack.',
      findRichText: true,
    );
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(shown, [
      [_cats],
    ]);
    expect(find.byType(ChatMessageMenuActionList), findsNothing);
  });

  testWidgets('on Android it is a row of the menu card, under a gap band '
      'across it, and it does not widen the card', (tester) async {
    await openMenu(tester, [_cats]);

    // The card's surface: the card widget itself may be stretched wider in
    // the menu's column, its surface held at its start.
    final card = find.descendant(
      of: find.byType(ChatMessageMenuCard),
      matching: find.byType(GlassSurface),
    );
    expect(card, findsOneWidget);
    final entry = find.text(
      'This message contains emoji from Cats pack.',
      findRichText: true,
    );
    expect(find.descendant(of: card, matching: entry), findsOneWidget);
    final band = find.descendant(
      of: card,
      matching: find.byType(MessageMenuGapBand),
    );
    expect(tester.getSize(band).height, 8);
    expect(tester.getSize(band).width, tester.getSize(card).width);
    expect(
      tester.getTopLeft(entry).dy,
      greaterThan(tester.getBottomLeft(band).dy),
    );
    // The card keeps the width of its rows: the entry wraps.
    expect(
      tester.getSize(card).width,
      lessThan(tester.getSize(entry).width + 200),
    );
  });

  testWidgets(
    'on a desktop it is a row of the menu card, under a separator: 11 px '
    'text 12 in and 4 down, no card of its own',
    (tester) async {
      final shown = await openMenu(tester, [
        _cats,
      ], policy: const ChatSelectionPolicy.desktop());

      expect(find.byType(ChatMessageMenuCard), findsOneWidget);
      final card = find.byType(ChatMessageMenuCard);
      final entry = find.text(
        'This message contains emoji from Cats pack.',
        findRichText: true,
      );
      expect(find.descendant(of: card, matching: entry), findsOneWidget);
      final row = find.byType(MessageContainsEmojiButton);
      expect(
        tester.getTopLeft(entry) - tester.getTopLeft(row),
        const Offset(12, 4),
      );
      expect(tester.getBottomLeft(row).dy - tester.getBottomLeft(entry).dy, 4);
      final text = tester.widget<RichText>(
        find.descendant(of: row, matching: find.byType(RichText)),
      );
      // The entry's own span, under the one the default style wraps it in.
      final span = (text.text as TextSpan).children!.single;
      expect(span.style?.fontSize, 11);
      expect(span.style?.color, PointerMenuTokens.night.text);
      // The separator above it: a 1 px line in the separator colour.
      final line = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox &&
              widget.color == PointerMenuTokens.night.separator,
        ),
      );
      expect(line, findsOneWidget);
      expect(tester.getSize(line).height, 1);
      expect(tester.getTopLeft(row).dy - tester.getBottomLeft(line).dy, 5);
      // No band of the card's own colour after the entry: the card ends 5
      // below it.
      expect(tester.getRect(card).bottom - tester.getBottomLeft(row).dy, 5);

      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(shown, [
        [_cats],
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('counts several packs and opens them all', (tester) async {
    final shown = await openMenu(tester, [_cats, _dogs]);

    final entry = find.text(
      'This message contains emoji from 2 Packs.',
      findRichText: true,
    );
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(shown, [
      [_cats, _dogs],
    ]);
  });

  testWidgets('is not offered for a message without emoji packs', (
    tester,
  ) async {
    await openMenu(tester, const []);

    expect(
      find.textContaining('contains emoji', findRichText: true),
      findsNothing,
    );
    expect(find.text('Reply'), findsOneWidget);
  });

  testWidgets('is not offered over a selection', (tester) async {
    await openMenu(tester, [
      _cats,
    ], membership: ChatMessageMenuMembership.elsewhere);

    expect(
      find.textContaining('contains emoji', findRichText: true),
      findsNothing,
    );
  });
}
