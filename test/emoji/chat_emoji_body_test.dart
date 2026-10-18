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
    ChatEmojiSizes sizes = const ChatEmojiSizes(),
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
                sizes: sizes,
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

    testWidgets('right to left starts at the right edge', (tester) async {
      view(tester, const Size(400, 300));
      await pumpBody(
        tester,
        _items(2, allCustom: true),
        direction: TextDirection.rtl,
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

    testWidgets('with a header it wraps at 65 % of the width', (tester) async {
      view(tester, const Size(1000, 1000));

      await pumpBody(tester, run, maxWidth: 400, hasHeader: true);

      // floor(260 / 26.8) = 9 to a line, four lines.
      expect(bodySize(tester).width, closeTo(9 * 26.8, 1e-6));
      expect(bodySize(tester).height, closeTo(4 * 26.8, 1e-6));
    });
  });

  group('sticker layout', () {
    const pack = ContentKey.document('pack-thumb');

    testWidgets('a 360 x 640 viewport gives a 112.5 dp sticker in a 10 dp '
        'inset', (tester) async {
      view(tester, const Size(360, 640));

      await pumpBody(
        tester,
        EmojiOnly(const [EmojiOnlyItem(_thumb)]),
        sticker: pack,
      );

      expect(bodySize(tester), const Size(132.5, 132.5));
      final (content, preset) = embeds.asked.single;
      expect(content, pack);
      expect(preset.size, const Size.square(112.5));
      expect(
        preset,
        AssetPresets.emojiSticker(extent: 112.5, devicePixelRatio: 1),
      );
      expect(
        embeds.made.single.paints.last.rect,
        const Rect.fromLTWH(10, 10, 112.5, 112.5),
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
