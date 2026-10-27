import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// What a host reads to set chrome around an emoji-only body. The expected
// numbers are the platform tables written out (see chat_emoji_policy_test),
// not the output of the code under test.

const _glyph = ContentKey.unicode('\u{1F44D}');
const _pack = ContentKey.document('pack');

EmojiOnly _glyphs(int count) => EmojiOnly([for (var i = 0; i < count; i++) const EmojiOnlyItem(_glyph)]);

EmojiOnly _customs(int count) => EmojiOnly([for (var i = 0; i < count; i++) EmojiOnlyItem(ContentKey.document('d$i'))]);

const _phone = Size(360, 640);

/// A rectangle equal within float noise: `3 * 37.6` is not `112.8`.
Matcher _rect(double l, double t, double w, double h) => isA<Rect>()
    .having((r) => r.left, 'left', closeTo(l, 1e-9))
    .having((r) => r.top, 'top', closeTo(t, 1e-9))
    .having((r) => r.width, 'width', closeTo(w, 1e-9))
    .having((r) => r.height, 'height', closeTo(h, 1e-9));

ChatEmojiGeometry _geometry(
  EmojiOnly emojiOnly, {
  required ChatEmojiPolicy policy,
  ContentKey? sticker,
  double maxWidth = 280,
  TextDirection direction = TextDirection.ltr,
  bool hasHeader = false,
  double bottomReserve = 0,
  Size viewport = _phone,
}) => ChatEmojiBody.geometryFor(
  emojiOnly: emojiOnly,
  policy: policy,
  sticker: sticker,
  viewport: viewport,
  maxWidth: maxWidth,
  direction: direction,
  hasHeader: hasHeader,
  bottomReserve: bottomReserve,
);

