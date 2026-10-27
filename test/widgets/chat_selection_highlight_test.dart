/// The selection highlight of a message body: one rectangle per line, the
/// line's height, whatever the line holds.
///
/// **Seam:** [ChatMarkdownBody] in a [ChatScrollView], measured through the
/// selection surface's highlight rectangles (`localBoxesForRange`, the same
/// geometry the markdown render object draws and the tap highlight contour is
/// built from), with the body's own colour-emoji scanner and a fake inline
/// embed resolver for the custom emoji.
///
/// **Why it exists.** A selection drew a box for every run, each as tall as
/// the run: a unicode emoji (drawn at the font's height times the policy's
/// scale), a custom emoji and the text around them were three heights, and a
/// selection over a hidden spoiler drew a different patch at the emoji's
/// positions than at the text's, which showed where the emoji were. The
/// fork's `selection_highlight_test.dart` reads the pixels (including that no
/// tint is drawn over an embed); this pins what the viewport's own body hands
/// them: the scanner and the embeds come from here.
///
/// Ahem draws every glyph as a square, which is all the geometry needs.
library;

import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart'
    show MarkdownThemeData, markdownBlockRenderedText;
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

class _LoadedSource extends ChatDataSource {
  _LoadedSource() {
    upsertMessages([
      UserChatMessage(
        id: 1,
        sender: 'User',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        content: 'x',
      ),
    ]);
    seedBoundaries(
      oldestKnownId: 1,
      newestKnownId: 1,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LoadedSource dataSource;
  late ChatScrollController controller;
  late FakeInlineEmbedResolver embeds;

  setUp(() {
    dataSource = _LoadedSource();
    controller = ChatScrollController();
    embeds = FakeInlineEmbedResolver();
  });
  tearDown(() {
    controller.dispose();
    dataSource.dispose();
  });

  Future<ChatSelectionController> pump(
    WidgetTester tester,
    String source, {
    double? lineHeight,
    double width = 400,
  }) async {
    tester.view
      ..physicalSize = Size(width, 300)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.mobile(),
    );
    addTearDown(selection.dispose);
    selection.putBody(1, Markdown.fromString(source));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScrollView(
            dataSource: dataSource,
            controller: controller,
            selectionController: selection,
            messageBuilder: (context, id, message, status, runLayout) =>
                ChatMarkdownBody(
                  key: ValueKey('md-$id'),
                  controller: selection,
                  messageId: id,
                  theme: MarkdownThemeData(
                    textStyle: TextStyle(
                      fontSize: 15,
                      height: lineHeight,
                      color: const Color(0xFF000000),
                    ),
                    emojiScale: 1.2,
                  ),
                  embedResolver: embeds,
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return selection;
  }

  List<Rect> boxes(ChatSelectionController selection, int from, int to) =>
      selection.surfaceFor(1)!.localBoxesForRange(0, from, to);

  // Rendered text: letters, a unicode emoji (2 code units) and a custom emoji
  // (its alt text, `:wave:`, 6).
  const line = 'ab \u{1F600} cd ![:wave:](fake:1) ef \u{1F44D} gh';

  testWidgets('a line of text, emoji and an embed is one rectangle', (
    tester,
  ) async {
    final selection = await pump(tester, line);
    final length = markdownBlockRenderedText(
      selection.bodyOf(1)!.blocks.first,
    ).length;

    final rects = boxes(selection, 0, length);

    expect(rects, hasLength(1));
    final surface = selection.surfaceFor(1)! as RenderBox;
    expect(rects.single.top, 0);
    expect(rects.single.bottom, closeTo(surface.size.height, 1e-6));
  });

  testWidgets('every kind of content has the same top and bottom', (
    tester,
  ) async {
    final selection = await pump(tester, line, lineHeight: 1.4);
    final text = markdownBlockRenderedText(selection.bodyOf(1)!.blocks.first);
    final emoji = text.indexOf('\u{1F600}');
    final embed = text.indexOf(':wave:');

    final ofText = boxes(selection, 0, 2).single;
    final ofEmoji = boxes(selection, emoji, emoji + 2).single;
    final ofEmbed = boxes(selection, embed, embed + 6).single;

    expect(ofEmoji.top, ofText.top);
    expect(ofEmoji.bottom, ofText.bottom);
    expect(ofEmbed.top, ofText.top);
    expect(ofEmbed.bottom, ofText.bottom);
  });

  testWidgets('wrapped lines are one rectangle each, and they touch', (
    tester,
  ) async {
    final selection = await pump(
      tester,
      '$line $line $line',
      lineHeight: 1.4,
      width: 240,
    );
    final length = markdownBlockRenderedText(
      selection.bodyOf(1)!.blocks.first,
    ).length;

    final rects = boxes(selection, 0, length);

    expect(rects.length, greaterThan(1));
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top, closeTo(rects[i - 1].bottom, 1e-6));
      expect(rects[i].height, closeTo(rects.first.height, 1e-6));
    }
  });

  testWidgets('over a spoiler every position is the same rectangle', (
    tester,
  ) async {
    final selection = await pump(
      tester,
      'a ||bc \u{1F600} de ![:wave:](fake:1) fg|| h',
      lineHeight: 1.4,
    );
    final text = markdownBlockRenderedText(selection.bodyOf(1)!.blocks.first);
    final emoji = text.indexOf('\u{1F600}');
    final embed = text.indexOf(':wave:');
    final secret = text.indexOf('bc');

    final rects = [
      boxes(selection, secret, secret + 2).single, // text in the spoiler
      boxes(selection, emoji, emoji + 2).single, // the unicode emoji
      boxes(selection, embed, embed + 6).single, // the custom emoji
      boxes(selection, 0, text.length).single, // all of it
    ];

    for (final rect in rects) {
      expect(rect.top, rects.first.top);
      expect(rect.bottom, rects.first.bottom);
    }
    expect(selection.spoilers.isRevealed(1), isFalse);
  });
}
