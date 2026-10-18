import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter_test/flutter_test.dart';

// Android's per-count font sizes (`Theme.java:8602-8606`,
// `MessageObject.java:2114-2148`), written out so the expectations do not
// come from the code under test.
const _allCustomFont = <int, double>{
  1: 81.6,
  2: 81.6,
  3: 55.2,
  4: 40.8,
  5: 33.6,
  6: 26.4,
  7: 22.8,
  8: 22.8,
  9: 22.8,
  10: 22.8,
};
const _mixedFont = <int, double>{
  1: 40.8,
  2: 40.8,
  3: 33.6,
  4: 26.4,
  5: 22.8,
  6: 22.8,
  7: 22.8,
  8: 22.8,
  9: 22.8,
  10: 22.8,
};

const _thumb = ContentKey.unicode('\u{1F44D}');

/// [count] items; all custom, or the first a unicode glyph.
EmojiOnly _items(int count, {required bool allCustom, List<int>? breaks}) =>
    EmojiOnly([
      for (var i = 0; i < count; i++)
        EmojiOnlyItem(
          !allCustom && i == 0 ? _thumb : ContentKey.document('d$i'),
          lineBreaksBefore: breaks?[i] ?? 0,
        ),
    ]);

/// Hands out [FakeInlineEmbed]s and remembers what it was asked for.
final class _Embeds {
  final asked = <(ContentKey, AssetPreset)>[];
  final made = <FakeInlineEmbed>[];

  InlineEmbed? call(ContentKey content, AssetPreset preset) {
    asked.add((content, preset));
    final embed = FakeInlineEmbed(sizeHint: preset.size);
    made.add(embed);
    return embed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Embeds embeds;
  late ChatSelectionController selection;

  setUp(() {
    embeds = _Embeds();
    selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.mobile(),
    );
    addTearDown(selection.dispose);
  });

