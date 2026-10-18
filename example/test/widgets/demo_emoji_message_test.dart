/// The chrome of an emoji-only message as it is drawn, per platform family:
/// the widget puts the pill, header and reactions where the pure placement
/// (`emoji_chrome_test.dart`) says, around the body's own geometry.
///
/// Flutter test draws text in the Ahem font, whose glyphs are as wide as they
/// are high, so the time `09:05` is 5 em wide: 60 at 12, 55 at 11, 65 at 13.
/// Expected numbers are worked from that and from the platform tables, not read
/// back from the code under test.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_emoji_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_glyphs.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_header_panel.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_meta_pill.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_reactions_row.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _sticker = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
]);
final _three = EmojiOnly([
  for (var i = 0; i < 3; i++) EmojiOnlyItem(ContentKey.document('d$i')),
]);
final _threeGlyphs = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
  EmojiOnlyItem(ContentKey.unicode('\u{1F680}')),
  EmojiOnlyItem(ContentKey.unicode('\u{1F525}')),
]);

const _android = ChatEmojiPolicy.android();
const _ios = ChatEmojiPolicy.ios();
const _desktop = ChatEmojiPolicy.desktop();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssetCacheScope scope;
  late ValueNotifier<LargeEmojiPolicy> policy;
  late ChatBodyHost host;
  late ChatSelectionController selection;

  setUp(() {
    scope = AssetCacheScope(producer: FakeAssetProducer());
    policy = ValueNotifier(const LargeEmojiPolicy(enabled: true));
    host = ChatBodyHost(assets: scope, policy: policy);
    selection = ChatSelectionController();
  });
  tearDown(() {
    selection.dispose();
    policy.dispose();
    scope.dispose();
  });

  Future<void> pump(
    WidgetTester tester,
    EmojiOnly emojiOnly, {
    required ChatEmojiPolicy platform,
    TextDirection direction = TextDirection.ltr,
    bool outgoing = false,
    EmojiHeaderData? header,
    List<EmojiReaction> reactions = const [],
    bool edited = false,
    int? views,
    EmojiSendState? sendState,
    Color? wallpaper,
    bool isLastOwn = false,
    bool hovered = false,
    double width = 340,
    bool physicalSides = true,
    double selected = 0,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Align(
                  // A platform that does not mirror keeps the sides, so the
                  // host's row does too; desktop's follows the direction.
                  alignment: physicalSides
                      ? (outgoing
                            ? Alignment.centerRight
                            : Alignment.centerLeft)
                      : (outgoing
                            ? AlignmentDirectional.centerEnd
                            : AlignmentDirectional.centerStart),
                  child: ChatSelectionStateScope(
                    state: ChatSelectionChromeState(
                      id: 1,
                      modeProgress: selected,
                      selectProgress: selected,
                      isSelectionMode: selected > 0,
                      isSelected: selected > 0,
                      showsCheck: true,
                      onTap: () {},
                      onLongPress: () {},
                    ),
                    child: DemoEmojiMessage(
                      messageId: 1,
                      emojiOnly: emojiOnly,
                      selection: selection,
                      host: host,
                      createdAt: DateTime(2026, 1, 1, 9, 5),
                      isOutgoing: outgoing,
                      edited: edited,
                      views: views,
                      header: header,
                      reactions: reactions,
                      sendState: sendState,
                      policy: platform,
                      wallpaper: wallpaper,
                      isLastOwn: isLastOwn,
                      hovered: hovered,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect body(WidgetTester tester) => tester.getRect(find.byType(ChatEmojiBody));
  Rect pill(WidgetTester tester) => tester.getRect(find.byType(EmojiMetaPill));
  Rect header(WidgetTester tester) =>
      tester.getRect(find.byType(EmojiHeaderPanel));
  Matcher near(double value) => closeTo(value, 0.01);
  const reply = EmojiHeaderData.reply(sender: 'Ann', text: 'see you');

  BoxDecoration pillDecoration(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(
                find
                    .descendant(
                      of: find.byType(EmojiMetaPill),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration;

  EmojiTicksPainter ticks(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byType(EmojiMetaPill),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter!
          as EmojiTicksPainter;

  group('Android', () {
    group('enlarged text', () {
      testWidgets('reserves a 23 dp strip under the emoji and puts the pill '
          '3 dp below them, 1 dp inside their end', (tester) async {
        await pump(tester, _three, platform: _android);

        final box = body(tester);
        // 3 custom emoji: 55.2 + 4 = 59.2 boxes, 177.6 wide.
        expect(box.width, near(177.6));
        expect(box.height, near(59.2 + 23));
        final p = pill(tester);
        // The time is 60 wide, the pill 72: 12 + 60, ending at 176.6.
        expect(p.size, const Size(72, 17));
        expect(p.right - box.left, near(176.6));
        expect(p.top - box.top, near(59.2 + 3));
      });

      testWidgets('an outgoing pill is 4 dp inside the end and carries 24 dp '
          'for the ticks', (tester) async {
        await pump(tester, _three, platform: _android, outgoing: true);

        final box = body(tester);
        final p = pill(tester);
        expect(p.width, near(96));
        expect(box.right - p.right, near(4));
        expect(box.right, near(340));
      });

      testWidgets('a narrow message: the pill starts at max(3, text - 13 - '
          'time)', (tester) async {
        final two = EmojiOnly(const [
          EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
          EmojiOnlyItem(ContentKey.unicode('\u{1F680}')),
        ]);
        await pump(tester, two, platform: _android);

        // 2 mixed glyphs: 44.8 boxes, 89.6 wide: 89.6 - 13 - 60 = 16.6.
        expect(pill(tester).left - body(tester).left, near(16.6));
      });

      testWidgets('the pill wider than the emoji is not clipped: the chrome '
          'grows to hold it', (tester) async {
        final one = EmojiOnly(const [
          EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
          EmojiOnlyItem(ContentKey.unicode('\u{1F680}')),
        ]);
        await pump(tester, one, platform: _android, edited: true);

        // `edited 09:05` is 12 em = 144 wide, the pill 156: wider than the
        // 89.6 box. Nothing paints outside the chrome's own box.
        final chrome = tester.getRect(find.byType(DemoEmojiMessage));
        expect(chrome.width, greaterThanOrEqualTo(pill(tester).width));
        expect(chrome.left, lessThanOrEqualTo(pill(tester).left + 0.01));
        expect(chrome.right, greaterThanOrEqualTo(pill(tester).right - 0.01));
        expect(find.text('edited 09:05'), findsOneWidget);
      });
    });

    group('a sticker', () {
      testWidgets('has the pill over the art, [-7, +10] of its bottom edge, '
          'and the strip below it', (tester) async {
        await pump(tester, _sticker, platform: _android);

        final art = body(tester);
        expect(art.width, near(112.5));
        expect(art.height, near(112.5 + 25));
        expect(pill(tester).top - art.top, near(105.5));
        // 112.5 - 17 - 60 = 35.5 from the art's start.
        expect(pill(tester).left - art.left, near(35.5));
      });

      testWidgets('has its header beside it, 18 dp after it for an incoming '
          'message', (tester) async {
        await pump(tester, _sticker, platform: _android, header: reply);

        expect(header(tester).left - body(tester).right, near(18));
        expect(header(tester).top - body(tester).top, near(4.66));
      });

      testWidgets('has an outgoing header pinned at the row\'s left, not '
          'adjacent', (tester) async {
        await pump(
          tester,
          _sticker,
          platform: _android,
          header: reply,
          outgoing: true,
        );

        expect(header(tester).left, near(16));
        expect(header(tester).right, lessThan(body(tester).left - 20));
      });
    });

    group('headers', () {
      testWidgets('a reply is above the text, left-aligned 2 dp before the '
          'box for an incoming sender, 9 for an outgoing one, 43 dp high', (
        tester,
      ) async {
        await pump(tester, _three, platform: _android, header: reply);

        expect(header(tester).height, near(43));
        expect(header(tester).bottom - body(tester).top, near(-13.34));
        expect(header(tester).left - body(tester).left, near(-2));

        await pump(
          tester,
          _three,
          platform: _android,
          header: reply,
          outgoing: true,
        );
        expect(header(tester).left - body(tester).left, near(-9));
      });

      testWidgets('a forward is 44 dp high; with a reply one 84 dp panel', (
        tester,
      ) async {
        await pump(
          tester,
          _three,
          platform: _android,
          header: const EmojiHeaderData.forward('Ann'),
        );
        expect(header(tester).height, near(44));

        await pump(
          tester,
          _three,
          platform: _android,
          header: const EmojiHeaderData(
            replySender: 'Ann',
            replyText: 'see you',
            forwardedFrom: 'Bob',
          ),
        );
        expect(header(tester).height, near(84));
        expect(find.text('Forwarded from'), findsOneWidget);
      });

      testWidgets('a reply has a 3 dp white bar and a 4 dp radius', (
        tester,
      ) async {
        await pump(tester, _three, platform: _android, header: reply);

        final panel = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(EmojiHeaderPanel),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
          (panel.decoration as BoxDecoration).borderRadius,
          BorderRadius.circular(4),
        );
        final bar = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(EmojiHeaderPanel),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(bar.color, const Color(0xFFFFFFFF));
      });

      testWidgets('the text wraps at 65 % of the screen under a header', (
        tester,
      ) async {
        final many = EmojiOnly([
          for (var i = 0; i < 12; i++)
            EmojiOnlyItem(ContentKey.document('d$i')),
        ]);
        await pump(tester, many, platform: _android);
        final free = body(tester).width;

        await pump(tester, many, platform: _android, header: reply);

        expect(body(tester).width, lessThan(free));
        expect(body(tester).width, lessThanOrEqualTo(360 * 0.65 + 0.5));
      });
    });

    group('the pill', () {
      testWidgets('is 17 dp high with a 12 dp radius for either layout', (
        tester,
      ) async {
        await pump(tester, _three, platform: _android);
        expect(pill(tester).height, near(17));
        expect(pillDecoration(tester).borderRadius, BorderRadius.circular(12));

        await pump(tester, _sticker, platform: _android);
        expect(pillDecoration(tester).borderRadius, BorderRadius.circular(12));
      });

      testWidgets('is the service colour at 60 % of its alpha; a wallpaper '
          'the host gives changes it', (tester) async {
        await pump(tester, _three, platform: _android);
        final byDefault = pillDecoration(tester).color!;
        expect(byDefault.a, closeTo(0x66 / 255 * 0.6, 0.004));

        await pump(
          tester,
          _three,
          platform: _android,
          wallpaper: const Color(0xFFFFFFFF),
        );
        final lighter = pillDecoration(tester).color!;
        expect(lighter.a, closeTo(byDefault.a, 0.004));
        expect(lighter.g, greaterThan(byDefault.g));
      });

      testWidgets('says `edited 09:05` as one string', (tester) async {
        await pump(tester, _three, platform: _android, edited: true);

        expect(find.text('edited 09:05'), findsOneWidget);
        expect(find.text('edited'), findsNothing);
      });

      testWidgets('shows the views before the time', (tester) async {
        await pump(tester, _three, platform: _android, views: 1234);

        expect(find.text('1.2K'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('1.2K')).dx,
          lessThan(tester.getTopLeft(find.text('09:05')).dx),
        );
      });

      for (final (state, label) in [
        (EmojiSendState.sending, 'a clock'),
        (EmojiSendState.sent, 'one check'),
        (EmojiSendState.read, 'two checks'),
        (EmojiSendState.error, 'the error square'),
      ]) {
        testWidgets('an outgoing message shows $label', (tester) async {
          await pump(
            tester,
            _three,
            platform: _android,
            outgoing: true,
            sendState: state,
          );

          expect(ticks(tester).state, state);
          expect(ticks(tester).vector, isFalse);
        });
      }

      testWidgets('an incoming message has no ticks', (tester) async {
        await pump(tester, _three, platform: _android);

        expect(
          find.descendant(
            of: find.byType(EmojiMetaPill),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );
      });
    });

    group('reactions', () {
      const reactions = [
        EmojiReaction('\u{1F44D}', 3),
        EmojiReaction('\u{2764}', 1),
      ];

      testWidgets('are 26 dp chips, 29 dp under the text, below the pill', (
        tester,
      ) async {
        await pump(tester, _three, platform: _android, reactions: reactions);

        final row = tester.getRect(find.byType(EmojiReactionsRow));
        expect(row.height, near(26));
        expect(row.top - body(tester).top, near(59.2 + 29));
        expect(row.left, near(body(tester).left));
        expect(row.top, greaterThan(pill(tester).bottom));
      });

      testWidgets('an outgoing row ends at the text\'s end', (tester) async {
        await pump(
          tester,
          _three,
          platform: _android,
          outgoing: true,
          reactions: reactions,
        );

        expect(
          tester.getRect(find.byType(EmojiReactionsRow)).right,
          near(body(tester).right),
        );
      });
    });

    testWidgets('right to left does not mirror: an incoming message stays at '
        'the left and the pill is where it was', (tester) async {
      await pump(tester, _three, platform: _android);
      final ltrPill = pill(tester).left - body(tester).left;

      await pump(
        tester,
        _three,
        platform: _android,
        direction: TextDirection.rtl,
      );

      expect(body(tester).left, near(0));
      expect(pill(tester).left - body(tester).left, near(ltrPill));
    });

    testWidgets('selection paints nothing of its own: the viewport tints the '
        'row', (tester) async {
      await pump(tester, _three, platform: _android, selected: 1);

      expect(find.byType(ColorFiltered), findsNothing);
    });
  });

  group('iOS', () {
    testWidgets('has a fully rounded pill, always shown, 11 pt text', (
      tester,
    ) async {
      await pump(tester, _three, platform: _ios);

      // 3 custom: iOS 64 pt font, 68 boxes: 204 wide.
      final box = body(tester);
      expect(box.width, near(204));
      final p = pill(tester);
      // `09:05` at 11 pt is 55, date + 14 = 69.
      expect(p.size, const Size(69, 17));
      expect(pillDecoration(tester).borderRadius, BorderRadius.circular(8.5));
      // 4 pt inside the box's end and bottom; the strip is 20 pt.
      expect(box.height, near(68 + 20));
      expect(box.right - p.right, near(4));
      expect(box.bottom - p.bottom, near(4));
    });

    testWidgets('a sticker is 112 pt art in a 10 pt inset, the pill 4 pt '
        'inside the frame', (tester) async {
      await pump(tester, _sticker, platform: _ios);

      final box = body(tester);
      expect(box.size, const Size(132, 132));
      expect(box.right - pill(tester).right, near(4));
    });

    testWidgets('draws vector ticks', (tester) async {
      await pump(
        tester,
        _three,
        platform: _ios,
        outgoing: true,
        sendState: EmojiSendState.sent,
      );

      expect(ticks(tester).vector, isTrue);
    });

    testWidgets('puts a reply beside the text, pinned to the far edge, '
        'never above it', (tester) async {
      await pump(tester, _three, platform: _ios, header: reply);

      expect(header(tester).right, near(340 - 12));
      expect(header(tester).bottom, greaterThan(body(tester).top));

      await pump(tester, _three, platform: _ios, header: reply, outgoing: true);
      expect(header(tester).left, near(14));
    });

    testWidgets('the default colour is #748391 at 0.45; a wallpaper makes '
        'it black at 0.2', (tester) async {
      await pump(tester, _three, platform: _ios);
      expect(pillDecoration(tester).color!.a, closeTo(0.45, 0.004));

      await pump(
        tester,
        _three,
        platform: _ios,
        wallpaper: const Color(0xFF123456),
      );
      expect(pillDecoration(tester).color!.a, closeTo(0.2, 0.004));
      expect(pillDecoration(tester).color!.r, 0);
    });

    testWidgets('does not mirror in a right-to-left chat', (tester) async {
      await pump(
        tester,
        _three,
        platform: _ios,
        direction: TextDirection.rtl,
        outgoing: true,
      );

      expect(body(tester).right, near(340));
    });

    testWidgets('selection paints nothing of its own', (tester) async {
      await pump(tester, _three, platform: _ios, selected: 1);

      expect(find.byType(ColorFiltered), findsNothing);
    });
  });

  group('Desktop', () {
    testWidgets('shows no time on an incoming message until the pointer is '
        'on its row', (tester) async {
      await pump(tester, _threeGlyphs, platform: _desktop);
      expect(find.byType(EmojiMetaPill), findsNothing);

      await pump(tester, _threeGlyphs, platform: _desktop, hovered: true);

      // 38 px images, 2 apart: 118 wide, a 65 + 16 = 81 pill 6 px after.
      expect(body(tester).size, const Size(118, 38));
      expect(pill(tester).left - body(tester).right, near(6));
      expect(pill(tester).width, near(81));
      expect(pill(tester).bottom, near(body(tester).bottom));
    });

    testWidgets('always shows an outgoing large emoji\'s time, under the '
        'glyphs, ending where they end', (tester) async {
      await pump(tester, _threeGlyphs, platform: _desktop, outgoing: true);

      // Time 65 + status 24 + 16.
      expect(pill(tester).width, near(105));
      expect(pill(tester).top - body(tester).top, near(38 + 2));
      expect(pill(tester).right, near(body(tester).right));
    });

    testWidgets('shows a time on the last own sticker, over its bottom-end '
        'corner', (tester) async {
      await pump(
        tester,
        _sticker,
        platform: _desktop,
        outgoing: true,
        isLastOwn: true,
      );

      expect(body(tester).size, const Size(112, 112));
      expect(pill(tester).bottom, near(body(tester).bottom));
      expect(pill(tester).right, near(body(tester).right));
    });

    testWidgets('puts a reply beside when it fits and above when it does '
        'not', (tester) async {
      await pump(tester, _threeGlyphs, platform: _desktop, header: reply);
      expect(header(tester).left - body(tester).right, near(6));

      // 3 custom emoji: 58 px boxes, 174 wide; 174 + 86 passes a 250 row.
      await pump(tester, _three, platform: _desktop, header: reply, width: 250);
      expect(header(tester).bottom, lessThanOrEqualTo(body(tester).top));
    });

    testWidgets('selection recolours the glyphs, in proportion to its '
        'progress', (tester) async {
      await pump(tester, _threeGlyphs, platform: _desktop);
      expect(find.byType(ColorFiltered), findsNothing);

      await pump(tester, _threeGlyphs, platform: _desktop, selected: 1);

      final filter = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
      expect(filter.colorFilter, isNotNull);
    });

    testWidgets('mirrors in a right-to-left chat', (tester) async {
      await pump(tester, _threeGlyphs, platform: _desktop, header: reply);
      expect(header(tester).left - body(tester).left, greaterThan(0));

      await pump(
        tester,
        _threeGlyphs,
        platform: _desktop,
        header: reply,
        direction: TextDirection.rtl,
        physicalSides: false,
      );

      expect(header(tester).right, lessThan(body(tester).left + 0.01));
    });
  });
}
