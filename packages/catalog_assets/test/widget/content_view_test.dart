import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _sticker = ContentKey.document('42');
const _other = ContentKey.document('43');
final _preset = AssetPresets.keyboardCell(extent: 20, devicePixelRatio: 2);
final _still = AssetPresets.keyboardCell(
  extent: 20,
  devicePixelRatio: 2,
  animate: false,
);

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

  Widget host(Widget child, {AssetCacheScope? provided}) => Directionality(
    textDirection: TextDirection.ltr,
    child: AssetCacheProvider(
      scope: provided ?? scope,
      child: Center(child: child),
    ),
  );

  group('attach', () {
    testWidgets('attaches the content with the preset on first build', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );

      expect(scope.isAttached(_sticker, _preset.spec), isTrue);
      expect(producer.attempts.single.request.spec, _preset.spec);
    });

    testWidgets('is as large as the preset', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );

      expect(tester.getSize(find.byType(ContentView)), _preset.size);
    });

    testWidgets('detaches when it leaves the tree', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );

      await tester.pumpWidget(host(const SizedBox()));

      expect(scope.isAttached(_sticker, _preset.spec), isFalse);
      expect(producer.attempts.single.isCancelled, isTrue);
    });

    testWidgets('does not attach again when the parent rebuilds', (
      tester,
    ) async {
      Widget view() => host(ContentView(content: _sticker, preset: _preset));

      await tester.pumpWidget(view());
      await tester.pumpWidget(view());
      await tester.pumpWidget(view());

      expect(producer.attempts, hasLength(1));
      expect(scope.isAttached(_sticker, _preset.spec), isTrue);
    });

    testWidgets('moves to the new content when it changes', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );

      await tester.pumpWidget(
        host(ContentView(content: _other, preset: _preset)),
      );

      expect(scope.isAttached(_sticker, _preset.spec), isFalse);
      expect(scope.isAttached(_other, _preset.spec), isTrue);
    });

    testWidgets('moves to the new spec when the preset changes', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );
      final bigger = AssetPresets.keyboardCell(extent: 40, devicePixelRatio: 2);

      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: bigger)),
      );

      expect(scope.isAttached(_sticker, _preset.spec), isFalse);
      expect(scope.isAttached(_sticker, bigger.spec), isTrue);
      expect(tester.getSize(find.byType(ContentView)), bigger.size);
    });

    testWidgets('keeps its attach when only the profile of the preset '
        'differs in a way that does not split the entry', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );

      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _still)),
      );

      expect(producer.attempts, hasLength(1));
      expect(scope.isAttached(_sticker, _still.spec), isTrue);
    });

    testWidgets('moves to another scope the host provides', (tester) async {
      final other = AssetCacheScope(
        producer: producer,
        clock: PlaybackClock(ticks: ticks),
      );
      addTearDown(other.dispose);
      Widget view(AssetCacheScope provided) => host(
        ContentView(content: _sticker, preset: _preset),
        provided: provided,
      );
      await tester.pumpWidget(view(scope));

      await tester.pumpWidget(view(other));

      expect(scope.isAttached(_sticker, _preset.spec), isFalse);
      expect(other.isAttached(_sticker, _preset.spec), isTrue);
    });

    testWidgets('uses the scope it is given over the provided one', (
      tester,
    ) async {
      final own = AssetCacheScope(
        producer: producer,
        clock: PlaybackClock(ticks: ticks),
      );
      addTearDown(own.dispose);

      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset, scope: own)),
      );

      expect(own.isAttached(_sticker, _preset.spec), isTrue);
      expect(scope.isAttached(_sticker, _preset.spec), isFalse);
    });

    testWidgets('needs a scope from somewhere', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ContentView(content: _sticker, preset: _preset),
        ),
      );

      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('paint', () {
    testWidgets('paints the placeholder before a stage exists', (tester) async {
      final placeholder = FakeAssetPaintable(label: 'placeholder');
      final withPlaceholder = AssetCacheScope(
        producer: producer,
        clock: PlaybackClock(ticks: ticks),
        mediaPlaceholder: placeholder,
      );
      addTearDown(withPlaceholder.dispose);

      await tester.pumpWidget(
        host(
          ContentView(content: _sticker, preset: _preset),
          provided: withPlaceholder,
        ),
      );

      expect(placeholder.paints, hasLength(1));
      expect(placeholder.paints.single.rect.size, _preset.size);
    });

    group('a placeholder of its own', () {
      late FakeAssetPaintable scoped;
      late AssetCacheScope withPlaceholder;

      setUp(() {
        scoped = FakeAssetPaintable(label: 'scope');
        withPlaceholder = AssetCacheScope(
          producer: producer,
          clock: PlaybackClock(ticks: ticks),
          mediaPlaceholder: scoped,
        );
        addTearDown(withPlaceholder.dispose);
      });

      testWidgets('is painted before a stage exists, instead of the '
          "scope's, in the placeholder tint", (tester) async {
        final own = FakeAssetPaintable(label: 'own');
        await tester.pumpWidget(
          host(
            ContentView(
              content: _sticker,
              preset: _preset,
              placeholder: own,
              placeholderTint: const Color(0xFF445566),
            ),
            provided: withPlaceholder,
          ),
        );

        expect(scoped.paints, isEmpty);
        expect(own.paints, hasLength(1));
        expect(own.paints.single.rect.size, _preset.size);
        expect(own.paints.single.context.tint, const Color(0xFF445566));
      });

      testWidgets('takes the tint of the view without a tint of its own', (
        tester,
      ) async {
        final own = FakeAssetPaintable(label: 'own');
        await tester.pumpWidget(
          host(
            ContentView(
              content: _sticker,
              preset: _preset,
              tint: const Color(0xFF112233),
              placeholder: own,
            ),
            provided: withPlaceholder,
          ),
        );

        expect(own.paints.single.context.tint, const Color(0xFF112233));
      });

      testWidgets('gives way to the thumbnail once one exists', (tester) async {
        final own = FakeAssetPaintable(label: 'own');
        await tester.pumpWidget(
          host(
            ContentView(content: _sticker, preset: _preset, placeholder: own),
            provided: withPlaceholder,
          ),
        );
        final thumbnail = producer.last.advance(AssetStage.placeholder);
        await tester.pump();

        expect(own.paints, hasLength(1));
        expect(thumbnail.paints, isNotEmpty);
      });
    });

    group('loading progress', () {
      RenderObject box(WidgetTester tester) =>
          tester.renderObject(find.byType(ContentView));

      testWidgets('is the reference radial progress over the centre until '
          'the first frame exists', (tester) async {
        await tester.pumpWidget(
          host(
            ContentView(content: _sticker, preset: _still, loadingRadius: 12),
          ),
        );

        // The disc of the indicator, centred in the 20 x 20 box.
        expect(box(tester), paints..circle(x: 10, y: 10, radius: 12));

        producer.last.advance(AssetStage.placeholder);
        await tester.pump();
        expect(box(tester), paints..circle(x: 10, y: 10, radius: 12));

        producer.last.advance(AssetStage.firstFrame);
        await tester.pump();
        expect(box(tester), isNot(paints..circle(radius: 12)));
      });

      testWidgets('is absent unless asked for', (tester) async {
        await tester.pumpWidget(
          host(ContentView(content: _sticker, preset: _still)),
        );

        expect(box(tester), isNot(paints..circle(radius: 12)));
      });

      testWidgets('asks for another frame only while it shows', (tester) async {
        await tester.pumpWidget(
          host(
            ContentView(content: _sticker, preset: _still, loadingRadius: 12),
          ),
        );

        expect(
          tester.hasRunningAnimations || tester.binding.hasScheduledFrame,
          isTrue,
        );

        producer.last.advance(AssetStage.full);
        await tester.pump();
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    });

    testWidgets('paints the canned paintable into its box', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );

      final painted = producer.last.advance(AssetStage.full);
      await tester.pump();

      expect(painted.paints, hasLength(1));
      expect(painted.paints.single.rect.size, _preset.size);
    });

    testWidgets('repaints when a better stage arrives and not otherwise', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );
      final thumbnail = producer.last.advance(AssetStage.placeholder);
      await tester.pump();
      await tester.pump();
      expect(thumbnail.paints, hasLength(1));

      final full = producer.last.advance(AssetStage.full);
      await tester.pump();

      expect(full.paints, hasLength(1));
      expect(thumbnail.paints, hasLength(1));
    });

    testWidgets('passes the tint and opacity on', (tester) async {
      await tester.pumpWidget(
        host(
          ContentView(
            content: _sticker,
            preset: _preset,
            tint: const Color(0xFF112233),
            opacity: 0.5,
          ),
        ),
      );

      final painted = producer.last.advance(AssetStage.full);
      await tester.pump();

      final context = painted.paints.last.context;
      expect(context.tint, const Color(0xFF112233));
      expect(context.opacity, 0.5);
    });

    testWidgets('repaints when the tint changes', (tester) async {
      Widget view(Color tint) =>
          host(ContentView(content: _sticker, preset: _preset, tint: tint));
      await tester.pumpWidget(view(const Color(0xFF000000)));
      final painted = producer.last.advance(AssetStage.full);
      await tester.pump();
      final before = painted.paints.length;

      await tester.pumpWidget(view(const Color(0xFFFFFFFF)));

      expect(painted.paints.length, before + 1);
      expect(painted.paints.last.context.tint, const Color(0xFFFFFFFF));
    });

    testWidgets('draws a glyph without a sprite as the placeholder', (
      tester,
    ) async {
      final atlas = FakeGlyphSpriteSource(const ['a', 'b']);
      addTearDown(atlas.dispose);
      scope.glyphSource = atlas;

      await tester.pumpWidget(
        host(
          ContentView(content: const ContentKey.unicode('a'), preset: _preset),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(producer.attempts, isEmpty);
    });
  });

  group('semantics', () {
    testWidgets('is silent without a label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );

      expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
      handle.dispose();
    });

    testWidgets('describes itself as an image with the label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          ContentView(
            content: _sticker,
            preset: _preset,
            semanticLabel: 'thumbs up',
          ),
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('thumbs up')),
        matchesSemantics(label: 'thumbs up', isImage: true),
      );
      handle.dispose();
    });
  });

  group('glyph page holds', () {
    late FakeGlyphSpriteSource atlas;

    setUp(() {
      atlas = FakeGlyphSpriteSource(const ['a', 'b', 'c', 'd']);
      scope.glyphSource = atlas;
      addTearDown(atlas.dispose);
    });

    testWidgets('holds the page of its glyph while it is in the tree', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ContentView(content: const ContentKey.unicode('c'), preset: _preset),
        ),
      );

      expect(atlas.holdCount(1), 1);
      expect(atlas.holdCount(0), 0);

      await tester.pumpWidget(host(const SizedBox()));

      expect(atlas.holdCount(1), 0);
    });

    testWidgets('takes one hold however often the parent rebuilds', (
      tester,
    ) async {
      Widget view() => host(
        ContentView(content: const ContentKey.unicode('a'), preset: _preset),
      );

      await tester.pumpWidget(view());
      await tester.pumpWidget(view());
      await tester.pumpWidget(view());

      expect(atlas.holdCount(0), 1);
    });

    testWidgets('moves its hold when the glyph changes', (tester) async {
      await tester.pumpWidget(
        host(
          ContentView(content: const ContentKey.unicode('a'), preset: _preset),
        ),
      );

      await tester.pumpWidget(
        host(
          ContentView(content: const ContentKey.unicode('d'), preset: _preset),
        ),
      );

      expect(atlas.holdCount(0), 0);
      expect(atlas.holdCount(1), 1);
    });

    testWidgets('draws the sprite when its page is baked and the placeholder '
        'when the page is released again', (tester) async {
      await tester.pumpWidget(
        host(
          ContentView(content: const ContentKey.unicode('a'), preset: _still),
        ),
      );

      atlas.bakePage(0);
      await tester.pump();
      final baked = _drawCalls(tester);
      atlas.releasePage(0);
      await tester.pump();
      final released = _drawCalls(tester);

      expect(baked, contains('drawImageRect'));
      expect(released, isNot(contains('drawImageRect')));
      expect(atlas.holdCount(0), 1);
    });

    testWidgets('keeps a hold per view for views of one page', (tester) async {
      await tester.pumpWidget(
        host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ContentView(
                content: const ContentKey.unicode('a'),
                preset: _preset,
              ),
              ContentView(
                content: const ContentKey.unicode('b'),
                preset: _preset,
              ),
            ],
          ),
        ),
      );
      expect(atlas.holdCount(0), 2);

      await tester.pumpWidget(
        host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ContentView(
                content: const ContentKey.unicode('a'),
                preset: _preset,
              ),
            ],
          ),
        ),
      );

      expect(atlas.holdCount(0), 1);
    });
  });

  group('playback', () {
    testWidgets('repaints on each tick while it plays', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );
      final painted = producer.last.advance(AssetStage.full, animated: true);
      await tester.pump();
      final before = painted.paints.length;

      ticks.tick(const Duration(milliseconds: 100));
      await tester.pump();

      expect(painted.paints.length, before + 1);
    });

    testWidgets('does not repaint a still preset on ticks', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _still)),
      );
      final painted = producer.last.advance(AssetStage.full, animated: true);
      await tester.pump();
      final before = painted.paints.length;

      ticks.tick(const Duration(milliseconds: 100));
      await tester.pump();

      expect(painted.paints.length, before);
    });

    testWidgets('stops while the host pauses the clock and resumes after', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );
      final painted = producer.last.advance(AssetStage.full, animated: true);
      await tester.pump();
      final before = painted.paints.length;

      scope.clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);
      ticks.tick(const Duration(milliseconds: 100));
      await tester.pump();
      expect(painted.paints.length, before);

      scope.clock.setPaused(PlaybackPauseLayer.routeMoving, paused: false);
      ticks.tick(const Duration(milliseconds: 200));
      await tester.pump();
      expect(painted.paints.length, before + 1);
    });

    testWidgets('stops while a ticker mode switches the subtree off', (
      tester,
    ) async {
      Widget view({required bool enabled}) => host(
        TickerMode(
          enabled: enabled,
          child: ContentView(content: _sticker, preset: _preset),
        ),
      );
      await tester.pumpWidget(view(enabled: true));
      final painted = producer.last.advance(AssetStage.full, animated: true);
      await tester.pump();
      final before = painted.paints.length;

      await tester.pumpWidget(view(enabled: false));
      ticks.tick(const Duration(milliseconds: 100));
      await tester.pump();
      expect(painted.paints.length, before);

      await tester.pumpWidget(view(enabled: true));
      ticks.tick(const Duration(milliseconds: 200));
      await tester.pump();
      expect(painted.paints.length, greaterThan(before));
    });

    testWidgets('leaves the clock when it leaves the tree', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );
      producer.last.advance(AssetStage.full, animated: true);
      await tester.pump();
      expect(ticks.isRunning, isTrue);

      await tester.pumpWidget(host(const SizedBox()));

      expect(ticks.isRunning, isFalse);
    });
  });

  // ADR 043, "Paint capability": the view is a render object that pushes
  // layers, so a playing asset on a platform texture is a texture layer.
  group('texture', () {
    List<TextureLayer> textures(WidgetTester tester) =>
        _find<TextureLayer>(tester.binding.renderViews.first.debugLayer!);

    testWidgets('a playing asset whose frames go to a texture is a texture '
        'layer at its box, and the view never paints it', (tester) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );
      final playing = producer.last.advance(AssetStage.full, animated: true)
        ..textureOnAdvance = const AssetTexture(id: 9, width: 64, height: 64);
      await tester.pump();
      ticks.tick(const Duration(milliseconds: 16));
      await tester.pump();
      final paintsWithTexture = playing.paints.length;
      ticks.tick(const Duration(milliseconds: 32));
      await tester.pump();

      final layer = textures(tester).single;
      // In the coordinates of the view's own repaint boundary.
      final box = Offset.zero & _preset.size;
      expect(layer.textureId, 9);
      expect(layer.rect, box);
      expect(playing.advances, isNotEmpty);
      expect(playing.paints, hasLength(paintsWithTexture));
    });

    testWidgets('a cover preset fills its box with the frame and is clipped '
        'to the box', (tester) async {
      const size = Size(40, 20);
      final cover = AssetPreset(
        size: size,
        spec: AssetSpec.atDensity(
          logicalWidth: size.width,
          logicalHeight: size.height,
          devicePixelRatio: 2,
        ),
        profile: const AssetProfile(animate: true, fit: AssetFit.cover),
      );
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: cover)),
      );
      // A portrait frame of 32 x 64 centred in a square texture of 64.
      producer.last
          .advance(AssetStage.full, animated: true)
          .textureOnAdvance = const AssetTexture(
        id: 9,
        width: 64,
        height: 64,
        frameWidth: 32,
        frameHeight: 64,
      );
      await tester.pump();
      ticks.tick(const Duration(milliseconds: 16));
      await tester.pump();

      final box = Offset.zero & size;
      final layer = textures(tester).single;
      // The frame covers the 40 x 20 box at the scale 40 / 32: the whole
      // texture is then 80 x 80, centred on the box.
      expect(
        layer.rect,
        Rect.fromCenter(center: box.center, width: 80, height: 80),
      );
      final clip = _ancestors(layer).whereType<ClipRectLayer>().first;
      expect(clip.clipRect, box);
    });

    testWidgets('a canvas paint is all a still or a texture-less asset gets', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ContentView(content: _sticker, preset: _preset)),
      );
      final playing = producer.last.advance(AssetStage.full, animated: true);
      await tester.pump();

      expect(textures(tester), isEmpty);
      expect(playing.paints, isNotEmpty);
    });
  });
}

// The layers of type [T] under [layer], depth first.
List<T> _find<T extends Layer>(Layer layer) => [
  if (layer is T) layer,
  if (layer is ContainerLayer)
    for (
      Layer? child = layer.firstChild;
      child != null;
      child = child.nextSibling
    )
      ..._find<T>(child),
];

// The ancestors of [layer], nearest first.
List<Layer> _ancestors(Layer layer) => [
  for (Layer? up = layer.parent; up != null; up = up.parent) up,
];

List<String> _drawCalls(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  final box = tester.renderObject<RenderBox>(find.byType(ContentView));
  box.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return [
    for (final call in canvas.invocations)
      call.invocation.memberName.toString().replaceAll(
        RegExp(r'Symbol\("|"\)'),
        '',
      ),
  ];
}
