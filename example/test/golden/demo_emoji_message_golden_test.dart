import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_emoji_message.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regenerate with
// `flutter test --update-goldens test/golden/demo_emoji_message_golden_test.dart`.
//
// The chrome around an emoji-only message: a sticker with its reply beside it
// and an enlarged-text message with its reply above, the time pill over the
// bottom trailing corner of each, left to right and right to left, for an
// incoming and an outgoing sender. The emoji are the cache's placeholders
// (nothing has been produced), and flutter_test draws text with the Ahem
// font, so nothing depends on the host platform's fonts.
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

final _sticker = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
]);
final _three = EmojiOnly([
  for (var i = 0; i < 3; i++) EmojiOnlyItem(ContentKey.document('d$i')),
]);

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
    TextDirection direction = TextDirection.ltr,
    bool outgoing = false,
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
    final host = ChatBodyHost(assets: scope, policy: policy);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view),
        child: Directionality(
          textDirection: direction,
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
                      alignment: outgoing
                          ? AlignmentDirectional.topEnd
                          : AlignmentDirectional.topStart,
                      heightFactor: 1,
                      child: DemoEmojiMessage(
                        messageId: 1,
                        emojiOnly: emojiOnly,
                        selection: selection,
                        host: host,
                        createdAt: DateTime(2026, 1, 1, 9, 5),
                        isOutgoing: outgoing,
                        header: const DemoReplyHeader(
                          sender: 'Ann',
                          text: 'see you',
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

  testWidgets('a sticker with its reply beside it', (tester) async {
    await shoot(tester, 'sticker', _sticker);
  });

  testWidgets('a sticker with its reply beside it, right to left', (
    tester,
  ) async {
    await shoot(tester, 'sticker_rtl', _sticker, direction: TextDirection.rtl);
  });

  testWidgets('an outgoing sticker with its reply beside it', (tester) async {
    await shoot(tester, 'sticker_outgoing', _sticker, outgoing: true);
  });

  testWidgets('enlarged text with its reply above it', (tester) async {
    await shoot(tester, 'text', _three);
  });

  testWidgets('enlarged text with its reply above it, right to left', (
    tester,
  ) async {
    await shoot(tester, 'text_rtl', _three, direction: TextDirection.rtl);
  });

  testWidgets('outgoing enlarged text with its reply above it', (tester) async {
    await shoot(tester, 'text_outgoing', _three, outgoing: true);
  });
}
