import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/document_embed.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_assets/content_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/testing.dart';

void main() {
  late ContentAssetScope scope;
  late ValueNotifier<LargeEmojiPolicy> policy;

  setUp(() {
    scope = ContentAssetScope.withMedia(producer: FakeAssetProducer());
    policy = ValueNotifier(const LargeEmojiPolicy(enabled: true));
  });
  tearDown(() {
    policy.dispose();
    scope.dispose();
  });

  Future<void> pump(WidgetTester tester, String body) async {
    final message = UserChatMessage.preParsed(
      id: 7,
      sender: 'alice',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      body: Markdown.fromString(body),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: DemoMessageBubble(
                message: message,
                selection: ChatSelectionController(),
                host: ChatBodyHost(assets: scope, policy: policy),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a document message lays its row out as a block: the bubble '
      'holds the whole row, under the sender', (tester) async {
    for (final (body, height) in [
      // An SVG with previews: the thumbnail row.
      (
        '![diagram.svg](file:diagram)',
        const DocumentRowStyle().thumbnailExtent,
      ),
      // Any other document: the icon row.
      ('![notes.txt](file:notes)', const DocumentRowStyle().iconRowHeight),
    ]) {
      await pump(tester, body);

      // The bubble's change transition builds the body for its morph too.
      final row = find.byType(DocumentRowView).first;
      expect(find.byType(DocumentRowView), findsWidgets, reason: body);
      final box = tester.getRect(row);
      expect(box.height, height, reason: body);
      expect(
        tester.getRect(find.text('alice')).bottom,
        lessThanOrEqualTo(box.top),
        reason: body,
      );
      final bubble = tester.getRect(find.byType(DemoMessageBubble));
      expect(bubble.top, lessThanOrEqualTo(box.top));
      expect(bubble.bottom, greaterThanOrEqualTo(box.bottom));
    }
  });

  testWidgets('a document among other text stays inline in the text', (
    tester,
  ) async {
    await pump(tester, 'see ![notes.txt](file:notes) here');

    expect(find.byType(DocumentRowView), findsNothing);
  });
}
