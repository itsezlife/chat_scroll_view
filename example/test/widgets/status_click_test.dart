/// The status of a message (its time, its delivery state) against the real
/// `ChatScrollView` and the demo's real rows, with a mouse.
///
/// Telegram Desktop shows the status of an emoji-only message while the
/// pointer is anywhere on the message's row, not only over the emoji box
/// (`ListWidget::mouseActionUpdate` finds the element under the cursor by `y`
/// alone and clamps `x` to the list; `UnwrappedMedia::needInfoDisplay` asks
/// `isUnderCursor`). A click on that status selects the message when nothing
/// is selected and toggles it in message selection
/// (`ListWidget::mouseActionFinish`, `CursorState::Date`); a right click opens
/// the message's menu. The time of an ordinary bubble keeps the tap barrier: a
/// mouse click on it is not a message tap.
///
/// These run the real viewport because its selection pointer sits above the
/// gesture arena: a detector inside the row cannot stop it, only the
/// viewport's own seam can.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_meta_pill.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
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

/// The demo treats these senders as the user's own (right-aligned rows).
const _incoming = 'Ann';
const _outgoing = 'Hixie';

IChatMessage _message(int id, {String content = 'hello', String? sender}) =>
    UserChatMessage(
      id: id,
      sender: sender ?? _incoming,
      createdAt: _time,
      updatedAt: _time,
      content: content,
    );

/// Three large emoji: the text layout.
const _glyphs = '\u{1F44D}\u{1F680}\u{1F525}';

/// One emoji the sticker pack has: the sticker layout.
const _sticker = '\u{1F44D}';

