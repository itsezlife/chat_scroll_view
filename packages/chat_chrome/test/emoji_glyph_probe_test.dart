/// A glyph the system cannot draw never reaches the grid as an empty box.
///
/// **Seam:** the pieces a host wires together, through their public API only:
/// `EmojiGlyphAtlasHost(observer:)` bakes the grid's glyphs and shows each
/// cell to a `MissingGlyphProbe` (the same pass, no second rasterisation); the
/// probe's verdict feeds `GlyphProbeEmojiPlatformFilter`; `EmojiPage` then
/// draws the filtered data from the baked pages, observed on a recording
/// canvas the way the viewport's own sprite tests observe it.
///
/// The "system" is a documented fake: a rasteriser that draws the
/// missing-glyph box for any glyph in [_unsupported] and for the probe's
/// reference, and a distinct solid colour for everything else. There is no
/// emoji font, so this demonstrates the logic, not any real device's output.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_chrome/src/panel/emoji_glyph_atlas_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

const _unsupported = {'🫩'};
const _glyphs = ['😀', '😁', '🫩'];

/// Draws what a system without the newest emoji draws.
final class _SystemWithoutNewEmoji implements GlyphRasteriser {
  final FakeGlyphRasteriser _draw = FakeGlyphRasteriser();

  /// Every glyph asked for, in order.
  final List<String> asked = <String>[];

  /// What the system draws for a glyph it has no art for.
  static const missingBox = 'missing-glyph box';

  @override
  void paint(ui.Canvas canvas, String glyph, ui.Rect cell) {
    asked.add(glyph);
    _draw.paint(
      canvas,
      _unsupported.contains(glyph) ||
              glyph == defaultMissingGlyphReferences.first
          ? missingBox
          : glyph,
      cell,
    );
  }
}

class _Data extends EmojiDataSource with EmojiDataListenerMixin {
  _Data(List<EmojiItem> items)
    : categories = [
        EmojiCategorySpec(id: 'faces', title: 'Faces', items: items),
      ];

  @override
  List<EmojiCategorySpec> categories;

  @override
  bool get isReady => true;
  @override
  int skinToneFor(String base) => 0;
  @override
  List<String> get recentGlyphs => const [];
  @override
  Future<void> load() async {}
  @override
  FutureOr<List<EmojiItem>> search(String query) => const [];
  @override
  Future<void> recordPick(EmojiItem item, {required EmojiPickSource source}) =>
      Future.value();
  @override
  Future<void> clearRecents() => Future.value();
  @override
  Future<void> setSkinTone(String base, int toneIndex) => Future.value();
  @override
  void dispose() => disposeDataListeners();
}

/// What one paint asks of the canvas: atlas sprites and placeholder circles.
class _RecordingCanvas implements ui.Canvas {
  int sprites = 0;
  int circles = 0;

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) => sprites += rects.length ~/ 4;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late FakeBakeFrameSource frames;
  late _Data data;
  late EmojiGlyphAtlasHost host;
  late MissingGlyphProbe probe;
  late _SystemWithoutNewEmoji system;

  setUp(() {
    frames = FakeBakeFrameSource();
    data = _Data([
      for (final glyph in _glyphs) EmojiItem.unicode(glyph: glyph),
    ]);
    system = _SystemWithoutNewEmoji();
    probe = MissingGlyphProbe(glyphs: _glyphs, artVersion: 'art-1');
    host = EmojiGlyphAtlasHost(
      dataSource: data,
      frames: frames,
      devicePixelRatio: 2,
      rasteriser: system,
      store: FakeGlyphPageStore(),
      observer: GlyphProbeBakeObserver(probe),
    );
  });
  tearDown(() {
    host.dispose();
    data.dispose();
  });

  /// Opens the panel and runs the bake to its end, with the real async the
  /// engine needs for image readbacks.
  Future<void> bakeEverything(WidgetTester tester) async {
    host
      ..sync(recents: const [])
      ..panelVisible.value = true;
    await tester.runAsync(() async {
      while (frames.hasPendingRequest) {
        frames.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await probe.completed.timeout(const Duration(seconds: 5));
    });
    await tester.pump();
  }

  Future<void> pumpGrid(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EmojiPage(
          dataSource: data,
          recents: const [],
          recentlyUsedLabel: 'Recent',
          onEmojiSelected: (_, {source = EmojiPickSource.grid}) {},
          glyphAtlas: host.atlas,
        ),
      ),
    ),
  );

  _RecordingCanvas paint(WidgetTester tester) {
    final canvas = _RecordingCanvas();
    tester
        .renderObject<RenderBox>(find.byType(PanelCatalogViewport))
        .paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  /// Frames until the atlas has loaded its pages for drawing.
  Future<void> settlePages(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  testWidgets('the bake shows the probe every glyph without drawing one twice', (
    tester,
  ) async {
    await bakeEverything(tester);

    expect(probe.isComplete, isTrue);
    expect(probe.supports('😀'), isTrue);
    expect(probe.supports('😁'), isTrue);
    expect(probe.supports('🫩'), isFalse);
    expect(probe.unsupported, {'🫩'});
    // One rasterising pass served both the atlas and the probe: each glyph and
    // the reference were drawn exactly once.
    expect(system.asked, unorderedEquals([..._glyphs, '\u{10FFFF}']));
  });

  testWidgets('unfiltered, the unsupported glyph is an empty box in the grid', (
    tester,
  ) async {
    await bakeEverything(tester);
    await pumpGrid(tester);
    await settlePages(tester);

    final canvas = paint(tester);

    expect(canvas.sprites, 3, reason: 'two emoji and the missing-glyph box');
  });

  testWidgets('filtered by the probe, the grid has no box for it', (
    tester,
  ) async {
    await bakeEverything(tester);
    final kept = await GlyphProbeEmojiPlatformFilter(
      probe,
    ).filter([for (final glyph in _glyphs) UnicodeEmojiItem(glyph: glyph)]);
    data.categories = [
      EmojiCategorySpec(id: 'faces', title: 'Faces', items: kept),
    ];
    host.sync(recents: const []);
    await pumpGrid(tester);
    await settlePages(tester);

    final canvas = paint(tester);

    expect(kept.map((item) => item.glyph), ['😀', '😁']);
    expect(canvas.sprites, 2);
    expect(canvas.circles, 0, reason: 'nothing left unbaked either');
  });

  testWidgets('filtering does not replan: the baked pages stay valid', (
    tester,
  ) async {
    await bakeEverything(tester);
    final atlas = host.atlas;

    data.categories = [
      EmojiCategorySpec(
        id: 'faces',
        title: 'Faces',
        items: const [EmojiItem.unicode(glyph: '😀')],
      ),
    ];
    host.sync(recents: const []);

    expect(host.atlas, same(atlas));
  });
}
