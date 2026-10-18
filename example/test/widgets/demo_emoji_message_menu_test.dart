/// The message menu open on an emoji-only message (mobile sheet): the scrim
/// dims everything but what the message paints.
///
/// An emoji-only message has no bubble. The reference client redraws the
/// message above a flat black dim, so the glyphs or the sticker's art, the
/// time pill, the reply panel and the reactions stay bright, each in its own
/// shape, and what lies between them stays dimmed (`Telegram`
/// `ChatActivity.java` 17630-17700: the `scrimPaint` rect, then the cell drawn
/// again). The expected points here are worked from where the widgets are laid
/// out, not read back from the code under test.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_header_panel.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_meta_pill.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_reactions_row.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/emoji_menu_rig.dart';

final _text = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
  EmojiOnlyItem(ContentKey.unicode('\u{1F680}')),
  EmojiOnlyItem(ContentKey.unicode('\u{1F525}')),
]);
final _sticker = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EmojiMenuRig rig;
  setUp(() => rig = EmojiMenuRig());
  tearDown(() => rig.dispose());

  Rect pill(WidgetTester t) => t.getRect(find.byType(EmojiMetaPill));
  Rect header(WidgetTester t) => t.getRect(find.byType(EmojiHeaderPanel));
  List<Rect> chips(WidgetTester t) => [
    for (final chip
        in find
            .descendant(
              of: find.byType(EmojiReactionsRow),
              matching: find.byType(DecoratedBox),
            )
            .evaluate())
      t.getRect(find.byElementPredicate((e) => e == chip)),
  ];

  // Black at 0.2 on a dark scheme, as Android's `dimBehindView(true)`.
  const dim = Color.fromRGBO(0, 0, 0, 0.2);

  const platforms = <String, ChatEmojiPolicy>{
    'android': ChatEmojiPolicy.android(),
    'ios': ChatEmojiPolicy.ios(),
  };
  final layouts = <String, EmojiOnly>{'text': _text, 'sticker': _sticker};
  const sides = <String, (TextDirection, bool)>{
    'incoming ltr': (TextDirection.ltr, false),
    'outgoing ltr': (TextDirection.ltr, true),
    'incoming rtl': (TextDirection.rtl, false),
    'outgoing rtl': (TextDirection.rtl, true),
  };

  for (final MapEntry(key: family, value: platform) in platforms.entries) {
    for (final MapEntry(key: layout, value: emoji) in layouts.entries) {
      for (final MapEntry(key: side, value: (direction, outgoing))
          in sides.entries) {
        for (final decorated in [false, true]) {
          final name =
              '$family $layout $side'
              '${decorated ? ' with a reply and reactions' : ''}';

          testWidgets('$name: the art, pill, reply and reactions are bright '
              'in their own shapes, the rest of the box is dimmed', (
            tester,
          ) async {
            await rig.show(
              tester,
              emoji,
              platform: platform,
              direction: direction,
              outgoing: outgoing,
              decorated: decorated,
            );
            await rig.open(tester);

            // What the viewport's body says it paints: the glyph run or the
            // sticker's art, without the strip kept for the pill.
            final bodyBox = tester.getRect(find.byType(ChatEmojiBody));
            final geometry = ChatEmojiBody.geometryFor(
              emojiOnly: emoji,
              policy: platform,
              sticker: rig.host.stickerOf(emoji),
              viewport: EmojiMenuRig.screen,
              maxWidth: EmojiMenuRig.rowWidth,
              direction: direction,
              hasHeader: decorated && layout == 'text',
            );
            final art = geometry.content.shift(bodyBox.topLeft);
            final p = pill(tester);
            final panel = decorated ? header(tester) : null;
            final reactions = decorated ? chips(tester) : const <Rect>[];
            final box = tester.getRect(find.byType(ChatMessageSurfaceBounds));
            final parts = <Rect>[art, p, ?panel, ...reactions];
            bool covered(Offset point) => parts.any((r) => r.contains(point));

            final bright = <Offset>[
              art.center,
              // The art's corners are square: a bubble would round them.
              art.topLeft + const Offset(0.5, 0.5),
              art.topRight + const Offset(-0.5, 0.5),
              art.bottomLeft + const Offset(0.5, -0.5),
              art.bottomRight + const Offset(-0.5, -0.5),
              p.center,
              ?panel?.center,
              for (final chip in reactions) chip.center,
            ];
            final dimmed = <Offset>[
              // Every corner of the box no part reaches.
              for (final corner in [
                box.topLeft + const Offset(1, 1),
                box.topRight + const Offset(-1, 1),
                box.bottomLeft + const Offset(1, -1),
                box.bottomRight + const Offset(-1, -1),
              ])
                if (!covered(corner)) corner,
              // The strip under the glyphs that the pill does not cover.
              for (final strip in [
                art.bottomLeft + const Offset(2, 2),
                art.bottomRight + const Offset(-2, 2),
              ])
                if (bodyBox.contains(strip) && !covered(strip)) strip,
              // Between the reply and the art, and between two chips.
              if (panel != null && art.top - panel.bottom > 2)
                Offset(art.center.dx, (panel.bottom + art.top) / 2),
              for (var i = 1; i < reactions.length; i++)
                Offset(
                  (reactions[i - 1].right + reactions[i].left) / 2,
                  reactions[i].center.dy,
                ),
            ];

            expect(bright, isNotEmpty);
            // A plain sticker is its box: no corner is left to dim.
            if (layout != 'sticker' || decorated) expect(dimmed, isNotEmpty);
            expect(
              find.byType(ChatMessageMenuScrim),
              paints..path(color: dim, includes: dimmed, excludes: bright),
            );
          });
        }
      }
    }
  }
}