/// Where a mouse waits when it is on no row.
const _away = Offset(-50, -50);

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

  /// A widget test that runs as [platform]: the demo's emoji family follows the
  /// running platform, and a test is Android unless it says otherwise.
  void chatTest(
    String description,
    Future<void> Function(WidgetTester tester) body, {
    TargetPlatform platform = TargetPlatform.macOS,
  }) => testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  /// Mounts the [messages] as the demo's rows in a chat of the selection
  /// [selectionPolicy], with a mouse that waits off every row.
  Future<_Rig> mount(
    WidgetTester tester,
    List<IChatMessage> messages, {
    ChatSelectionPolicy selectionPolicy = const ChatSelectionPolicy.desktop(),
    int buttons = kPrimaryMouseButton,
  }) async {
    tester.view
      ..physicalSize = const Size(500, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selection = ChatSelectionController(policy: selectionPolicy);
    addTearDown(selection.dispose);
    final controller = ChatScrollController()..jumpTo(messages.length - 1);
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
            dataSource: _Source(messages),
            controller: controller,
            selectionController: selection,
            onIdleMessageTap: (request) => idle.add(request.messageId),
            onSecondaryMessageTap: (request) =>
                secondary.add(request.messageId),
            messageBuilder: (context, id, message, status, runLayout) =>
                KeyedSubtree(
                  key: ValueKey(id),
                  child: DemoMessageBubble(
                    message: message ?? messages[id],
                    runLayout: runLayout,
                    selection: selection,
                    host: host,
                  ),
                ),
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
    await mouse.addPointer(location: _away);
    return _Rig(selection, mouse, idle, secondary, stickers);
  }

  Finder inRow(int id, Finder finder) =>
      find.descendant(of: find.byKey(ValueKey(id)), matching: finder);

  /// The viewport's cell of row [id]: the whole width, margins included.
  Rect rowRect(WidgetTester tester, int id) =>
      tester.getRect(find.byKey(ValueKey(id)).first);

  /// The emoji body of row [id].
  Rect bodyRect(WidgetTester tester, int id) =>
      tester.getRect(inRow(id, find.byType(ChatEmojiBody)));

  /// Moves the mouse to [to] and lets the row react.
  Future<void> hover(WidgetTester tester, _Rig rig, Offset to) async {
    await rig.mouse.moveTo(to);
    await tester.pump();
  }

  /// Moves the mouse onto [onto], then clicks it with the button the rig was
  /// mounted with.
  Future<void> click(WidgetTester tester, _Rig rig, Offset onto) async {
    await hover(tester, rig, onto);
    await rig.mouse.down(onto);
    await tester.pump();
    await rig.mouse.up();
    await tester.pump();
  }

  /// A point of row [id] that is on no part of the message: the end edge of an
  /// incoming row, far from the emoji box.
  Offset emptySide(WidgetTester tester, int id) {
    final row = rowRect(tester, id);
    return Offset(row.right - 12, row.center.dy);
  }

  /// Hovers the empty side of row [id], so its hover-revealed pill exists.
  Future<void> reveal(WidgetTester tester, _Rig rig, int id) =>
      hover(tester, rig, emptySide(tester, id));

  Offset pillOf(WidgetTester tester, int id) =>
      tester.getCenter(inRow(id, find.byType(EmojiMetaPill)));

  group('hover-revealed pill of a large-emoji message', () {
    Future<_Rig> mountText(
      WidgetTester tester, {
      int buttons = kPrimaryMouseButton,
    }) => mount(tester, [
      for (var i = 0; i < 3; i++) _message(i, content: _glyphs),
    ], buttons: buttons);

    chatTest('is not there until the pointer is on the row', (tester) async {
      final rig = await mountText(tester);
      expect(find.byType(EmojiMetaPill), findsNothing);

      await hover(tester, rig, bodyRect(tester, 1).center);

      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);
    });

    chatTest('follows the pointer along the whole row, not the emoji box', (
      tester,
    ) async {
      final rig = await mountText(tester);
      final row = rowRect(tester, 1);
      final body = bodyRect(tester, 1);

      // The empty side of the row, far from the box.
      await hover(tester, rig, emptySide(tester, 1));
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);
      await hover(tester, rig, _away);
      expect(find.byType(EmojiMetaPill), findsNothing);

      // Beside the box, and in the avatar gutter at the start edge.
      await hover(tester, rig, Offset(body.right + 40, body.center.dy));
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);
      await hover(tester, rig, _away);
      await hover(tester, rig, Offset(row.left + 4, row.center.dy));
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);

      // The row's own margins above and below the box belong to it too.
      await hover(tester, rig, _away);
      await hover(tester, rig, Offset(body.center.dx, row.top + 1));
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);
      await hover(tester, rig, _away);
      await hover(tester, rig, Offset(body.center.dx, row.bottom - 1));
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);
    });

    chatTest('goes when the pointer leaves the row, and moves to the row '
        'it enters', (tester) async {
      final rig = await mountText(tester);
      await reveal(tester, rig, 1);
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);

      await reveal(tester, rig, 2);
      expect(inRow(1, find.byType(EmojiMetaPill)), findsNothing);
      expect(inRow(2, find.byType(EmojiMetaPill)), findsOneWidget);

      await hover(tester, rig, _away);
      expect(find.byType(EmojiMetaPill), findsNothing);
    });

    chatTest('of an outgoing row is always there, so hover adds nothing', (
      tester,
    ) async {
      final rig = await mount(tester, [
        for (var i = 0; i < 3; i++)
          _message(i, content: _glyphs, sender: _outgoing),
      ]);
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);

      await hover(tester, rig, rowRect(tester, 1).centerLeft);
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);
    });

    chatTest('a click on it selects the message, and one more unselects '
        'it', (tester) async {
      final rig = await mountText(tester);
      await reveal(tester, rig, 1);

      await click(tester, rig, pillOf(tester, 1));
      expect(rig.selection.selectedIds, <int>{1});
      expect(rig.selection.isSelectionMode, isTrue);

      await click(tester, rig, pillOf(tester, 1));
      expect(rig.selection.selectedIds, isEmpty);
      expect(rig.selection.isSelectionMode, isFalse);
    });

    chatTest('a click on it in message selection toggles that message', (
      tester,
    ) async {
      final rig = await mountText(tester);
      rig.selection.startSelection(0);
      await tester.pump();
      await reveal(tester, rig, 1);

      await click(tester, rig, pillOf(tester, 1));
      expect(rig.selection.selectedIds, <int>{0, 1});

      await click(tester, rig, pillOf(tester, 1));
      expect(rig.selection.selectedIds, <int>{0});
    });

    chatTest('a click beside it does what a click on the row does', (
      tester,
    ) async {
      final rig = await mountText(tester);
      rig.selection.startSelection(0);
      await tester.pump();
      await reveal(tester, rig, 1);

      await click(tester, rig, bodyRect(tester, 1).center);

      expect(rig.selection.selectedIds, <int>{0, 1});
    });

    chatTest('a click on it leaves the idle tap alone', (tester) async {
      final rig = await mountText(tester);
      await reveal(tester, rig, 1);

      await click(tester, rig, pillOf(tester, 1));

      expect(rig.idle, isEmpty);
    });

    chatTest('a drag that starts on it selects nothing', (tester) async {
      final rig = await mountText(tester);
      await reveal(tester, rig, 1);
      final pill = pillOf(tester, 1);

      await rig.mouse.moveTo(pill);
      await rig.mouse.down(pill);
      await rig.mouse.moveTo(pill + const Offset(0, -150));
      await tester.pump();
      await rig.mouse.up();
      await tester.pump();

      expect(rig.selection.selectedIds, isEmpty);
    });

    chatTest('a secondary click on it opens the message menu and selects '
        'nothing', (tester) async {
      final rig = await mountText(tester, buttons: kSecondaryMouseButton);
      await reveal(tester, rig, 1);

      await click(tester, rig, pillOf(tester, 1));

      expect(rig.secondary, <int>[1]);
      expect(rig.selection.selectedIds, isEmpty);
    });
  });

  group('pill of a sticker', () {
    Future<_Rig> mountSticker(
      WidgetTester tester, {
      int buttons = kPrimaryMouseButton,
    }) => mount(tester, [
      for (var i = 0; i < 3; i++) _message(i, content: _sticker),
    ], buttons: buttons);

    chatTest('is shown on the empty side of the row', (tester) async {
      final rig = await mountSticker(tester);
      expect(find.byType(EmojiMetaPill), findsNothing);

      await reveal(tester, rig, 1);
      expect(inRow(1, find.byType(EmojiMetaPill)), findsOneWidget);

      await hover(tester, rig, _away);
      expect(find.byType(EmojiMetaPill), findsNothing);
    });

    chatTest('a click on it selects the message and does not tap the '
        'sticker, and one more unselects it', (tester) async {
      final rig = await mountSticker(tester);
      await reveal(tester, rig, 1);

      await click(tester, rig, pillOf(tester, 1));
      expect(rig.selection.selectedIds, <int>{1});
      expect(rig.stickers, isEmpty);

      await click(tester, rig, pillOf(tester, 1));
      expect(rig.selection.selectedIds, isEmpty);
      expect(rig.stickers, isEmpty);
    });

    chatTest('a click on it in message selection toggles that message', (
      tester,
    ) async {
      final rig = await mountSticker(tester);
      rig.selection.startSelection(0);
      await tester.pump();
      await reveal(tester, rig, 1);

      await click(tester, rig, pillOf(tester, 1));

      expect(rig.selection.selectedIds, <int>{0, 1});
      expect(rig.stickers, isEmpty);
    });

    chatTest('a click beside it, on the row, still toggles the message', (
      tester,
    ) async {
      final rig = await mountSticker(tester);
      rig.selection.startSelection(0);
      await tester.pump();

      await click(tester, rig, emptySide(tester, 1));

      expect(rig.selection.selectedIds, <int>{0, 1});
    });

    chatTest('a secondary click on it opens the message menu', (tester) async {
      final rig = await mountSticker(tester, buttons: kSecondaryMouseButton);
      await reveal(tester, rig, 1);

      await click(tester, rig, pillOf(tester, 1));

      expect(rig.secondary, <int>[1]);
      expect(rig.selection.selectedIds, isEmpty);
    });
  });

  group('pill under the mobile selection policy', () {
    const mobile = ChatSelectionPolicy.mobile();

    Future<_Rig> mountMobile(WidgetTester tester) => mount(tester, [
      for (var i = 0; i < 3; i++) _message(i, content: _glyphs),
    ], selectionPolicy: mobile);

    chatTest(
      'a touch tap on it is a message tap: it opens the idle '
      'chrome, and in message selection it toggles the row',
      platform: TargetPlatform.android,
      (tester) async {
        final rig = await mountMobile(tester);

        final touch = await tester.startGesture(pillOf(tester, 1));
        await touch.up();
        await tester.pump(const Duration(milliseconds: 100));
        expect(rig.idle, <int>[1]);
        expect(rig.selection.selectedIds, isEmpty);

        rig.selection.startSelection(0);
        await tester.pump();
        final again = await tester.startGesture(pillOf(tester, 1));
        await again.up();
        await tester.pump(const Duration(milliseconds: 100));
        expect(rig.selection.selectedIds, <int>{0, 1});
      },
    );

    chatTest(
      'a mouse click on it does not select the message',
      platform: TargetPlatform.android,
      (tester) async {
        final rig = await mountMobile(tester);

        await click(tester, rig, pillOf(tester, 1));

        expect(rig.selection.selectedIds, isEmpty);
      },
    );
  });

  group('time of an ordinary message', () {
    Future<_Rig> mountBubble(
      WidgetTester tester, {
      int buttons = kPrimaryMouseButton,
    }) => mount(tester, [
      for (var i = 0; i < 3; i++) _message(i),
    ], buttons: buttons);

    chatTest('a click on it does not toggle the message, and one on the '
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

    chatTest('a secondary click on it opens the message menu', (tester) async {
      final rig = await mountBubble(tester, buttons: kSecondaryMouseButton);

      await click(tester, rig, tester.getCenter(inRow(1, find.text('09:05'))));

      expect(rig.secondary, <int>[1]);
    });
  });
}
