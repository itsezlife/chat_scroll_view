import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _sticker = ContentKey.document('42');
final _preset = AssetPresets.inlineMessage(
  ascent: 8,
  descent: 2,
  devicePixelRatio: 2,
);
const _rect = Rect.fromLTWH(4, 6, 12, 12);

List<String> _drawn(TestRecordingCanvas canvas) => [
  for (final call in canvas.invocations)
    if (call.invocation.memberName.toString().contains('draw'))
      call.invocation.memberName.toString().replaceAll(
        RegExp(r'Symbol\("|"\)'),
        '',
      ),
];

void main() {
  late FakeAssetProducer producer;
  late ManualPlaybackTickSource ticks;
  late AssetCacheScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    ticks = ManualPlaybackTickSource();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ticks),
    );
    addTearDown(scope.dispose);
  });

  ContentEmbed embedOf(ContentKey key, {AssetPreset? preset}) {
    final embed = ContentEmbed(
      scope: scope,
      content: key,
      preset: preset ?? _preset,
    );
    addTearDown(embed.dispose);
    return embed;
  }

  Canvas canvas() => Canvas(PictureRecorder());

  InlineEmbedContract.run(() => embedOf(_sticker));

  group('attach', () {
    test('attaches the key with the preset spec on creation', () {
      embedOf(_sticker);

      expect(scope.isAttached(_sticker, _preset.spec), isTrue);
      expect(producer.last.request, AssetRequest(_sticker, _preset.spec));
    });

    test('reports the preset size as its size hint', () {
      expect(embedOf(_sticker).sizeHint, _preset.size);
    });

    test('two embeds of one content share one attempt', () {
      embedOf(_sticker);
      embedOf(_sticker);

      expect(producer.attempts, hasLength(1));
    });
  });

  group('paint', () {
    test('paints the paintable of the stage reached into the rect', () {
      final embed = embedOf(_sticker);
      final first = producer.last.advance(AssetStage.firstFrame);

      embed.paint(canvas(), _rect, const InlineEmbedPaintContext());

      expect(first.paints.single.rect, _rect);
    });

    test('paints the scope placeholder before any stage', () {
      final placeholder = FakeAssetPaintable(label: 'placeholder');
      scope.dispose();
      scope = AssetCacheScope(
        producer: producer,
        clock: PlaybackClock(ticks: ticks),
        placeholder: placeholder,
      );
      addTearDown(scope.dispose);
      final embed = embedOf(_sticker);

      embed.paint(canvas(), _rect, const InlineEmbedPaintContext());

      expect(placeholder.paints.single.rect, _rect);
    });

    test('passes the text colour and opacity as tint and opacity', () {
      final embed = embedOf(_sticker);
      final painted = producer.last.advance(AssetStage.full);

      embed.paint(
        canvas(),
        _rect,
        const InlineEmbedPaintContext(tint: Color(0xFF112233), opacity: 0.5),
      );

      final context = painted.paints.single.context;
      expect(context.tint, const Color(0xFF112233));
      expect(context.opacity, 0.5);
    });

    test('draws nothing once disposed', () {
      final embed = embedOf(_sticker);
      final painted = producer.last.advance(AssetStage.full);

      embed.dispose();
      embed.paint(canvas(), _rect, const InlineEmbedPaintContext());

      expect(painted.paints, isEmpty);
    });
  });

  group('invalidation', () {
    test('tells a listener when a better stage arrives', () {
      final embed = embedOf(_sticker);
      var heard = 0;
      embed.addListener(() => heard++);

      producer.last.advance(AssetStage.placeholder);
      producer.last.advance(AssetStage.full);

      expect(heard, 2);
    });

    test('stops telling a removed listener', () {
      final embed = embedOf(_sticker);
      var heard = 0;
      void listener() => heard++;
      embed
        ..addListener(listener)
        ..removeListener(listener);

      producer.last.advance(AssetStage.full);

      expect(heard, 0);
    });

    test('is silent after dispose', () {
      final embed = embedOf(_sticker);
      var heard = 0;
      embed.addListener(() => heard++);
      final attempt = producer.last;

      embed.dispose();
      attempt.advance(AssetStage.full);

      expect(heard, 0);
    });
  });

  group('dispose', () {
    test('detaches, so an entry with a first frame is no longer pinned', () {
      final embed = embedOf(_sticker);
      producer.last.advance(AssetStage.full);

      embed.dispose();

      expect(scope.isAttached(_sticker, _preset.spec), isFalse);
      expect(scope.contains(_sticker, _preset.spec), isTrue);
    });

    test('cancels the running attempt when it was the last embed', () {
      final embed = embedOf(_sticker);

      embed.dispose();

      expect(producer.last.isCancelled, isTrue);
    });

    test('leaves the attempt running while another embed shows it', () {
      final first = embedOf(_sticker);
      embedOf(_sticker);

      first.dispose();

      expect(producer.last.isCancelled, isFalse);
    });

    test('gives back the attach once, however often it is called', () {
      final first = embedOf(_sticker);
      final second = embedOf(_sticker);

      first
        ..dispose()
        ..dispose();

      expect(scope.isAttached(_sticker, _preset.spec), isTrue);
      second.dispose();
      expect(scope.isAttached(_sticker, _preset.spec), isFalse);
    });
  });

  group('playback', () {
    final animated = AssetPresets.inlineMessage(
      ascent: 8,
      descent: 2,
      devicePixelRatio: 2,
    );

    test('advances while visible and stops when the body hides it', () {
      final embed = embedOf(_sticker, preset: animated);
      producer.last.advance(AssetStage.full, animated: true);
      var heard = 0;
      embed.addListener(() => heard++);

      ticks.tick(const Duration(milliseconds: 100));
      expect(heard, 1);

      embed.visible = false;
      ticks.tick(const Duration(milliseconds: 200));
      expect(heard, 1);
      expect(embed.visible, isFalse);
    });

    test('a sticker preset that does not autoplay stays still on attach', () {
      final held = embedOf(
        _sticker,
        preset: AssetPresets.emojiSticker(
          extent: 112,
          devicePixelRatio: 2,
          autoplay: false,
        ),
      );
      producer.last.advance(AssetStage.full, animated: true);
      var heard = 0;
      held.addListener(() => heard++);

      ticks.tick(const Duration(milliseconds: 100));

      expect(heard, 0);
    });

    test('a custom emoji item plays on attach', () {
      final item = embedOf(
        _sticker,
        preset: AssetPresets.emojiOnly(step: 40, devicePixelRatio: 2),
      );
      producer.last.advance(AssetStage.full, animated: true);
      var heard = 0;
      item.addListener(() => heard++);

      ticks.tick(const Duration(milliseconds: 100));

      expect(heard, 1);
    });

    test('stops while the host pauses the clock', () {
      final embed = embedOf(_sticker, preset: animated);
      producer.last.advance(AssetStage.full, animated: true);
      var heard = 0;
      embed.addListener(() => heard++);

      scope.clock.setPaused(PlaybackPauseLayer.fastScroll, paused: true);
      ticks.tick(const Duration(milliseconds: 100));

      expect(heard, 0);
    });
  });

  group('glyphs', () {
    late FakeGlyphSpriteSource atlas;
    const glyph = '\u{1F44D}';

    setUp(() {
      atlas = FakeGlyphSpriteSource(const [glyph, 'b', 'c', 'd']);
      scope.glyphSource = atlas;
      addTearDown(atlas.dispose);
    });

    test('holds the page of its glyph from creation to dispose', () {
      final embed = embedOf(const ContentKey.unicode(glyph));
      expect(atlas.holdCount(0), 1);

      embed.dispose();
      embed.dispose();

      expect(atlas.holdCount(0), 0);
    });

    test('draws the baked sprite once its page lands', () {
      final embed = embedOf(const ContentKey.unicode(glyph));
      var heard = 0;
      embed.addListener(() => heard++);
      final before = TestRecordingCanvas();
      embed.paint(before, _rect, const InlineEmbedPaintContext());

      atlas.bakePage(0);
      final after = TestRecordingCanvas();
      embed.paint(after, _rect, const InlineEmbedPaintContext());

      expect(heard, 1);
      expect(_drawn(before), ['drawCircle']);
      expect(_drawn(after), ['drawImageRect']);
    });

    test('keeps the hold of a page the atlas released while it shows', () {
      final embed = embedOf(const ContentKey.unicode(glyph));
      atlas.bakePage(0);

      atlas.releasePage(0);
      final recording = TestRecordingCanvas();
      embed.paint(recording, _rect, const InlineEmbedPaintContext());

      expect(atlas.holdCount(0), 1);
      expect(_drawn(recording), ['drawCircle']);
    });
  });
}