  void view(WidgetTester tester, Size size) {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpBody(
    WidgetTester tester,
    EmojiOnly emojiOnly, {
    ContentKey? sticker,
    bool autoplay = true,
    bool hasHeader = false,
    double maxWidth = 3000,
    TextDirection direction = TextDirection.ltr,
    double textScale = 1,
    ChatEmojiEmbedFactory? factory,
    ChatEmojiPolicy policy = const ChatEmojiPolicy.android(),
    double bottomReserve = 0,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(
        tester.view,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Directionality(
        textDirection: direction,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ChatEmojiBody(
                controller: selection,
                messageId: 1,
                emojiOnly: emojiOnly,
                sticker: sticker,
                autoplay: autoplay,
                hasHeader: hasHeader,
                policy: policy,
                bottomReserve: bottomReserve,
                embedFactory: factory ?? embeds.call,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Size bodySize(WidgetTester tester) =>
      tester.getSize(find.byType(ChatEmojiBody));

  group('text layout sizes', () {
    for (final allCustom in [true, false]) {
      for (var count = 1; count <= 10; count++) {
        final font = (allCustom ? _allCustomFont : _mixedFont)[count]!;
        testWidgets(
          '$count ${allCustom ? 'custom' : 'mixed'}: font $font, box ${font + 4}',
          (tester) async {
            view(tester, const Size(3000, 1000));

            await pumpBody(tester, _items(count, allCustom: allCustom));

            final size = bodySize(tester);
            expect(size.width, closeTo(count * (font + 4), 1e-6));
            expect(size.height, closeTo(font + 4, 1e-6));
            // A custom emoji gets its preset at that step; a glyph none.
            final customs = allCustom ? count : count - 1;
            expect(embeds.asked, hasLength(customs));
            for (final (_, preset) in embeds.asked) {
              expect(
                preset,
                AssetPresets.emojiOnly(step: font, devicePixelRatio: 1),
              );
            }
          },
        );
      }
    }

    testWidgets('the text scale changes nothing', (tester) async {
      view(tester, const Size(3000, 1000));
      await pumpBody(tester, _items(3, allCustom: false));
      final plain = bodySize(tester);

      await pumpBody(tester, _items(3, allCustom: false), textScale: 3);

      expect(bodySize(tester), plain);
    });

    testWidgets('line breaks are honoured', (tester) async {
      view(tester, const Size(3000, 1000));

      await pumpBody(tester, _items(3, allCustom: true, breaks: [0, 0, 1]));

      // Font 55.2 for three items; two on the first line, one on the next.
      expect(bodySize(tester).width, closeTo(2 * 59.2, 1e-6));
      expect(bodySize(tester).height, closeTo(2 * 59.2, 1e-6));
    });

    testWidgets('right to left starts at the right edge on desktop', (
      tester,
    ) async {
      view(tester, const Size(400, 300));
      await pumpBody(
        tester,
        _items(2, allCustom: true),
        direction: TextDirection.rtl,
        policy: const ChatEmojiPolicy.desktop(),
      );

      expect(
        tester.getTopRight(find.byType(ChatEmojiBody)).dx,
        closeTo(400, 1e-6),
      );
      final first = embeds.made.first;
      final rect = first.paints.last.rect;
      // The first item is at the right end of the box.
      expect(rect.left, greaterThan(embeds.made.last.paints.last.rect.left));
    });

    testWidgets('right to left does not mirror on Android', (tester) async {
      view(tester, const Size(400, 300));
      await pumpBody(
        tester,
        _items(2, allCustom: true),
        direction: TextDirection.rtl,
      );

      final first = embeds.made.first.paints.last.rect;
      final last = embeds.made.last.paints.last.rect;
      expect(
        first.left,
        lessThan(last.left),
        reason: 'lines start at the left',
      );
    });

    testWidgets('a bottom reserve is room under the items, not a resize of '
        'them', (tester) async {
      view(tester, const Size(3000, 1000));

      await pumpBody(tester, _items(3, allCustom: false), bottomReserve: 23);

      expect(bodySize(tester).height, closeTo(33.6 + 4 + 23, 1e-6));
      expect(
        embeds.made,
        hasLength(2),
        reason: 'a rebuild with room does not re-make the embeds',
      );
    });

    testWidgets('desktop images are 38 px, 2 px apart', (tester) async {
      view(tester, const Size(3000, 1000));

      await pumpBody(
        tester,
        _items(3, allCustom: false),
        policy: const ChatEmojiPolicy.desktop(),
      );

      expect(bodySize(tester), const Size(118, 38));
    });
  });

  group('wrap', () {
    // 30 mixed glyphs: box 26.8.
    final run = _items(30, allCustom: false);

    testWidgets('without a header the run wraps at the full width', (
      tester,
    ) async {
      view(tester, const Size(1000, 1000));

      await pumpBody(tester, run, maxWidth: 400);

      // floor(400 / 26.8) = 14 to a line, three lines.
      expect(bodySize(tester).width, closeTo(14 * 26.8, 1e-6));
      expect(bodySize(tester).height, closeTo(3 * 26.8, 1e-6));
    });

    testWidgets('with a header it wraps at 65 % of the parent width', (
      tester,
    ) async {
      view(tester, const Size(400, 1000));

      await pumpBody(tester, run, maxWidth: 400, hasHeader: true);

      // floor(260 / 26.8) = 9 to a line, four lines.
      expect(bodySize(tester).width, closeTo(9 * 26.8, 1e-6));
      expect(bodySize(tester).height, closeTo(4 * 26.8, 1e-6));
    });

    testWidgets('the share is of the parent, not of the row: a narrow row '
        'under a wide screen wraps at the row', (tester) async {
      view(tester, const Size(1000, 1000));

      await pumpBody(tester, run, maxWidth: 400, hasHeader: true);

      // 65 % of 1000 is 650: the row's 400 is the limit, 14 to a line.
      expect(bodySize(tester).width, closeTo(14 * 26.8, 1e-6));
    });

    testWidgets('a host that knows its column gives the parent width', (
      tester,
    ) async {
      view(tester, const Size(1000, 1000));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: ChatEmojiBody(
                  controller: selection,
                  messageId: 1,
                  emojiOnly: run,
                  embedFactory: embeds.call,
                  hasHeader: true,
                  parentWidth: 400,
                ),
              ),
            ),
          ),
        ),
      );

      expect(bodySize(tester).width, closeTo(9 * 26.8, 1e-6));
    });
  });

  group('sticker layout', () {
    const pack = ContentKey.document('pack-thumb');

    testWidgets('a 360 x 640 viewport gives a 112.5 dp sticker with no inset '
        'on Android', (tester) async {
      view(tester, const Size(360, 640));

      await pumpBody(
        tester,
        EmojiOnly(const [EmojiOnlyItem(_thumb)]),
        sticker: pack,
      );

      expect(bodySize(tester), const Size(112.5, 112.5));
      final (content, preset) = embeds.asked.single;
      expect(content, pack);
      expect(preset.size, const Size.square(112.5));
      expect(
        preset,
        AssetPresets.emojiSticker(extent: 112.5, devicePixelRatio: 1),
      );
      expect(
        embeds.made.single.paints.last.rect,
        const Rect.fromLTWH(0, 0, 112.5, 112.5),
      );
    });

    testWidgets('iOS sets a 112 pt sticker in a 10 pt inset', (tester) async {
      view(tester, const Size(360, 640));

      await pumpBody(
        tester,
        EmojiOnly(const [EmojiOnlyItem(_thumb)]),
        sticker: pack,
        policy: const ChatEmojiPolicy.ios(),
      );

      expect(bodySize(tester), const Size(132, 132));
      expect(
        embeds.made.single.paints.last.rect,
        const Rect.fromLTWH(10, 10, 112, 112),
      );
    });

    testWidgets('a sticker of two items is the text layout', (tester) async {
      view(tester, const Size(360, 640));

      await pumpBody(tester, _items(2, allCustom: false), sticker: pack);

      expect(
        ChatEmojiBody.layoutKindFor(_items(2, allCustom: false), sticker: pack),
        ChatEmojiLayoutKind.text,
      );
      expect(
        ChatEmojiBody.layoutKindFor(EmojiOnly(const [EmojiOnlyItem(_thumb)])),
        ChatEmojiLayoutKind.text,
        reason: 'no resolved document, no sticker',
      );
      expect(embeds.asked.map((a) => a.$1), isNot(contains(pack)));
    });

    testWidgets('a custom emoji\'s sticker loops', (tester) async {
      view(tester, const Size(360, 640));
      const own = ContentKey.document('own');

      await pumpBody(
        tester,
        EmojiOnly(const [EmojiOnlyItem(own)]),
        sticker: own,
      );

      final preset = embeds.asked.single.$2;
      expect(preset.profile.animate, isTrue);
      expect(preset.profile.loop, isTrue);
    });

    testWidgets('the unicode sticker plays once', (tester) async {
      view(tester, const Size(360, 640));

      await pumpBody(
        tester,
        EmojiOnly(const [EmojiOnlyItem(_thumb)]),
        sticker: pack,
      );

      expect(embeds.asked.single.$2.profile.loop, isFalse);
      expect(embeds.asked.single.$2.profile.animate, isTrue);
    });

    testWidgets('autoplay false holds the first frame', (tester) async {
      view(tester, const Size(360, 640));

      await pumpBody(
        tester,
        EmojiOnly(const [EmojiOnlyItem(_thumb)]),
        sticker: pack,
        autoplay: false,
      );

      expect(embeds.asked.single.$2.profile.animate, isFalse);
    });
  });

  group('embeds', () {
    testWidgets('a rebuild keeps the embeds, a changed message replaces '
        'them', (tester) async {
      view(tester, const Size(3000, 1000));
      await pumpBody(tester, _items(2, allCustom: true));
      expect(embeds.made, hasLength(2));

      await pumpBody(tester, _items(2, allCustom: true));
      expect(embeds.made, hasLength(2));
      expect(embeds.made.any((e) => e.isDisposed), isFalse);

      await pumpBody(tester, _items(3, allCustom: true));
      expect(embeds.made.take(2).every((e) => e.isDisposed), isTrue);
      expect(embeds.made, hasLength(5));
    });

    testWidgets('leaving the tree disposes them', (tester) async {
      view(tester, const Size(3000, 1000));
      await pumpBody(tester, _items(2, allCustom: true));

      await tester.pumpWidget(const SizedBox());

      expect(embeds.made.every((e) => e.isDisposed), isTrue);
    });

    testWidgets('an embed that signals repaints the body', (tester) async {
      view(tester, const Size(3000, 1000));
      await pumpBody(tester, _items(1, allCustom: true));
      final embed = embeds.made.single;
      final before = embed.paints.length;

      embed.invalidate();
      await tester.pump();

      expect(embed.paints.length, greaterThan(before));
    });

    testWidgets('a factory with no embed leaves the square empty', (
      tester,
    ) async {
      view(tester, const Size(3000, 1000));

      await pumpBody(
        tester,
        _items(2, allCustom: true),
        factory: (_, _) => null,
      );

      expect(bodySize(tester).width, closeTo(2 * 85.6, 1e-6));
    });
  });

  group('geometry', () {
    // The host places chrome from `geometryFor` before the body is laid out:
    // the two must give the same box, whatever the platform or the layout.
    final cases = <String, (EmojiOnly, ContentKey?, ChatEmojiPolicy)>{
      'android text': (
        _items(7, allCustom: false),
        null,
        const ChatEmojiPolicy.android(),
      ),
      'android sticker': (
        EmojiOnly(const [EmojiOnlyItem(_thumb)]),
        const ContentKey.document('pack'),
        const ChatEmojiPolicy.android(),
      ),
      'ios sticker': (
        EmojiOnly(const [EmojiOnlyItem(_thumb)]),
        const ContentKey.document('pack'),
        const ChatEmojiPolicy.ios(),
      ),
      'ios text': (
        _items(12, allCustom: true),
        null,
        const ChatEmojiPolicy.ios(),
      ),
      'desktop text': (
        _items(3, allCustom: false),
        null,
        const ChatEmojiPolicy.desktop(),
      ),
    };
    for (final MapEntry(key: name, value: (emoji, sticker, policy))
        in cases.entries) {
      for (final header in [false, true]) {
        testWidgets('$name${header ? ' under a header' : ''}', (tester) async {
          view(tester, const Size(360, 640));

          await pumpBody(
            tester,
            emoji,
            sticker: sticker,
            policy: policy,
            hasHeader: header,
            maxWidth: 300,
            bottomReserve: 23,
          );

          final geometry = ChatEmojiBody.geometryFor(
            emojiOnly: emoji,
            policy: policy,
            sticker: sticker,
            viewport: const Size(360, 640),
            maxWidth: 300,
            direction: TextDirection.ltr,
            hasHeader: header,
            bottomReserve: 23,
          );
          expect(bodySize(tester), geometry.size);
        });
      }
    }
  });

  group('registration', () {
    testWidgets('it registers as a non-text body, and leaves on removal', (
      tester,
    ) async {
      view(tester, const Size(3000, 1000));
      await pumpBody(tester, _items(2, allCustom: true));

      expect(selection.hasBody(1), isFalse);
      final box = tester.getRect(find.byType(ChatEmojiBody));
      expect(
        selection.resolveInlineHit(1, box.centerLeft + const Offset(5, 0)),
        isA<ChatInlineHit$Embed>(),
      );

      await tester.pumpWidget(const SizedBox());

      expect(selection.resolveInlineHit(1, box.centerLeft), isNull);
    });

    testWidgets('a twin that must not register leaves the live entry alone', (
      tester,
    ) async {
      view(tester, const Size(3000, 1000));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ChatMarkdownBodyRegistration(
              registers: false,
              child: ChatEmojiBody(
                controller: selection,
                messageId: 1,
                emojiOnly: _items(2, allCustom: true),
                embedFactory: embeds.call,
              ),
            ),
          ),
        ),
      );

      expect(selection.resolveInlineHit(1, const Offset(5, 5)), isNull);
    });

