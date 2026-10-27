// The seeded dust below needs the engine's own test seam, which is not public.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'dart:math';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart' show MarkdownThemeData, MarkdownTheme;
import 'package:flutter_md/src/render/spoiler_particle_tile.dart';
import 'package:flutter_test/flutter_test.dart';

// Regenerate with `flutter test --update-goldens test/goldens`.
//
// One chat row holding the whole inline layer: a mention, an embed, a hashtag
// and a hidden spoiler, left-to-right and right-to-left, then the same rows
// with the spoiler revealed. The embed paints a solid square in the text colour
// so its place in the line can be read off; the dust over the spoiler is
// seeded, so the pictures are the same on every run. flutter_test renders text
// with the Ahem font, so nothing depends on the host platform's fonts.
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
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= _tolerance) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

/// An embed that paints a solid square in the colour of the text around it.
final class _SquareEmbed implements InlineEmbed {
  _SquareEmbed(this.sizeHint);

  // Only to hold listeners: this embed never changes.
  final _signal = FakeInlineEmbed();

  @override
  final Size sizeHint;

  @override
  bool visible = true;

  @override
  void addListener(void Function() listener) => _signal.addListener(listener);

  @override
  void removeListener(void Function() listener) => _signal.removeListener(listener);

  @override
  void paint(Canvas canvas, Rect rect, InlineEmbedPaintContext context) =>
      canvas.drawRect(rect.deflate(1), Paint()..color = context.tint ?? const Color(0xFF000000));

  @override
  void dispose() => _signal.dispose();
}

final class _SquareEmbedResolver implements InlineEmbedResolver {
  @override
  InlineEmbed? resolve(InlineEmbedTarget target, InlineEmbedMetrics metrics) =>
      target.scheme == 'fake' ? _SquareEmbed(Size.square(1.2 * (metrics.ascent + metrics.descent))) : null;
}

const _source =
    'Hi [@Ann](mention:42) ![:w:](fake:1) [#tag](hashtag:tag) '
    '||a secret that wraps||';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Goldens sit next to this file, also when test/unit_test.dart runs it.
  late GoldenFileComparator previous;
  setUpAll(() {
    previous = goldenFileComparator;
    goldenFileComparator = _GoldenComparator(Uri.file('test/goldens/inline_layer_golden_test.dart'));
  });
  tearDownAll(() => goldenFileComparator = previous);

  setUp(() => SpoilerParticleTiles.debugConfigure(random: () => Random(7)));
  tearDown(SpoilerParticleTiles.debugReset);

  for (final revealed in [false, true]) {
    for (final direction in TextDirection.values) {
      final name = '${revealed ? 'revealed' : 'hidden'}_${direction.name}';

      testWidgets('a chat row, spoiler ${revealed ? 'revealed' : 'hidden'} '
          '(${direction.name})', (tester) async {
        tester.view
          ..physicalSize = const Size(260, 110)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final selection = ChatSelectionController(policy: const ChatSelectionPolicy.mobile());
        addTearDown(selection.dispose);
        selection.putBody(1, Markdown.fromString(_source));
        if (revealed) selection.spoilers.reveal(1);
        const ink = Color(0xFF0D47A1);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(),
            child: Directionality(
              textDirection: direction,
              child: MarkdownTheme(
                data: MarkdownThemeData(
                  textStyle: const TextStyle(fontSize: 14, color: ink),
                  textDirection: direction,
                  linkColor: const Color(0xFF1565C0),
                  mentionColor: const Color(0xFF2E7D32),
                ),
                child: RepaintBoundary(
                  key: const ValueKey('shot'),
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
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
        );
        await tester.pump();

        await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('inline_layer/$name.png'));
      });
    }
  }
}
