import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regenerate with `flutter test --update-goldens test/goldens`.
//
// The emoji-only body at 1, 2, 3, 5 and 10 items, all custom and mixed (the
// first item a unicode glyph), the sticker layout, and the right-to-left
// variants of 3 and 10. A custom emoji paints a solid square of its own colour
// in its box, so the order and the box can be read off; a unicode glyph is
// text, which flutter_test draws with the Ahem font, a square of the font
// size, so nothing depends on the host platform's fonts. The sizes themselves
// are asserted in test/emoji/; these pictures show the arrangement.
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

const _palette = <Color>[
  Color(0xFFE53935),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFFFB8C00),
  Color(0xFF8E24AA),
  Color(0xFF00ACC1),
  Color(0xFFFDD835),
  Color(0xFF6D4C41),
  Color(0xFF546E7A),
  Color(0xFFD81B60),
];

/// An embed that paints a rounded square of one colour into its rectangle.
final class _ColorEmbed implements InlineEmbed {
  _ColorEmbed(this.color, this.sizeHint);

  final Color color;

  // Only to hold listeners: this embed never changes.
  final _signal = FakeInlineEmbed();

  @override
  final Size sizeHint;

  @override
  bool visible = true;

  @override
  void addListener(VoidCallback listener) => _signal.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _signal.removeListener(listener);

  @override
  void paint(ui.Canvas canvas, Rect rect, InlineEmbedPaintContext context) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(6)),
        Paint()..color = color,
      );

  @override
  void dispose() => _signal.dispose();
}

EmojiOnly _items(int count, {required bool allCustom}) => EmojiOnly([
  for (var i = 0; i < count; i++)
    EmojiOnlyItem(
      !allCustom && i == 0
          ? const ContentKey.unicode('\u{1F44D}')
          : ContentKey.document('d$i'),
    ),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Goldens sit next to this file, also when test/unit_test.dart runs it.
  late GoldenFileComparator previous;
  setUpAll(() {
    previous = goldenFileComparator;
    goldenFileComparator = _GoldenComparator(
      Uri.file('test/goldens/chat_emoji_body_golden_test.dart'),
    );
  });
  tearDownAll(() => goldenFileComparator = previous);

  Future<void> shoot(
    WidgetTester tester,
    String name,
    EmojiOnly emojiOnly, {
    ContentKey? sticker,
    TextDirection direction = TextDirection.ltr,
    Size view = const Size(360, 640),
    double width = 320,
  }) async {
    tester.view
      ..physicalSize = view
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selection = ChatSelectionController();
    addTearDown(selection.dispose);
    var made = 0;

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view),
        child: Directionality(
          textDirection: direction,
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFF263238)),
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: const ValueKey('shot'),
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: width,
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        heightFactor: 1,
                        child: ChatEmojiBody(
                          controller: selection,
                          messageId: 1,
                          emojiOnly: emojiOnly,
                          sticker: sticker,
                          embedFactory: (content, preset) => _ColorEmbed(
                            _palette[made++ % _palette.length],
                            preset.size,
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
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const ValueKey('shot')),
      matchesGoldenFile('chat_emoji_body/$name.png'),
    );
  }

  for (final count in [1, 2, 3, 5, 10]) {
    for (final allCustom in [true, false]) {
      final kind = allCustom ? 'custom' : 'mixed';
      testWidgets('$count items, $kind', (tester) async {
        await shoot(
          tester,
          '${kind}_$count',
          _items(count, allCustom: allCustom),
        );
      });
    }
  }

  for (final count in [3, 10]) {
    for (final allCustom in [true, false]) {
      final kind = allCustom ? 'custom' : 'mixed';
      testWidgets('$count items, $kind, right to left', (tester) async {
        await shoot(
          tester,
          '${kind}_${count}_rtl',
          _items(count, allCustom: allCustom),
          direction: TextDirection.rtl,
        );
      });
    }
  }

  testWidgets('the sticker layout', (tester) async {
    await shoot(
      tester,
      'sticker',
      EmojiOnly(const [EmojiOnlyItem(ContentKey.unicode('\u{1F44D}'))]),
      sticker: const ContentKey.document('pack'),
    );
  });

  testWidgets('the sticker layout, right to left', (tester) async {
    await shoot(
      tester,
      'sticker_rtl',
      EmojiOnly(const [EmojiOnlyItem(ContentKey.unicode('\u{1F44D}'))]),
      sticker: const ContentKey.document('pack'),
      direction: TextDirection.rtl,
    );
  });
}