    testWidgets('a unicode glyph is no hit, a custom emoji is an embed', (
      tester,
    ) async {
      view(tester, const Size(3000, 1000));
      await pumpBody(tester, _items(2, allCustom: false));
      final box = tester.getRect(find.byType(ChatEmojiBody));
      final y = box.center.dy;

      expect(selection.resolveInlineHit(1, Offset(box.left + 5, y)), isNull);
      expect(
        selection.resolveInlineHit(1, Offset(box.left + 40 + 5, y)),
        const ChatInlineHit.embed(messageId: 1, target: 'document:d1', alt: ''),
      );
    });
  });

  group('semantics', () {
    testWidgets('the label is the plain text of the message', (tester) async {
      final handle = tester.ensureSemantics();
      view(tester, const Size(3000, 1000));

      await pumpBody(
        tester,
        EmojiOnly(const [
          EmojiOnlyItem(_thumb),
          EmojiOnlyItem(ContentKey.unicode('\u{2764}'), lineBreaksBefore: 1),
        ]),
      );

      expect(
        tester.getSemantics(find.byType(ChatEmojiBody)).label,
        '\u{1F44D}\n\u{2764}',
      );
      handle.dispose();
    });

    testWidgets('the host gives the label when it has the full text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      view(tester, const Size(3000, 1000));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ChatEmojiBody(
              controller: selection,
              messageId: 1,
              emojiOnly: _items(2, allCustom: true),
              embedFactory: embeds.call,
              semanticsLabel: 'two custom emoji',
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(ChatEmojiBody)).label,
        'two custom emoji',
      );
      handle.dispose();
    });
  });

  group('cursor', () {
    testWidgets('over the sticker it is the click cursor', (tester) async {
      view(tester, const Size(360, 640));
      await pumpBody(
        tester,
        EmojiOnly(const [EmojiOnlyItem(_thumb)]),
        sticker: const ContentKey.document('pack'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.byType(ChatEmojiBody)));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );

      await mouse.moveTo(const Offset(350, 630));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        isNot(SystemMouseCursors.click),
      );
    });
  });
}
