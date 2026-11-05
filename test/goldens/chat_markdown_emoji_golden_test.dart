import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_md/flutter_md.dart'
    show MarkdownTheme, MarkdownThemeData;
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

// Unicode emoji in an ordinary bubble, the two messages of the report (five
// emoji, and eleven emoji and a word) and the same five with two custom
// emoji among them, drawn the way the app draws them: SF for the letters and
// Apple Color Emoji for the pictures, at 15 px over a 1.35 line, at two
// pixels per logical pixel.
//
// Unlike the other goldens, these need the platform's own fonts (Ahem draws
// every emoji as a square, which is exactly what could not show the bug), so
// their baselines are an Apple Silicon Mac's, not the runner's: compared and
// regenerated there (`flutter test --update-goldens` on that Mac), and skipped
// where the two font files are missing. The emoji pictures change between
// macOS releases, hence the larger tolerance; a release that still differs
// is regenerated, not worked around.

const _emojiFile = '/System/Library/Fonts/Apple Color Emoji.ttc';
const _textFile = '/System/Library/Fonts/SFNS.ttf';

/// A custom emoji: a solid square of the text colour, at the 1.2 x font height
/// a real one has, so its size beside the unicode glyphs can be read off.
final class _SquareEmbed implements InlineEmbed {
  _SquareEmbed(this.sizeHint);

  final _listeners = ChangeNotifier();

  @override
  final Size sizeHint;

  @override
  bool visible = true;

  @override
  void addListener(VoidCallback listener) => _listeners.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _listeners.removeListener(listener);

  @override
  void paint(Canvas canvas, Rect rect, InlineEmbedPaintContext context) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(4)),
        Paint()..color = const Color(0xFF64B5F6),
      );

  @override
  void dispose() => _listeners.dispose();
}

final class _SquareEmbedResolver implements InlineEmbedResolver {
  @override
  InlineEmbed? resolve(InlineEmbedTarget target, InlineEmbedMetrics metrics) =>
      _SquareEmbed(Size.square(1.2 * (metrics.ascent + metrics.descent)));
}

const _cases = <String, String>{
  // The incoming five of the report, as unicode.
  'five': '\u{1F600}\u{1F602}\u{1F60D}\u{1F929}\u{1F970}',
  // The eleven and a word.
  'eleven_and_text':
      '\u{1F600}\u{1F602}\u{1F60D}\u{1F929}\u{1F970}\u{1F973}\u{1F60E}'
      '\u{1F913}\u{1F914}\u{1F644}\u{1F631} ауцаа',
  // Unicode and custom side by side, the report's first message.
  'with_custom':
      '\u{1F600}![x](fake:1)\u{1F60D} ![x](fake:2)\u{1F970} and a flag '
      '\u{1F1FA}\u{1F1F8}',
};

void main() {
  useGoldenBaselines(
    'test/goldens/chat_markdown_emoji_golden_test.dart',
    tolerance: 0.03,
    baselineHost: 'macos_arm64',
  );
  TestWidgetsFlutterBinding.ensureInitialized();

  final hasFonts =
      File(_emojiFile).existsSync() && File(_textFile).existsSync();

  setUpAll(() async {
    if (!hasFonts) return;
    for (final (family, file) in const [
      ('RealEmoji', _emojiFile),
      ('RealText', _textFile),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
          ))
          .load();
    }
  });

  for (final MapEntry(:key, :value) in _cases.entries) {
    testWidgets('a bubble with $key', (tester) async {
      if (!hasFonts) return;
      tester.view
        ..physicalSize = const Size(640, 160)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final selection = ChatSelectionController();
      addTearDown(selection.dispose);
      selection.putBody(1, Markdown.fromString(value));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MarkdownTheme(
              data: MarkdownThemeData(
                textStyle: const TextStyle(
                  fontFamily: 'RealText',
                  fontFamilyFallback: ['RealEmoji'],
                  fontSize: 15,
                  height: 1.35,
                  color: Color(0xFFFFFFFF),
                ),
              ),
              child: RepaintBoundary(
                key: const ValueKey('shot'),
                child: ColoredBox(
                  color: const Color(0xFF181818),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: ChatMarkdownBody(
                            controller: selection,
                            messageId: 1,
                            embedResolver: _SquareEmbedResolver(),
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
        matchesGoldenFile('chat_markdown_emoji/$key.png'),
      );
    });
  }
}
