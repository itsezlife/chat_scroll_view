/// The placement of the chrome around an emoji-only message, per platform
/// family: pure geometry, no widgets.
///
/// Every number is a literal worked by hand from the platform's source (the
/// research note `04-emoji-only-chrome.md`, section in each group's name), not
/// computed by the code under test. A `D` is a derivation over the cited terms.
/// The row frame is 300 wide, the time text 30 wide.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_chrome.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _glyph = ContentKey.unicode('\u{1F44D}');
const _pack = ContentKey.document('pack');
const _phone = Size(360, 640);
const _row = 300.0;
const _metrics = EmojiMetaMetrics(timeWidth: 30, timeHeight: 14);

EmojiOnly _glyphs(int count) =>
    EmojiOnly([for (var i = 0; i < count; i++) const EmojiOnlyItem(_glyph)]);

Matcher _rect(double l, double t, double w, double h) => isA<Rect>()
    .having((r) => r.left, 'left', closeTo(l, 1e-6))
    .having((r) => r.top, 'top', closeTo(t, 1e-6))
    .having((r) => r.width, 'width', closeTo(w, 1e-6))
    .having((r) => r.height, 'height', closeTo(h, 1e-6));

/// Lays [emoji] out under [chrome] the way the host does: the pill, the strip
/// it asks for, the body's geometry with that strip, then the chrome.
({EmojiChromeLayout layout, ChatEmojiGeometry body, EmojiPillLayout pill})
_place(
  ChatEmojiPolicy policy,
  EmojiOnly emoji, {
  ContentKey? sticker,
  bool outgoing = false,
  EmojiSendState state = EmojiSendState.none,
  EmojiMetaMetrics metrics = _metrics,
  EmojiHeaderShape? headerShape,
  Size? header,
  Size? reactions,
  double rowWidth = _row,
}) {
  final chrome = EmojiChrome.of(policy);
  ChatEmojiGeometry geometry(double reserve) => ChatEmojiBody.geometryFor(
    emojiOnly: emoji,
    policy: policy,
    sticker: sticker,
    viewport: _phone,
    maxWidth: rowWidth,
    direction: TextDirection.ltr,
    bottomReserve: reserve,
  );
  final kind = geometry(0).kind;
  final pill = chrome.pill(
    metrics: metrics,
    outgoing: outgoing,
    kind: kind,
    state: state,
  );
  final reserve = chrome.bottomReserve(
    kind: kind,
    outgoing: outgoing,
    contentHeight: geometry(0).content.height,
    pill: pill.size,
  );
  final body = geometry(reserve);
  return (
    layout: chrome.layout(
      EmojiChromeInput(
        body: body,
        outgoing: outgoing,
        rowWidth: rowWidth,
        pill: pill,
        headerShape: headerShape,
        header: header,
        reactions: reactions,
      ),
    ),
    body: body,
    pill: pill,
  );
}

