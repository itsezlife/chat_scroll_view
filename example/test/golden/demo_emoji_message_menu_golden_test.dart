import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/emoji_menu_rig.dart';

// Regenerate with
// `flutter test --update-goldens test/golden/demo_emoji_message_menu_golden_test.dart`.
//
// The message menu (mobile sheet) open on an emoji-only message, per platform
// family (Android, iOS): the text layout of three emoji and the sticker
// layout, incoming and outgoing, in a left-to-right and a right-to-left chat,
// plain and with a reply and reactions. The dim is black at 0.2 and only what
// the message paints stays bright: the glyphs or the art, the pill, the reply
// panel and each reaction chip, in their own shapes, with no bubble around
// them. The emoji are unicode glyphs, which flutter_test draws with the Ahem
// font (a solid square of the font size), so the picture reads without the
// host platform's fonts.
//
// The goldens were generated on macOS. The comparator forgives antialiasing
// noise (a fraction of a percent of the pixels) so the same files can hold on
// another platform; if CI on Linux still differs, regenerate there and record
// it here.
class _GoldenComparator extends LocalFileComparator {
  _GoldenComparator(super.testFile);

  static const double _tolerance = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

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

  // Goldens sit next to this file, also when test/unit_test.dart runs it.
  late GoldenFileComparator previous;
  setUpAll(() {
    previous = goldenFileComparator;
    goldenFileComparator = _GoldenComparator(
      Uri.file('test/golden/demo_emoji_message_menu_golden_test.dart'),
    );
  });
  tearDownAll(() => goldenFileComparator = previous);

  // No reaction strip, three rows and the finger just under the message: the
  // card and the strip are placed at the finger (and a tall card is moved up
  // by the presenter), and here they would cover the message the picture is
  // about.
  late EmojiMenuRig rig;
  setUp(
    () => rig = EmojiMenuRig(
      reactions: const <String>[],
      excludeActionIds: const <String>[
        MessageMenuActionId.forward,
        MessageMenuActionId.pin,
        MessageMenuActionId.edit,
      ],
    ),
  );
  tearDown(() => rig.dispose());

  const platforms = <String, ChatEmojiPolicy>{
    'android': ChatEmojiPolicy.android(),
    'ios': ChatEmojiPolicy.ios(),
  };
  // (name, emoji, direction, outgoing, decorated)
  final cases = <(String, EmojiOnly, TextDirection, bool, bool)>[
    ('text_in_ltr', _text, TextDirection.ltr, false, false),
    ('text_out_ltr_decorated', _text, TextDirection.ltr, true, true),
    ('text_in_rtl_decorated', _text, TextDirection.rtl, false, true),
    ('sticker_out_ltr', _sticker, TextDirection.ltr, true, false),
    ('sticker_in_ltr_decorated', _sticker, TextDirection.ltr, false, true),
    ('sticker_out_rtl_decorated', _sticker, TextDirection.rtl, true, true),
  ];

  for (final MapEntry(key: family, value: platform) in platforms.entries) {
    for (final (name, emoji, direction, outgoing, decorated) in cases) {
      testWidgets('$family $name', (tester) async {
        await rig.show(
          tester,
          emoji,
          platform: platform,
          direction: direction,
          outgoing: outgoing,
          decorated: decorated,
          // A mid tone, so the dim reads against it.
          background: const Color(0xFF5B7083),
        );
        final surface = rig.selection.messageSurfaceGlobal(1)!.rect;
        await rig.open(tester, tap: surface.bottomCenter + const Offset(0, 2));

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/emoji_message_menu/${family}_$name.png'),
        );
      });
    }
  }
}
