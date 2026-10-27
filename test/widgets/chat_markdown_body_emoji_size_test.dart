/// Unicode emoji inside a markdown body: how big the glyph is drawn next to
/// the text around it.
///
/// **Seam:** [ChatMarkdownBody] in a [ChatScrollView], measured through the
/// selection surface's glyph boxes, with the platform's real colour emoji font
/// loaded: Ahem draws every glyph as a square of the font size, so the test
/// font cannot tell an emoji that is the right size from one that is not.
///
/// **Why it exists.** A desktop bubble showed regular emoji "weirdly small".
/// A glyph set as text is drawn at the font size (a 15 px text gets a 15 px
/// emoji), while the client the body follows draws an emoji at the font's
/// height, ascent plus descent, and a custom emoji (an embed) at 1.2 times
/// that. Next to a custom emoji the unicode one was 40 % smaller. The
/// expected extents below are the font's own metrics read from a probe of the
/// text font alone, not the body's output.
///
/// Needs the macOS font files; elsewhere the test is skipped.
library;

import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart' show InlineEmbedResolver;
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_md/flutter_md.dart' show MarkdownThemeData;
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

const _emojiFile = '/System/Library/Fonts/Apple Color Emoji.ttc';
const _textFile = '/System/Library/Fonts/SFNS.ttf';
const _fontSize = 15.0;
const _lineHeight = 1.35;

class _LoadedSource extends ChatDataSource {
  _LoadedSource() {
    upsertMessages([
      UserChatMessage(id: 1, sender: 'User', createdAt: DateTime(2026), updatedAt: DateTime(2026), content: 'x'),
    ]);
    seedBoundaries(oldestKnownId: 1, newestKnownId: 1, reachedOldest: true, reachedNewest: true);
  }

  @override
  Future<List<IChatMessage>> fetchRange({required int fromId, required int toId}) async => const <IChatMessage>[];
}

Future<void> _loadFont(String family, String file) async {
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
  await loader.load();
}

const _style = TextStyle(
  fontFamily: 'RealText',
  fontFamilyFallback: ['RealEmoji'],
  fontSize: _fontSize,
  height: _lineHeight,
  color: Color(0xFF000000),
);

/// The font's height at [_fontSize]: what the reference client sizes an emoji
/// to. Read from a probe of the text font alone.
double _fontHeight() {
  final probe = TextPainter(
    text: const TextSpan(
      text: 'x',
      style: TextStyle(fontFamily: 'RealText', fontSize: _fontSize),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final line = probe.computeLineMetrics().single;
  probe.dispose();
  return line.ascent + line.descent;
}

/// What a line of `ab <emoji> cd` was tall before the emoji were enlarged: the
/// emoji at the font size. The emoji font splits the line with a deeper
/// descent than the text's, so this is a pixel taller than a line of text
/// alone, and the enlarged emoji must not add to it.
double _lineHeightWithEmojiAtFontSize(String emoji) {
  final probe = TextPainter(
    text: TextSpan(text: 'ab $emoji cd', style: _style),
    textDirection: TextDirection.ltr,
  )..layout();
  final height = probe.height;
  probe.dispose();
  return height;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hasFonts = File(_emojiFile).existsSync() && File(_textFile).existsSync();

  late _LoadedSource dataSource;
  late ChatScrollController controller;

  setUpAll(() async {
    if (!hasFonts) return;
    await _loadFont('RealEmoji', _emojiFile);
    await _loadFont('RealText', _textFile);
  });
  setUp(() {
    dataSource = _LoadedSource();
    controller = ChatScrollController();
  });
  tearDown(() {
    controller.dispose();
    dataSource.dispose();
  });

  /// Pumps [source] in a body at [pixelRatio] and returns the surface.
  Future<ChatSelectionController> pump(
    WidgetTester tester,
    String source, {
    double pixelRatio = 1,
    MarkdownThemeData? theme,
    InlineEmbedResolver? embedResolver,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 300) * pixelRatio
      ..devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final selection = ChatSelectionController(policy: const ChatSelectionPolicy.mobile());
    addTearDown(selection.dispose);
    selection.putBody(1, Markdown.fromString(source));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScrollView(
            dataSource: dataSource,
            controller: controller,
            selectionController: selection,
            messageBuilder: (context, id, message, status, runLayout) => ChatMarkdownBody(
              key: ValueKey('md-$id'),
              controller: selection,
              messageId: id,
              theme: theme ?? MarkdownThemeData(textStyle: _style),
              embedResolver: embedResolver,
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

  for (final pixelRatio in [1.0, 2.0]) {
    group('at ${pixelRatio}x', () {
      // The emoji sit between two letters: `a<emoji>b`. The range is the
      // emoji's own code units.
      for (final emoji in [
        '\u{1F600}', // a plain emoji: two code units
        '\u{1F44D}\u{1F3FD}', // a skin tone
        '\u{1F468}‍\u{1F469}‍\u{1F467}', // a ZWJ family
        '\u{1F1FA}\u{1F1F8}', // a flag
        '1️⃣', // a keycap
        '❤️', // a basic-plane emoji with a presentation selector
      ]) {
        final label = emoji.runes.map((r) => r.toRadixString(16).toUpperCase()).join('-');
        testWidgets('$label is drawn at the font height, in the line', (tester) async {
          if (!hasFonts) return;
          final selection = await pump(tester, 'ab $emoji cd', pixelRatio: pixelRatio);

          final glyph = boxes(selection, 3, 3 + emoji.length).first;
          final extent = _fontHeight();

          expect(glyph.width, closeTo(extent, 0.5), reason: 'glyph width');
          // The line is no taller than it was with the emoji at the font size.
          expect(
            tester.getSize(find.byKey(const ValueKey('md-1'))).height,
            closeTo(_lineHeightWithEmojiAtFontSize(emoji), 0.5),
            reason: 'line height',
          );
        });
      }
    });
  }

  group('what stays at the font size', () {
    for (final (name, text) in const [
      ('a heart with no presentation selector', '\u2764'),
      ('a copyright sign', '\u00A9'),
      ('a digit', '1'),
    ]) {
      testWidgets(name, (tester) async {
        if (!hasFonts) return;
        final selection = await pump(tester, 'ab $text cd');

        // A text glyph, or the emoji font's at the font size when the text
        // font has none: never the enlarged square.
        final glyph = boxes(selection, 3, 3 + text.length).first;
        expect(glyph.width, lessThanOrEqualTo(_fontSize + 0.01));
      });
    }

    testWidgets('a theme that sets its own scanner is left alone', (tester) async {
      if (!hasFonts) return;
      final selection = await pump(
        tester,
        'ab \u{1F600} cd',
        theme: MarkdownThemeData(textStyle: _style, emojiRuns: (_) => const <TextRange>[]),
      );

      expect(boxes(selection, 3, 5).first.width, closeTo(_fontSize, 0.01));
    });
  });

  testWidgets('a unicode emoji is a custom emoji\'s box over 1.2', (tester) async {
    if (!hasFonts) return;
    final resolver = FakeInlineEmbedResolver();
    final selection = await pump(tester, 'ab \u{1F600} ![x](fake:1) cd', embedResolver: resolver);

    final custom = resolver.made.single.sizeHint.width;
    expect(boxes(selection, 3, 5).first.width, closeTo(custom / 1.2, 0.01));
  });

  test('the text font is taller than its size (the premise of the rule)', () {
    if (!hasFonts) return;
    // SF reaches 1.18 em; an emoji at the font size is smaller than
    // the letters' own line.
    expect(_fontHeight() / _fontSize, greaterThan(1.1));
  });
}