void main() {
  group('Android (04 section 1)', () {
    const policy = ChatEmojiPolicy.android();

    group('the pill (1.4)', () {
      test('is 17 dp high and tw + 12 wide for an incoming message', () {
        final pill = EmojiChrome.of(policy).pill(
          metrics: _metrics,
          outgoing: false,
          kind: ChatEmojiLayoutKind.text,
        );

        expect(pill.size, const Size(42, 17));
        expect(pill.metaWidth, 30);
        expect(pill.timeOrigin.dx, 6, reason: '6 dp from the leading edge');
      });

      test('an outgoing text layout adds 24 dp for the ticks, a sticker 20 dp '
          '(tw + 36, tw + 32)', () {
        final chrome = EmojiChrome.of(policy);

        expect(
          chrome
              .pill(
                metrics: _metrics,
                outgoing: true,
                kind: ChatEmojiLayoutKind.text,
                state: EmojiSendState.sent,
              )
              .size
              .width,
          66,
        );
        expect(
          chrome
              .pill(
                metrics: _metrics,
                outgoing: true,
                kind: ChatEmojiLayoutKind.sticker,
                state: EmojiSendState.sent,
              )
              .size
              .width,
          62,
        );
      });

      test('views add the icon, a 10 dp gap and the count to the time width',
          () {
        const withViews = EmojiMetaMetrics(
          timeWidth: 30,
          timeHeight: 14,
          viewsWidth: 20,
        );
        final pill = EmojiChrome.of(policy).pill(
          metrics: withViews,
          outgoing: false,
          kind: ChatEmojiLayoutKind.text,
        );

        // 20 (count) + 14.17 (a 17 x 12 icon scaled to 10 high) + 10 + 30.
        expect(pill.metaWidth, closeTo(74.17, 0.01));
        expect(pill.size.width, closeTo(86.17, 0.01));
        expect(pill.viewsIcon!.left, 6);
        expect(pill.viewsIcon!.width, closeTo(14.17, 0.01));
        expect(pill.viewsIcon!.height, 10);
        expect(pill.viewsCountOrigin!.dx, closeTo(6 + 14.17 + 3, 0.01));
        expect(pill.timeOrigin.dx, closeTo(6 + 20 + 14.17 + 10, 0.01));
      });

      test('the radius is 12 dp for the text and the sticker layout', () {
        final chrome = EmojiChrome.of(policy);

        expect(chrome.pillRadius(17), 12);
      });

      test('ticks: one 12 dp check, 7.5 dp from the end of a text-layout '
          'pill (D)', () {
        final pill = EmojiChrome.of(policy).pill(
          metrics: _metrics,
          outgoing: true,
          kind: ChatEmojiLayoutKind.text,
          state: EmojiSendState.sent,
        );

        expect(pill.status, _rect(46.5, 2.5, 12, 12));
      });

      test('ticks: two checks 4.8 dp apart when read', () {
        final pill = EmojiChrome.of(policy).pill(
          metrics: _metrics,
          outgoing: true,
          kind: ChatEmojiLayoutKind.text,
          state: EmojiSendState.read,
        );

        expect(pill.status, _rect(41.7, 2.5, 16.8, 12));
      });

      test('ticks sit 5.5 dp from the end of a sticker-layout pill (D)', () {
        final pill = EmojiChrome.of(policy).pill(
          metrics: _metrics,
          outgoing: true,
          kind: ChatEmojiLayoutKind.sticker,
          state: EmojiSendState.sent,
        );

        expect(pill.status, _rect(44.5, 2.5, 12, 12));
      });

      test('the clock is 12 dp, 8 dp from the end; the error square 14 dp, '
          '6.5 dp from it', () {
        final chrome = EmojiChrome.of(policy);
        EmojiPillLayout of(EmojiSendState state) => chrome.pill(
          metrics: _metrics,
          outgoing: true,
          kind: ChatEmojiLayoutKind.text,
          state: state,
        );

        expect(of(EmojiSendState.sending).status, _rect(46, 2.5, 12, 12));
        expect(of(EmojiSendState.error).status, _rect(45.5, 1.5, 14, 14));
      });

      test('an incoming message has no ticks', () {
        final pill = EmojiChrome.of(policy).pill(
          metrics: _metrics,
          outgoing: false,
          kind: ChatEmojiLayoutKind.text,
          state: EmojiSendState.read,
        );

        expect(pill.status, isNull);
      });
    });

    group('the strip and the pill under the text (1.4)', () {
      test('the strip is 3 + 17 + 3 = 23 dp under the text', () {
        final chrome = EmojiChrome.of(policy);

        expect(
          chrome.bottomReserve(
            kind: ChatEmojiLayoutKind.text,
            outgoing: false,
            contentHeight: 37.6,
            pill: const Size(42, 17),
          ),
          23,
        );
      });

      test('an incoming pill ends 1 dp inside the text and is 3 dp below it',
          () {
        final p = _place(policy, _glyphs(3));

        expect(p.body.size.height, closeTo(60.6, 1e-9));
        expect(p.layout.body, _rect(0, 0, 112.8, 60.6));
        expect(p.layout.pill, _rect(69.8, 40.6, 42, 17));
        expect(p.layout.bounds, _rect(0, 0, 112.8, 60.6));
      });

      test('an outgoing pill ends 4 dp inside the text, at the right edge',
          () {
        final p = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
        );

        expect(p.layout.body, _rect(187.2, 0, 112.8, 60.6));
        expect(p.layout.pill, _rect(230, 40.6, 66, 17));
      });

      test('a lone narrow emoji: the pill is not pulled left of 3 dp', () {
        final p = _place(policy, _glyphs(1));

        // 44.8 wide text: the pill's left is max(3, 44.8 - 13 - 30).
        expect(p.layout.pill, _rect(3, 44.8 + 3, 42, 17));
        expect(p.layout.bounds.right, closeTo(45, 1e-9));
      });
    });

    group('the pill over the sticker (1.3, 1.4)', () {
      test('the strip below the art is 25 dp: 9 + the 16 dp an animated emoji '
          'is lowered by', () {
        final chrome = EmojiChrome.of(policy);

        expect(
          chrome.bottomReserve(
            kind: ChatEmojiLayoutKind.sticker,
            outgoing: false,
            contentHeight: 112.5,
            pill: const Size(42, 17),
          ),
          25,
        );
      });

      test('an incoming pill is 5 dp inside the art and spans [-7, +10] of '
          'its bottom edge', () {
        final p = _place(policy, _glyphs(1), sticker: _pack);

        expect(p.layout.body, _rect(0, 0, 112.5, 137.5));
        expect(p.layout.pill, _rect(65.5, 105.5, 42, 17));
      });

      test('an outgoing pill is 5 dp inside the art\'s right edge', () {
        final p = _place(
          policy,
          _glyphs(1),
          sticker: _pack,
          outgoing: true,
          state: EmojiSendState.sent,
        );

        expect(p.layout.body, _rect(187.5, 0, 112.5, 137.5));
        expect(p.layout.pill, _rect(233, 105.5, 62, 17));
      });
    });

    group('the reply and forward headers (1.6)', () {
      const text = EmojiHeaderText(
        nameWidth: 40,
        nameHeight: 17,
        textWidth: 60,
        textHeight: 17,
        forwardWidth: 90,
        forwardHeight: 34,
      );

      test('a reply is 43 dp high and max(name + 11, text + 22) + 3 wide', () {
        final chrome = EmojiChrome.of(policy);

        expect(
          chrome.headerSize(shape: EmojiHeaderShape.reply, text: text),
          const Size(85, 43),
        );
      });

      test('a forward is 44 dp high and its text + 14 wide', () {
        final chrome = EmojiChrome.of(policy);

        expect(
          chrome.headerSize(shape: EmojiHeaderShape.forward, text: text),
          const Size(104, 44),
        );
      });

      test('both are one 84 dp panel as wide as the wider of the two', () {
        final chrome = EmojiChrome.of(policy);

        expect(
          chrome.headerSize(
            shape: EmojiHeaderShape.forwardedReply,
            text: text,
          ),
          const Size(104, 84),
        );
      });

      test('above the text: an incoming reply is left-aligned 2 dp before the '
          'box, 13.34 dp over it', () {
        final p = _place(
          policy,
          _glyphs(3),
          headerShape: EmojiHeaderShape.reply,
          header: const Size(85, 43),
        );

        expect(p.layout.header, _rect(-2, -56.34, 85, 43));
        expect(p.layout.bounds.top, closeTo(-56.34, 1e-9));
      });

      test('above the text: an outgoing reply is left-aligned 9 dp before '
          'the box, not right-aligned', () {
        final p = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
          headerShape: EmojiHeaderShape.reply,
          header: const Size(85, 43),
        );

        expect(p.layout.header, _rect(187.2 - 9, -56.34, 85, 43));
      });

      test('an outgoing header that would pass the screen is pulled back so '
          'its end is 14 dp inside it', () {
        final p = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
          headerShape: EmojiHeaderShape.reply,
          header: const Size(200, 43),
        );

        expect(p.layout.header!.right, 282, reason: 'a reply\'s end is 18 dp in');
      });

      test('above the text: a forward starts 4 dp inside an incoming box and '
          '3 dp before an outgoing one, 8 dp over the text', () {
        final incoming = _place(
          policy,
          _glyphs(3),
          headerShape: EmojiHeaderShape.forward,
          header: const Size(104, 44),
        );
        final outgoing = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
          headerShape: EmojiHeaderShape.forward,
          header: const Size(104, 44),
        );

        expect(incoming.layout.header, _rect(4, -52, 104, 44));
        expect(outgoing.layout.header, _rect(187.2 - 3, -52, 104, 44));
      });

      test('above the text: forward and reply are one panel 18 dp over the '
          'text', () {
        final p = _place(
          policy,
          _glyphs(3),
          headerShape: EmojiHeaderShape.forwardedReply,
          header: const Size(104, 84),
        );

        expect(p.layout.header, _rect(4, -102, 104, 84));
      });

      test('beside the sticker: an incoming reply is 18 dp from the art, its '
          'top 4.66 dp below the art\'s', () {
        final p = _place(
          policy,
          _glyphs(1),
          sticker: _pack,
          headerShape: EmojiHeaderShape.reply,
          header: const Size(85, 43),
        );

        expect(p.layout.header, _rect(112.5 + 18, 4.66, 85, 43));
      });

      test('beside the sticker: an outgoing reply is pinned 16 dp from the '
          'row\'s left edge, not adjacent', () {
        final p = _place(
          policy,
          _glyphs(1),
          sticker: _pack,
          outgoing: true,
          state: EmojiSendState.sent,
          headerShape: EmojiHeaderShape.reply,
          header: const Size(85, 43),
        );

        expect(p.layout.header, _rect(16, 4.66, 85, 43));
      });

      test('beside the sticker: a forward starts 1 dp below the art\'s top',
          () {
        final p = _place(
          policy,
          _glyphs(1),
          sticker: _pack,
          headerShape: EmojiHeaderShape.forward,
          header: const Size(104, 44),
        );

        expect(p.layout.header!.top, closeTo(1, 1e-9));
      });
    });

    group('reactions (1.7)', () {
      test('under a text layout: the row\'s top is 29 dp under the text, its '
          'start at the text\'s start', () {
        final p = _place(
          policy,
          _glyphs(3),
          reactions: const Size(90, 26),
        );

        expect(p.layout.reactions, _rect(0, 37.6 + 29, 90, 26));
        expect(p.layout.pill!.bottom, lessThan(p.layout.reactions!.top));
      });

      test('an outgoing row ends at the text\'s end', () {
        final p = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
          reactions: const Size(90, 26),
        );

        expect(p.layout.reactions!.right, closeTo(300, 1e-9));
      });

      test('under a sticker: 23 dp under the art', () {
        final p = _place(
          policy,
          _glyphs(1),
          sticker: _pack,
          reactions: const Size(90, 26),
        );

        expect(p.layout.reactions!.top, closeTo(112.5 + 23, 1e-9));
      });
    });

    test('the time is always shown, nothing mirrors, selection is the '
        'viewport\'s row tint', () {
      final chrome = EmojiChrome.of(policy);

      expect(
        chrome.showsMeta(
          outgoing: false,
          kind: ChatEmojiLayoutKind.text,
          emojiOnly: _glyphs(3),
          hovered: false,
          isLastOwn: false,
          state: EmojiSendState.none,
        ),
        isTrue,
      );
      expect(chrome.mirrorsInRtl, isFalse);
      expect(chrome.selection, EmojiSelectionStyle.viewportRowTint);
    });
  });

  group('iOS (04 section 2)', () {
    const policy = ChatEmojiPolicy.ios();

    group('the pill (2.4)', () {
      test('is 17 pt high, fully rounded, date + status 13 + 14 wide', () {
        final chrome = EmojiChrome.of(policy);
        final incoming = chrome.pill(
          metrics: _metrics,
          outgoing: false,
          kind: ChatEmojiLayoutKind.text,
        );
        final outgoing = chrome.pill(
          metrics: _metrics,
          outgoing: true,
          kind: ChatEmojiLayoutKind.text,
          state: EmojiSendState.sent,
        );

        expect(incoming.size, const Size(44, 17));
        expect(outgoing.size, const Size(57, 17));
        expect(chrome.pillRadius(17), 8.5);
        expect(incoming.timeOrigin.dx, 7);
      });

      test('a sent check is 11 x 9 at the end of the date plus 1 pt', () {
        final pill = EmojiChrome.of(policy).pill(
          metrics: _metrics,
          outgoing: true,
          kind: ChatEmojiLayoutKind.text,
          state: EmojiSendState.sent,
        );

        // x = 7 + 30 + 5 + 13 - 11 - 6 = 38; y centred (17 - 9) / 2 = 4.
        expect(pill.status!.left, 38);
        expect(pill.status!.width, 11);
        expect(pill.status!.height, 9);
      });

      test('read: the second check is 6 pt after the first', () {
        final pill = EmojiChrome.of(policy).pill(
          metrics: _metrics,
          outgoing: true,
          kind: ChatEmojiLayoutKind.text,
          state: EmojiSendState.read,
        );

        // Two checks of 11 pt, 6 apart: 38 .. 55.
        expect(pill.status!.left, 38);
        expect(pill.status!.width, 17);
      });
    });

    group('placement (2.4)', () {
      test('text: the pill is 4 pt inside the box\'s end and bottom; the strip '
          'is 20 pt', () {
        final p = _place(policy, _glyphs(3));

        // 3 glyphs: 64 pt font, 68 boxes: content 204 x 68, strip 20.
        expect(p.body.size, const Size(204, 88));
        expect(p.layout.pill, _rect(156, 67, 44, 17));
      });

      test('a wide pill stops at the display inset, 6 pt before the box', () {
        final wide = _place(
          policy,
          _glyphs(1),
          metrics: const EmojiMetaMetrics(
            timeWidth: 120,
            timeHeight: 14,
          ),
        );

        // 98 wide box; the pill is 134 wide: its left is max(-6, 98 - 4 - 134).
        expect(wide.layout.pill!.left, -6);
      });

      test('sticker: the pill is 4 pt inside the 10 pt inset, so 6 pt outside '
          'the art', () {
        final p = _place(policy, _glyphs(1), sticker: _pack);

        expect(p.body.size, const Size(132, 132));
        expect(p.layout.pill, _rect(84, 111, 44, 17));
      });
    });

    group('headers (2.5)', () {
      test('are beside the text and the sticker alike, never above', () {
        final text = _place(
          policy,
          _glyphs(3),
          headerShape: EmojiHeaderShape.reply,
          header: const Size(90, 40),
        );
        final sticker = _place(
          policy,
          _glyphs(1),
          sticker: _pack,
          headerShape: EmojiHeaderShape.reply,
          header: const Size(90, 40),
        );

        expect(text.layout.header!.bottom, greaterThan(0));
        expect(sticker.layout.header!.bottom, greaterThan(0));
      });

      test('an outgoing header is pinned 14 pt from the left edge, an '
          'incoming one 12 pt from the right', () {
        final out = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
          headerShape: EmojiHeaderShape.reply,
          header: const Size(90, 40),
        );
        final incoming = _place(
          policy,
          _glyphs(3),
          headerShape: EmojiHeaderShape.reply,
          header: const Size(90, 40),
        );

        expect(out.layout.header!.left, 14);
        expect(incoming.layout.header!.right, 288);
      });

      test('its top is 8 pt under the frame\'s top: 8 pt over a text layout '
          '(the frame starts 16 pt above the text), 8 pt in for a sticker',
          () {
        final text = _place(
          policy,
          _glyphs(3),
          headerShape: EmojiHeaderShape.reply,
          header: const Size(90, 40),
        );
        final sticker = _place(
          policy,
          _glyphs(1),
          sticker: _pack,
          headerShape: EmojiHeaderShape.reply,
          header: const Size(90, 40),
        );

        expect(text.layout.header!.top, -8);
        expect(sticker.layout.header!.top, 8);
      });

      test('a reply is 17 pt wider than its longer line, 40 pt high', () {
        final chrome = EmojiChrome.of(policy);

        expect(
          chrome.headerSize(
            shape: EmojiHeaderShape.reply,
            text: const EmojiHeaderText(
              nameWidth: 40,
              nameHeight: 17,
              textWidth: 60,
              textHeight: 17,
              forwardWidth: 0,
              forwardHeight: 0,
            ),
          ),
          const Size(77, 40),
        );
      });
    });

    test('reactions go under the box, at its start (incoming) or end '
        '(outgoing)', () {
      final incoming = _place(
        policy,
        _glyphs(3),
        reactions: const Size(90, 26),
      );
      final outgoing = _place(
        policy,
        _glyphs(3),
        outgoing: true,
        state: EmojiSendState.sent,
        reactions: const Size(90, 26),
      );

      expect(incoming.layout.reactions, _rect(0, 88, 90, 26));
      expect(outgoing.layout.reactions!.right, closeTo(300, 1e-9));
      expect(outgoing.layout.reactions!.top, 88);
    });

    test('the time is always shown, nothing mirrors, selection is only the '
        'checkbox', () {
      final chrome = EmojiChrome.of(policy);

      expect(chrome.mirrorsInRtl, isFalse);
      expect(chrome.selection, EmojiSelectionStyle.none);
      expect(
        chrome.showsMeta(
          outgoing: false,
          kind: ChatEmojiLayoutKind.sticker,
          emojiOnly: _glyphs(1),
          hovered: false,
          isLastOwn: false,
          state: EmojiSendState.none,
        ),
        isTrue,
      );
    });
  });

  group('Desktop (04 section 3)', () {
    const policy = ChatEmojiPolicy.desktop();
    const desktopMetrics = EmojiMetaMetrics(timeWidth: 30, timeHeight: 17);

    group('the pill (3.3)', () {
      test('is the text plus 16 x 4 padding; outgoing adds the 24 px status '
          'space', () {
        final chrome = EmojiChrome.of(policy);
        final incoming = chrome.pill(
          metrics: desktopMetrics,
          outgoing: false,
          kind: ChatEmojiLayoutKind.text,
        );
        final outgoing = chrome.pill(
          metrics: desktopMetrics,
          outgoing: true,
          kind: ChatEmojiLayoutKind.text,
          state: EmojiSendState.sent,
        );

        expect(incoming.size, const Size(46, 21));
        expect(outgoing.size, const Size(70, 21));
        expect(incoming.timeOrigin, const Offset(8, 2));
      });
    });

    group('placement (3.3)', () {
      test('incoming: the pill is 6 px right of the content, bottom-aligned '
          'with it; there is no strip', () {
        final p = _place(policy, _glyphs(3), metrics: desktopMetrics);

        expect(p.body.size, const Size(118, 38));
        expect(p.layout.body, _rect(0, 0, 118, 38));
        expect(p.layout.pill, _rect(124, 17, 46, 21));
        expect(p.layout.bounds, _rect(0, 0, 170, 38));
      });

      test('outgoing text: the pill is under the glyphs, 2 px from them, '
          'ending at the content\'s end', () {
        final p = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
          metrics: desktopMetrics,
        );

        // 38 + 2 + 21 = 61 high; content right is the row's right.
        expect(p.layout.body, _rect(182, 0, 118, 61));
        expect(p.layout.pill, _rect(230, 40, 70, 21));
      });

      test('outgoing sticker: the pill overlaps the art\'s bottom-end corner',
          () {
        final p = _place(
          policy,
          _glyphs(1),
          sticker: _pack,
          outgoing: true,
          state: EmojiSendState.sent,
          metrics: desktopMetrics,
        );

        expect(p.layout.body, _rect(188, 0, 112, 112));
        expect(p.layout.pill, _rect(230, 91, 70, 21));
      });

      test('an incoming pill is pulled back inside the row\'s right margin '
          'of 22 px', () {
        final p = _place(
          policy,
          _glyphs(3),
          metrics: desktopMetrics,
          rowWidth: 150,
        );

        expect(p.layout.pill!.right, 128);
      });

      test('the strip is 2 px + the pill for content up to 38 high', () {
        final chrome = EmojiChrome.of(policy);

        expect(
          chrome.bottomReserve(
            kind: ChatEmojiLayoutKind.text,
            outgoing: true,
            contentHeight: 38,
            pill: const Size(70, 21),
          ),
          23,
        );
        expect(
          chrome.bottomReserve(
            kind: ChatEmojiLayoutKind.text,
            outgoing: false,
            contentHeight: 38,
            pill: const Size(46, 21),
          ),
          0,
        );
        expect(
          chrome.bottomReserve(
            kind: ChatEmojiLayoutKind.sticker,
            outgoing: true,
            contentHeight: 112,
            pill: const Size(70, 21),
          ),
          0,
        );
      });
    });

    group('visibility (3.3)', () {
      bool shown({
        bool outgoing = false,
        ChatEmojiLayoutKind kind = ChatEmojiLayoutKind.text,
        EmojiOnly? emoji,
        bool hovered = false,
        bool isLastOwn = false,
        EmojiSendState state = EmojiSendState.none,
      }) => EmojiChrome.of(policy).showsMeta(
        outgoing: outgoing,
        kind: kind,
        emojiOnly: emoji ?? _glyphs(3),
        hovered: hovered,
        isLastOwn: isLastOwn,
        state: state,
      );

      test('an incoming emoji shows no time until the pointer is on it', () {
        expect(shown(), isFalse);
        expect(shown(hovered: true), isTrue);
      });

      test('an outgoing large emoji always shows it', () {
        expect(shown(outgoing: true), isTrue);
      });

      test('an outgoing sticker shows it on hover, as the last own message, '
          'while sending or when it failed', () {
        final emoji = _glyphs(1);
        bool sticker({
          bool hovered = false,
          bool isLastOwn = false,
          EmojiSendState state = EmojiSendState.read,
        }) => shown(
          outgoing: true,
          kind: ChatEmojiLayoutKind.sticker,
          emoji: emoji,
          hovered: hovered,
          isLastOwn: isLastOwn,
          state: state,
        );

        expect(sticker(), isFalse);
        expect(sticker(hovered: true), isTrue);
        expect(sticker(isLastOwn: true), isTrue);
        expect(sticker(state: EmojiSendState.sending), isTrue);
        expect(sticker(state: EmojiSendState.error), isTrue);
      });

      test('a single line of more than 3 custom emoji shows it when '
          'outgoing', () {
        final four = EmojiOnly([
          for (var i = 0; i < 4; i++) EmojiOnlyItem(ContentKey.document('d$i')),
        ]);
        final two = EmojiOnly([
          for (var i = 0; i < 2; i++) EmojiOnlyItem(ContentKey.document('d$i')),
        ]);

        expect(shown(outgoing: true, emoji: four), isTrue);
        expect(shown(outgoing: true, emoji: two), isFalse);
      });
    });

    group('headers (3.4)', () {
      const header = Size(100, 40);

      test('beside when the row holds both: incoming 6 px after the content, '
          '3 px from the top', () {
        final p = _place(
          policy,
          _glyphs(3),
          metrics: desktopMetrics,
          headerShape: EmojiHeaderShape.reply,
          header: header,
        );

        expect(p.layout.header!.left, 124);
        // The element is max(38, 3 + 40 + 4 + 21) = 68 high and an incoming
        // content sits at its bottom: the header's top is 3 px into the
        // element, 30 px above the content.
        expect(p.layout.header!.top, closeTo(3 - 30, 1e-9));
        expect(p.layout.pill!.top, closeTo(17, 1e-9));
        expect(p.layout.bounds.height, closeTo(68, 1e-9));
      });

      test('beside, outgoing: hugging the content, 6 px before it', () {
        final p = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
          metrics: desktopMetrics,
          headerShape: EmojiHeaderShape.reply,
          header: header,
        );

        expect(p.layout.header!.right, 182 - 6);
      });

      test('above when content + min(additional, 86) passes the row: left '
          'for incoming, the content\'s end for outgoing', () {
        final incoming = _place(
          policy,
          _glyphs(3),
          metrics: desktopMetrics,
          rowWidth: 150,
          headerShape: EmojiHeaderShape.reply,
          header: header,
        );
        final outgoing = _place(
          policy,
          _glyphs(3),
          outgoing: true,
          state: EmojiSendState.sent,
          metrics: desktopMetrics,
          rowWidth: 150,
          headerShape: EmojiHeaderShape.reply,
          header: header,
        );

        // Panel 40 high, 3 px above it as the skip, 2 px margin below.
        expect(incoming.layout.header, _rect(0, -42, 100, 40));
        expect(
          outgoing.layout.header!.right,
          outgoing.layout.body.left + 118,
          reason: 'right-aligned with the content',
        );
      });
    });

    test('reactions go under the element, aligned to its side', () {
      final p = _place(
        policy,
        _glyphs(3),
        metrics: desktopMetrics,
        reactions: const Size(90, 26),
      );

      expect(p.layout.reactions!.left, 0);
      expect(p.layout.reactions!.top, closeTo(38 + 4, 1e-9));
    });

    test('everything mirrors in a right-to-left chat, selection recolours the '
        'glyph', () {
      final chrome = EmojiChrome.of(policy);
      final p = _place(
        policy,
        _glyphs(3),
        metrics: desktopMetrics,
        headerShape: EmojiHeaderShape.reply,
        header: const Size(100, 40),
      );

      final mirrored = p.layout.mirrored(300);

      expect(chrome.mirrorsInRtl, isTrue);
      expect(chrome.selection, EmojiSelectionStyle.glyphRecolour);
      expect(mirrored.body.right, 300 - p.layout.body.left);
      expect(mirrored.pill!.left, 300 - p.layout.pill!.right);
      expect(mirrored.header!.left, 300 - p.layout.header!.right);
    });
  });

  group('the divergences are named constants', () {
    test('every unverified value is a named, documented constant', () {
      // Each is listed in ADR 036's divergence table.
      expect(EmojiChrome$Android.unverifiedClockSize, 12);
      expect(EmojiChrome$Ios.unverifiedPillHeight, 17);
      expect(EmojiChrome$Ios.unverifiedHeaderHeight, 40);
      expect(EmojiChrome$Desktop.unverifiedRadius, 6);
      expect(EmojiChrome$Desktop.unverifiedTickSize, 12);
      expect(EmojiChrome$Desktop.unverifiedReactionsGap, 4);
    });
  });
}