void main() {
  group('Android text layout', () {
    const policy = ChatEmojiPolicy.android();

    test('three mixed emoji: 3 boxes of 37.6, the text rect and its edge', () {
      final g = _geometry(_glyphs(3), policy: policy);

      expect(g.kind, ChatEmojiLayoutKind.text);
      expect(g.content, _rect(0, 0, 112.8, 37.6));
      expect(g.lastLine, _rect(0, 0, 112.8, 37.6));
      expect(g.size.width, closeTo(112.8, 1e-9));
      expect(g.size.height, closeTo(37.6, 1e-9));
      expect(g.trailingEdge, closeTo(112.8, 1e-9));
    });

    test('a reserved strip is below the text and part of the size', () {
      final g = _geometry(_glyphs(3), policy: policy, bottomReserve: 23);

      expect(g.size.height, closeTo(60.6, 1e-9));
      expect(g.reserved, _rect(0, 37.6, 112.8, 23));
      expect(g.content, _rect(0, 0, 112.8, 37.6));
    });

    test('ten mixed emoji wrap at the row; the last line is the shorter', () {
      // Font 22.8, box 26.8: 10 of them wrap at 280 into 10 (268), one line.
      final one = _geometry(_glyphs(10), policy: policy, maxWidth: 280);
      expect(one.content, _rect(0, 0, 268, 26.8));

      final wrapped = _geometry(_glyphs(10), policy: policy, maxWidth: 120);
      // floor(120 / 26.8) = 4 to a line: 4 + 4 + 2.
      expect(wrapped.content.width, closeTo(107.2, 1e-9));
      expect(wrapped.content.height, closeTo(3 * 26.8, 1e-9));
      expect(wrapped.lastLine, _rect(0, 53.6, 53.6, 26.8));
    });

    test('under a header the wrap is 65 % of the parent, not of the row', () {
      // 30 glyphs: box 26.8. The parent is 400 wide, the row 380.
      final free = _geometry(_glyphs(30), policy: policy, maxWidth: 380);
      final under = _geometry(
        _glyphs(30),
        policy: policy,
        maxWidth: 380,
        hasHeader: true,
        viewport: const Size(400, 800),
      );

      // floor(380 / 26.8) = 14; floor(260 / 26.8) = 9.
      expect(free.content.width, closeTo(14 * 26.8, 1e-9));
      expect(under.content.width, closeTo(9 * 26.8, 1e-9));
    });

    test('a parent width given by the host replaces the viewport', () {
      final g = ChatEmojiBody.geometryFor(
        emojiOnly: _glyphs(30),
        policy: policy,
        viewport: const Size(1200, 800),
        parentWidth: 400,
        maxWidth: 380,
        direction: TextDirection.ltr,
        hasHeader: true,
      );

      expect(g.content.width, closeTo(9 * 26.8, 1e-9));
    });

    test('right to left does not mirror the lines', () {
      final g = _geometry(_glyphs(2), policy: policy, direction: TextDirection.rtl);

      expect(g.direction, TextDirection.ltr);
      expect(g.items.first.left, 0);
      expect(g.trailingEdge, closeTo(2 * 44.8, 1e-9));
    });
  });

  group('Android sticker layout', () {
    test('112.5 dp art, no inset, so the box is the art', () {
      final g = _geometry(_glyphs(1), policy: const ChatEmojiPolicy.android(), sticker: _pack);

      expect(g.kind, ChatEmojiLayoutKind.sticker);
      expect(g.content, _rect(0, 0, 112.5, 112.5));
      expect(g.size, const Size(112.5, 112.5));
    });
  });

  group('iOS', () {
    const policy = ChatEmojiPolicy.ios();

    test('the sticker is 112 pt art in a 10 pt inset', () {
      final g = _geometry(_glyphs(1), policy: policy, sticker: _pack);

      expect(g.content, _rect(10, 10, 112, 112));
      expect(g.size, const Size(132, 132));
      expect(g.trailingEdge, 122);
    });

    test('the text is a 94 pt glyph for one emoji without a sticker', () {
      final g = _geometry(_glyphs(1), policy: policy);

      expect(g.content, _rect(0, 0, 98, 98));
    });

    test('a header does not narrow the emoji, which keep the full wrap', () {
      // 19 pt font, box 23: floor(200 / 23) = 8, under a header too.
      final free = _geometry(_glyphs(20), policy: policy, maxWidth: 200);
      final under = _geometry(_glyphs(20), policy: policy, maxWidth: 200, hasHeader: true);

      expect(free.content.width, 8 * 23);
      expect(under.content.width, 8 * 23);
    });
  });

  group('Desktop', () {
    const policy = ChatEmojiPolicy.desktop();

    test('three glyphs are 38 px images 2 px apart: 118 px', () {
      final g = _geometry(_glyphs(3), policy: policy);

      expect(g.content, _rect(0, 0, 118, 38));
      expect(g.items[1].left, 40);
    });

    test('the sticker is 112 px with no inset', () {
      final g = _geometry(_glyphs(1), policy: policy, sticker: _pack);

      expect(g.content, _rect(0, 0, 112, 112));
      expect(g.size, const Size(112, 112));
    });

    test('a custom emoji pair is 78 px boxes', () {
      final g = _geometry(_customs(2), policy: policy);

      expect(g.content, _rect(0, 0, 156, 78));
    });

    test('right to left mirrors: the trailing edge is the left one', () {
      final g = _geometry(_glyphs(3), policy: policy, direction: TextDirection.rtl);

      expect(g.direction, TextDirection.rtl);
      expect(g.trailingEdge, 0);
      expect(g.items.first.left, 80);
    });
  });

  test('the geometry is the box the body lays out to', () {
    // The body and the host's chrome must agree to the pixel; the body test
    // pumps the widget and compares. Here: the same inputs, the same value.
    final a = _geometry(_glyphs(7), policy: const ChatEmojiPolicy.android(), bottomReserve: 23);
    final b = _geometry(_glyphs(7), policy: const ChatEmojiPolicy.android(), bottomReserve: 23);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
