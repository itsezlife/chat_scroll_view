/// A spoiler survives the whole trip: composer, send, message, text
/// selection, copy, paste (ADR 037, ADR 032).
///
/// **Seam:** the real host path, a [ChatScrollView] over the example's data
/// source and copy writer, with a real mouse drag, observed through what the
/// next composer holds after it pastes.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_clipboard/rich_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `a ` is 0..2, the spoiler `secret` 2..8, ` b` 8..10.
  final typed = RichText('a secret b', const [
    Entity(2, 6, EntityKind.spoiler),
  ]);

  testWidgets(
    'a spoiler typed, sent, selected and copied pastes as a spoiler',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final clipboard = FakeRichClipboard();

        // The sender's composer holds a spoiler; sending encodes it.
        final sender = ComposerController(clipboard: clipboard);
        addTearDown(sender.dispose);
        sender.text.insert(typed);
        final body = ChatBodyMarkdown.send(sender.sendableText);
        expect(body, 'a ||secret|| b');

        // The message is the body; its text is selected with a mouse.
        final source = GeneratedChatDataSource(messageCount: 0);
        addTearDown(source.dispose);
        final message = source.sendMessage(sender: 'Alice', content: body);
        final controller = ChatScrollController()..jumpTo(message.id);
        addTearDown(controller.dispose);
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
          copyWriter: (copy) => clipboard.write(ChatCopy.of(copy)),
        );
        addTearDown(selection.dispose);
        selection.putBody(
          message.id,
          Markdown.fromString(ChatBodyMarkdown.received(message.content)),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: source,
                  controller: controller,
                  selectionController: selection,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: ChatMarkdownBody(
                          controller: selection,
                          messageId: id,
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = selection.surfaceFor(message.id)!;
        Offset pointOn(int from, int to) =>
            (surface as RenderBox).localToGlobal(
              surface.localBoxesForRange(0, from, to).first.center,
            );
        // From the left edge of the first character, so the range starts at 0.
        final start = pointOn(0, 1) - const Offset(5, 0);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: start);
        await tester.pump();
        await mouse.down(start);
        // Past the end of the line: the selection runs to the end of the text.
        await mouse.moveTo(pointOn(9, 10) + const Offset(40, 0));
        await tester.pump();
        await mouse.up();
        await tester.pumpAndSettle();
        expect(selection.spoilers.isRevealed(message.id), isFalse);

        // The copy carries the spoiler, over the same plain text.
        expect(await selection.copyTextSelection(), isTrue);
        final copied = (await clipboard.read())!.rich!;
        expect(copied, typed);

        // Through the wire forms the system clipboard writes, it is the same.
        expect(RichTextHtml.decode(RichTextHtml.encode(copied)), copied);
        expect(
          RichTextMarkdown.decode(RichTextMarkdown.encode(copied)),
          copied,
        );

        // Pasted into a composer, it is a spoiler there and is sent as one.
        final receiver = ComposerController(clipboard: clipboard);
        addTearDown(receiver.dispose);
        expect(await receiver.paste(), isTrue);
        expect(receiver.richText, copied);
        expect(
          receiver.sendableText.entities.where(
            (e) => e.kind == EntityKind.spoiler,
          ),
          hasLength(1),
        );
        expect(
          ChatBodyMarkdown.send(receiver.sendableText),
          contains('||secret||'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
