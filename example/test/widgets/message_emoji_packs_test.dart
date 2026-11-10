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
  }) async {
    final dataSource = _OneMessageSource();
    final selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.mobile(),
    );
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
