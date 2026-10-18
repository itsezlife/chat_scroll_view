/// A mouse click on a message's status (the time, the delivery state) is not a
/// message tap: it does not select or unselect the message, and the drag that
/// starts on it does not drag-select. A secondary click on it opens the
/// message's menu, as it does beside it.
///
/// These run the real `ChatScrollView` with a mouse pointer, because the
/// viewport's selection pointer sits above the gesture arena: a detector inside
/// the row cannot stop it, only the viewport's own seam can.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_emoji_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_meta_pill.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source extends ChatDataSource {
  _Source(List<IChatMessage> messages) {
    upsertMessages(messages);
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

final _time = DateTime(2026, 1, 1, 9, 5);

IChatMessage _message(int id) => UserChatMessage(
  id: id,
  sender: 'Ann',
  createdAt: _time,
  updatedAt: _time,
  content: 'hello $id',
);

final _glyphs = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
  EmojiOnlyItem(ContentKey.unicode('\u{1F680}')),
  EmojiOnlyItem(ContentKey.unicode('\u{1F525}')),
]);
final _sticker = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
]);

const _desktop = ChatEmojiPolicy.desktop();

/// What one mounted chat records.
class _Rig {
  _Rig(this.selection, this.mouse, this.idle, this.secondary, this.stickers);

  final ChatSelectionController selection;
  final TestGesture mouse;
  final List<int> idle;
  final List<int> secondary;
  final List<int> stickers;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssetCacheScope scope;
  late ValueNotifier<LargeEmojiPolicy> policy;
  late ChatBodyHost host;

  setUp(() {
    scope = AssetCacheScope(producer: FakeAssetProducer());
    policy = ValueNotifier(const LargeEmojiPolicy(enabled: true));
    host = ChatBodyHost(assets: scope, policy: policy);
  });
  tearDown(() {
    policy.dispose();
    scope.dispose();
  });

