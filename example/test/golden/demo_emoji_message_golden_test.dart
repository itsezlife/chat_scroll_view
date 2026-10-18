import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_emoji_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_header_panel.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_reactions_row.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regenerate with
// `flutter test --update-goldens test/golden/demo_emoji_message_golden_test.dart`.
//
// The chrome around an emoji-only message, per platform family (Android, iOS,
// desktop): the text layout of 1, 3 and 10 emoji and the sticker layout, for
// an incoming and an outgoing sender in a left-to-right and a right-to-left
// chat, plain and with a reply and reactions. The emoji are unicode glyphs,
// which flutter_test draws with the Ahem font (a solid square of the font size),
// so the layout reads off the picture and nothing depends on the host
// platform's fonts. An incoming desktop message shows its time only under the
// pointer, so those pictures are taken with the pointer on it.
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

const _glyphs = <String>[
  '\u{1F44D}',
  '\u{1F680}',
  '\u{1F525}',
  '\u{1F600}',
  '\u{1F389}',
  '\u{2728}',
  '\u{1F60D}',
  '\u{1F64F}',
  '\u{1F60E}',
  '\u{1F914}',
];

EmojiOnly _glyphRun(int count) => EmojiOnly([
  for (var i = 0; i < count; i++) EmojiOnlyItem(ContentKey.unicode(_glyphs[i])),
]);

const _platforms = <String, ChatEmojiPolicy>{
  'android': ChatEmojiPolicy.android(),
  'ios': ChatEmojiPolicy.ios(),
  'desktop': ChatEmojiPolicy.desktop(),
};

const _reply = EmojiHeaderData.reply(sender: 'Ann', text: 'see you soon');
const _reactions = [
  EmojiReaction('\u{1F44D}', 3, chosen: true),
  EmojiReaction('\u{2764}', 1),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Goldens sit next to this file, also when test/unit_test.dart runs it.
  late GoldenFileComparator previous;
  setUpAll(() {
    previous = goldenFileComparator;
    goldenFileComparator = _GoldenComparator(
      Uri.file('test/golden/demo_emoji_message_golden_test.dart'),
    );
  });
  tearDownAll(() => goldenFileComparator = previous);

  Future<void> shoot(
    WidgetTester tester,
    String name,
    EmojiOnly emojiOnly, {
    required ChatEmojiPolicy platform,
    ContentKey? stickerOf,
    TextDirection direction = TextDirection.ltr,
    bool outgoing = false,
    bool decorated = false,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scope = AssetCacheScope(producer: FakeAssetProducer());
    addTearDown(scope.dispose);
    final policy = ValueNotifier(const LargeEmojiPolicy(enabled: true));
    addTearDown(policy.dispose);
    final selection = ChatSelectionController();
    addTearDown(selection.dispose);
    final host = ChatBodyHost(
      assets: scope,
      policy: policy,
      stickerFor: (key) => stickerOf,
    );
    final mirrors = platform.mirrorsInRtl;

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view),
        child: Directionality(
          textDirection: direction,
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFFE0E0E0)),
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: const ValueKey('shot'),
                child: ColoredBox(
                  color: const Color(0xFF121215),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: 300,
                      child: Align(
                        alignment: mirrors
                            ? (outgoing
                                  ? AlignmentDirectional.topEnd
                                  : AlignmentDirectional.topStart)
                            : (outgoing
                                  ? Alignment.topRight
                                  : Alignment.topLeft),
                        heightFactor: 1,
                        child: DemoEmojiMessage(
                          messageId: 1,
                          emojiOnly: emojiOnly,
                          selection: selection,
                          host: host,
                          createdAt: DateTime(2026, 1, 1, 9, 5),
                          isOutgoing: outgoing,
                          policy: platform,
                          // Desktop shows an incoming time while the pointer
                          // is on the row.
                          hovered:
                              platform is ChatEmojiPolicy$Desktop && !outgoing,
                          header: decorated ? _reply : null,
                          reactions: decorated ? _reactions : const [],
                        ),
                      ),
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

    await expectLater(
      find.byKey(const ValueKey('shot')),
      matchesGoldenFile('goldens/emoji_message/$name.png'),
    );
  }

  // (name, emoji, sticker document)
  final layouts = <(String, EmojiOnly, ContentKey?)>[
    ('text1', _glyphRun(1), null),
    ('text3', _glyphRun(3), null),
    ('text10', _glyphRun(10), null),
    ('sticker', _glyphRun(1), const ContentKey.document('pack')),
  ];
  final sides = <(String, TextDirection, bool)>[
    ('in_ltr', TextDirection.ltr, false),
    ('out_ltr', TextDirection.ltr, true),
    ('in_rtl', TextDirection.rtl, false),
    ('out_rtl', TextDirection.rtl, true),
  ];

  for (final MapEntry(key: family, value: platform) in _platforms.entries) {
    for (final (layout, emoji, sticker) in layouts) {
      for (final (side, direction, outgoing) in sides) {
        testWidgets('$family $layout $side', (tester) async {
          await shoot(
            tester,
            '$family/${layout}_$side',
            emoji,
            platform: platform,
            stickerOf: sticker,
            direction: direction,
            outgoing: outgoing,
          );
        });

        // With a reply and reactions, for the layouts the header and the
        // reactions place differently.
        if (layout == 'text3' || layout == 'sticker') {
          testWidgets('$family $layout $side with a reply and reactions', (
            tester,
          ) async {
            await shoot(
              tester,
              '$family/${layout}_${side}_decorated',
              emoji,
              platform: platform,
              stickerOf: sticker,
              direction: direction,
              outgoing: outgoing,
              decorated: true,
            );
          });
        }
      }
    }
  }
}
