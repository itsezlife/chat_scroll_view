/// The variant picker with a real colour emoji font: no picture is cropped.
///
/// **Seam:** [EmojiVariantPicker] rendered to pixels with the platform's
/// emoji font loaded, and the ink of every option measured against the cell
/// it sits in.
///
/// **Why it exists.** The reported "emoji overflow in the skin-tone
/// containers" does not show with the test font (Ahem draws a square) nor in
/// layout metrics: Apple Color Emoji lays a glyph out in its em box but draws
/// bitmaps that spill several pixels past it, and the first picker clipped
/// each option to a 32 px rounded container, cropping a hand, a couple or a
/// runner at the edge (4 of the 6 options below touched the clip). The cell
/// of the picker is now the grid's, larger than the glyph box, and nothing
/// clips, so ink must stay clear of the cell's edges.
///
/// Needs the macOS font file; elsewhere the test is skipped (the layout tests
/// still pin the metrics).
library;

import 'dart:io';

import 'package:content_model/content_model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/testing.dart';

const _fontFile = '/System/Library/Fonts/Apple Color Emoji.ttc';
const _scale = 4.0;

void main() {
  testWidgets(
    'no option\'s ink reaches the edge of its cell',
    (tester) async {
      final bytes = File(_fontFile).readAsBytesSync();
      final loader = FontLoader('RealEmoji')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      await tester.binding.setSurfaceSize(const Size(500, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const cell = Size(43.75, 45);
      final options = [
        for (final glyph in [
          '🙋🏽',
          '🧑🏽‍🤝‍🧑🏿',
          '👨🏽‍👩🏽‍👧🏽‍👦🏽',
          '🏃🏽‍♀️',
          '🫶🏽',
          '💑🏽',
        ])
          ContentKey.unicode(glyph) as ContentKey$Unicode,
      ];
      await tester.pumpWidget(
        PanelShellTestScope(
          size: const Size(500, 200),
          child: RepaintBoundary(
            key: const ValueKey('scene'),
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: DefaultTextStyle(
                style: const TextStyle(fontFamily: 'RealEmoji'),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: EmojiVariantPicker(options: options, cell: cell),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final data = (await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('scene')),
            )
            .toImage(pixelRatio: _scale);
        return (image, await image.toByteData());
      }))!;
      final (image, pixels) = data;
      final layout = EmojiVariantPickerLayout(
        count: options.length,
        cell: cell,
      );

      bool isInk(int x, int y) {
        int channel(int c) => pixels!.getUint8((y * image.width + x) * 4 + c);
        final (r, g, b) = (channel(0), channel(1), channel(2));
        // The card is 0xE8EAED; anything clearly different is a picture.
        return (r - 0xE8).abs() > 12 ||
            (g - 0xEA).abs() > 12 ||
            (b - 0xED).abs() > 12;
      }

      for (var i = 0; i < options.length; i++) {
        final rect = layout
            .optionRect(i)
            .shift(
              const Offset(
                EmojiVariantPickerLayout.shadowMargin,
                EmojiVariantPickerLayout.shadowMargin,
              ),
            );
        // Ink on the outermost pixels of the cell would be a crop.
        const margin = 2 * _scale;
        var touches = false;
        for (
          var y = (rect.top * _scale).ceil();
          y < rect.bottom * _scale;
          y++
        ) {
          for (
            var x = (rect.left * _scale).ceil();
            x < rect.right * _scale;
            x++
          ) {
            final nearEdge =
                x - rect.left * _scale < margin ||
                rect.right * _scale - x < margin ||
                y - rect.top * _scale < margin ||
                rect.bottom * _scale - y < margin;
            if (nearEdge && isInk(x, y)) touches = true;
          }
        }
        expect(touches, isFalse, reason: 'option $i is cropped by its cell');
      }
    },
    skip: !File(_fontFile).existsSync(),
  );
}