  /// Mounts three rows built by [row] in a desktop-policy chat, with a mouse.
  Future<_Rig> mount(
    WidgetTester tester,
    Widget Function(int id, ChatSelectionController selection) row, {
    int buttons = kPrimaryMouseButton,
  }) async {
    tester.view
      ..physicalSize = const Size(500, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.desktop(),
    );
    addTearDown(selection.dispose);
    final controller = ChatScrollController()..jumpTo(2);
    addTearDown(controller.dispose);
    final idle = <int>[];
    final secondary = <int>[];
    final stickers = <int>[];
    selection.addInteractionListener((interaction) {
      if (interaction is ChatStickerActivated) {
        stickers.add(interaction.messageId);
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: child!,
        ),
        home: Scaffold(
          body: ChatScrollView(
            dataSource: _Source([for (var i = 0; i < 3; i++) _message(i)]),
            controller: controller,
            selectionController: selection,
            onIdleMessageTap: (request) => idle.add(request.messageId),
            onSecondaryMessageTap: (request) =>
                secondary.add(request.messageId),
            messageBuilder: (context, id, message, status, runLayout) =>
                KeyedSubtree(key: ValueKey(id), child: row(id, selection)),
          ),
        ),
      ),
    );
    await tester.pump();
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(490, 790));
    return _Rig(selection, mouse, idle, secondary, stickers);
  }

  Finder inRow(int id, Finder finder) =>
      find.descendant(of: find.byKey(ValueKey(id)), matching: finder);

  Widget emojiRow(
    int id,
    ChatSelectionController selection, {
    required EmojiOnly emoji,
    bool outgoing = false,
    bool lastOwn = false,
  }) => DemoEmojiMessage(
    messageId: id,
    emojiOnly: emoji,
    selection: selection,
    host: host,
    createdAt: _time,
    isOutgoing: outgoing,
    isLastOwn: lastOwn,
    policy: _desktop,
  );

  /// Moves the mouse onto [onto] (so a hover-revealed pill is shown), then
  /// clicks it with the button the rig was mounted with.
  Future<void> click(WidgetTester tester, _Rig rig, Offset onto) async {
    await rig.mouse.moveTo(onto);
    await tester.pump();
    await rig.mouse.down(onto);
    await tester.pump();
    await rig.mouse.up();
    await tester.pump();
  }

  /// Hovers the body of row [id], so its hover-revealed pill exists.
  Future<void> reveal(WidgetTester tester, _Rig rig, int id) async {
    await rig.mouse.moveTo(
      tester.getCenter(inRow(id, find.byType(ChatEmojiBody))),
    );
    await tester.pump();
  }

  group('hover-revealed pill of a large-emoji message', () {
    Future<_Rig> mountText(
      WidgetTester tester, {
      int buttons = kPrimaryMouseButton,
    }) => mount(
      tester,
      (id, selection) => emojiRow(id, selection, emoji: _glyphs),
      buttons: buttons,
    );

    testWidgets('is not there until the pointer is on the row, and is then', (
      tester,
    ) async {
      final rig = await mountText(tester);
      expect(find.byType(EmojiMetaPill), findsNothing);

      await reveal(tester, rig, 1);

      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);
    });

    testWidgets('a click on it does not select the message', (tester) async {
      final rig = await mountText(tester);
      await reveal(tester, rig, 1);

      await click(tester, rig, tester.getCenter(find.byType(EmojiMetaPill)));

      expect(rig.selection.selectedIds, isEmpty);
      expect(rig.selection.isSelectionMode, isFalse);
    });

    testWidgets('a click on it does not unselect a selected message, and the '
        'same click beside it does', (tester) async {
      final rig = await mountText(tester);
      rig.selection
        ..startSelection(0)
        ..toggle(1);
      await tester.pump();
      await reveal(tester, rig, 1);

      await click(tester, rig, tester.getCenter(find.byType(EmojiMetaPill)));
      expect(rig.selection.selectedIds, <int>{0, 1});

      await click(
        tester,
        rig,
        tester.getCenter(inRow(1, find.byType(ChatEmojiBody))),
      );
      expect(rig.selection.selectedIds, <int>{0});
    });

    testWidgets('a click on it does not select another message while a '
        'selection is live, and one beside it does', (tester) async {
      final rig = await mountText(tester);
      rig.selection.startSelection(0);
      await tester.pump();
      await reveal(tester, rig, 1);

      await click(tester, rig, tester.getCenter(find.byType(EmojiMetaPill)));
      expect(rig.selection.selectedIds, <int>{0});

      await click(
        tester,
        rig,
        tester.getCenter(inRow(1, find.byType(ChatEmojiBody))),
      );
      expect(rig.selection.selectedIds, <int>{0, 1});
    });

    testWidgets('a drag that starts on it selects nothing', (tester) async {
      final rig = await mountText(tester);
      await reveal(tester, rig, 1);
      final pill = tester.getCenter(find.byType(EmojiMetaPill));

      await rig.mouse.moveTo(pill);
      await rig.mouse.down(pill);
      await rig.mouse.moveTo(pill + const Offset(0, -150));
      await tester.pump();
      await rig.mouse.up();
      await tester.pump();

      expect(rig.selection.selectedIds, isEmpty);
    });

    testWidgets('a secondary click on it opens the message menu, as beside '
        'it', (tester) async {
      final rig = await mountText(tester, buttons: kSecondaryMouseButton);
      await reveal(tester, rig, 1);

      await click(tester, rig, tester.getCenter(find.byType(EmojiMetaPill)));

      expect(rig.secondary, <int>[1]);
    });
  });

  group('pill of a sticker', () {
    Future<_Rig> mountSticker(WidgetTester tester) => mount(
      tester,
      (id, selection) => emojiRow(
        id,
        selection,
        emoji: _sticker,
        outgoing: true,
        lastOwn: true,
      ),
    );

    testWidgets('a click on it neither toggles the message nor taps the '
        'sticker', (tester) async {
      final rig = await mountSticker(tester);
      rig.selection.startSelection(0);
      await tester.pump();

      await click(
        tester,
        rig,
        tester.getCenter(inRow(1, find.byType(EmojiMetaPill))),
      );

      expect(rig.selection.selectedIds, <int>{0});
      expect(rig.stickers, isEmpty);
    });

    testWidgets('a click beside it, on the row, still toggles the message', (
      tester,
    ) async {
      final rig = await mountSticker(tester);
      rig.selection.startSelection(0);
      await tester.pump();
      final art = tester.getRect(inRow(1, find.byType(ChatEmojiBody)));

      await click(tester, rig, Offset(400, art.center.dy));

      expect(rig.selection.selectedIds, <int>{0, 1});
    });
  });

  group('time of an ordinary message', () {
    Future<_Rig> mountBubble(
      WidgetTester tester, {
      int buttons = kPrimaryMouseButton,
    }) => mount(
      tester,
      (id, selection) => DemoMessageBubble(
        message: _message(id),
        selection: selection,
        host: host,
      ),
      buttons: buttons,
    );

    testWidgets('a click on it does not toggle the message, and one on the '
        'bubble does', (tester) async {
      final rig = await mountBubble(tester);
      rig.selection.startSelection(0);
      await tester.pump();

      await click(tester, rig, tester.getCenter(inRow(1, find.text('09:05'))));
      expect(rig.selection.selectedIds, <int>{0});

      await click(
        tester,
        rig,
        tester.getTopLeft(inRow(1, find.byType(DemoMessageMeta))) -
            const Offset(40, 0),
      );
      expect(rig.selection.selectedIds, <int>{0, 1});
    });

    testWidgets('a secondary click on it opens the message menu', (
      tester,
    ) async {
      final rig = await mountBubble(tester, buttons: kSecondaryMouseButton);

      await click(tester, rig, tester.getCenter(inRow(1, find.text('09:05'))));

      expect(rig.secondary, <int>[1]);
    });
  });
}
