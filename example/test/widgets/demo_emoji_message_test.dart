/// Where the host places the chrome of an emoji-only message (research 05,
/// section 3.3): the time pill over the body's bottom trailing corner, the
/// header beside a sticker and above enlarged text, mirrored for the reading
/// direction and for the sender.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_emoji_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _sticker = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
]);
final _three = EmojiOnly([
  for (var i = 0; i < 3; i++) EmojiOnlyItem(ContentKey.document('d$i')),
]);

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
    TextDirection direction = TextDirection.ltr,
    bool outgoing = false,
    bool withHeader = true,
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
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: 340,
                child: Align(
                  alignment: outgoing
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: DemoEmojiMessage(
                    messageId: 1,
                    emojiOnly: emojiOnly,
                    selection: selection,
                    host: host,
                    createdAt: DateTime(2026, 1, 1, 9, 5),
                    isOutgoing: outgoing,
                    header: withHeader
                        ? const DemoReplyHeader(sender: 'Ann', text: 'see you')
                        : null,
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
  Rect header(WidgetTester tester) =>
      tester.getRect(find.byType(DemoReplyHeader));
  Finder pillFinder() => find
      .ancestor(
        of: find.byType(DemoMessageMeta),
        matching: find.byType(DecoratedBox),
      )
      .first;

  group('a sticker', () {
    testWidgets('has its header beside it, after it for an incoming message', (
      tester,
    ) async {
      await pump(tester, _sticker);

      expect(header(tester).left, greaterThanOrEqualTo(body(tester).right));
      expect(header(tester).top, body(tester).top);
    });

    testWidgets('has its header before it for an outgoing message', (
      tester,
    ) async {
      await pump(tester, _sticker, outgoing: true);

      expect(header(tester).right, lessThanOrEqualTo(body(tester).left));
    });

    testWidgets('mirrors in a right-to-left chat', (tester) async {
      await pump(tester, _sticker, direction: TextDirection.rtl);

      expect(header(tester).right, lessThanOrEqualTo(body(tester).left));
    });

    testWidgets('has the time pill at its bottom trailing corner, radius 12', (
      tester,
    ) async {
      await pump(tester, _sticker, withHeader: false);

      final pill = tester.getRect(pillFinder());
      expect(body(tester).right - pill.right, inInclusiveRange(0, 20));
      expect(body(tester).bottom - pill.bottom, inInclusiveRange(0, 20));
      final decoration =
          tester.widget<DecoratedBox>(pillFinder()).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(12));
      expect(decoration.color!.a, closeTo(0.6, 0.01));
    });

    testWidgets('has the pill at the leading side of a right-to-left chat', (
      tester,
    ) async {
      await pump(
        tester,
        _sticker,
        direction: TextDirection.rtl,
        withHeader: false,
      );

      final pill = tester.getRect(pillFinder());
      expect(pill.left - body(tester).left, inInclusiveRange(0, 20));
    });
  });

  group('enlarged text', () {
    testWidgets('has its header above it', (tester) async {
      await pump(tester, _three);

      expect(header(tester).bottom, lessThanOrEqualTo(body(tester).top));
      expect(header(tester).left, body(tester).left);
    });

    testWidgets('has an outgoing header on the end edge', (tester) async {
      await pump(tester, _three, outgoing: true);

      expect(header(tester).right, closeTo(340, 0.5));
    });

    testWidgets('has the time pill at its bottom trailing corner, radius 4', (
      tester,
    ) async {
      await pump(tester, _three, withHeader: false);

      final pill = tester.getRect(pillFinder());
      expect(body(tester).right - pill.right, inInclusiveRange(0, 12));
      expect(body(tester).bottom - pill.bottom, inInclusiveRange(0, 12));
      final decoration =
          tester.widget<DecoratedBox>(pillFinder()).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(4));
    });

    testWidgets('wraps narrower under a header', (tester) async {
      final many = EmojiOnly([
        for (var i = 0; i < 12; i++) EmojiOnlyItem(ContentKey.document('d$i')),
      ]);
      await pump(tester, many, withHeader: false);
      final free = body(tester).width;

      await pump(tester, many);

      expect(body(tester).width, lessThan(free));
      expect(body(tester).width, lessThanOrEqualTo(340 * 0.65 + 0.5));
    });
  });
}
