import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/packed_path.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart' show SvgPathData;

// Byte values, as the wire packs them: below 64 a number, 64 to 127 a number
// after a minus, 128 to 191 a number after a comma; from 192 a character of
// the table (here: 'l' is 192 + 37, 'H' 192 + 7, 'V' 192 + 21, the digit d
// 244 + d, the unused 'A' 192 + 0).
const _l = 192 + 37;
const _h = 192 + 7;
const _v = 192 + 21;
int _digit(int d) => 244 + d;

void main() {
  test('expands numbers, separators and commands, opened with M and closed '
      'with z', () {
    expect(
      PackedPath.expand(const [10, 128 | 20, _l, 5, 64 | 3]),
      'M10,20l5-3z',
    );
    expect(PackedPath.expand(const [0, 128 | 0, _h, 8, _v, 8]), 'M0,0H8V8z');
  });

  test('a number past 63 continues in digit characters', () {
    expect(
      PackedPath.expand([
        1,
        _digit(9),
        _digit(6),
        128 | 2,
        _digit(0),
        _digit(0),
      ]),
      'M196,200z',
    );
  });

  test('an outline preview is the expanded path in a 512 box', () {
    expect(
      PackedPath.outlineOf(const [0, 128 | 0, _h, 8, _v, 8]),
      const ContentPreview.outline('M0,0H8V8z', ContentSize(512, 512)),
    );
  });

  test('a command the outline does not draw leaves no preview', () {
    expect(PackedPath.outlineOf(const [0, 128 | 0, 192, 8, 128 | 8]), isNull);
    expect(PackedPath.outlineOf(const []), isNull);
  });

  test('every bundled Lottie sticker carries its outline from the wire, a '
      'shape the core draws', () {
    for (final sticker in LottieStickerPack.stickers) {
      final preview = sticker.descriptor.preview;

      expect(preview, isA<ContentPreview$Outline>(), reason: sticker.name);
      final outline = preview! as ContentPreview$Outline;
      expect(outline.viewBox, const ContentSize(512, 512));
      expect(SvgPathData.parse(outline.pathData), isNotNull);
    }
  });
}
