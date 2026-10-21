import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';

const _perPage = 676; // GlyphAtlasLayout().cellsPerPage

void main() {
  late FakeBakeFrameSource frames;
  late StreamController<PanelCatalogScrollEvent> events;
  late GlyphAtlas atlas;

  setUp(() {
    frames = FakeBakeFrameSource();
    events = StreamController<PanelCatalogScrollEvent>.broadcast(sync: true);
    final visible = ValueNotifier<bool>(true);
    final opening = ValueNotifier<bool>(false);
    atlas = GlyphAtlas(
      index: GlyphAtlasIndex([for (var i = 0; i <= _perPage; i++) 'g$i']),
      rasteriser: FakeGlyphRasteriser(),
      store: FakeGlyphPageStore(),
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
    )..start();
    CatalogBakeForwarder(
      events: events.stream,
      port: GlyphAtlasBakePort(atlas),
    );
    addTearDown(() {
      atlas.dispose();
      visible.dispose();
      opening.dispose();
      unawaited(events.close());
    });
  });

  test('baking waits while the catalogue moves and resumes at rest', () {
    expect(frames.hasPendingRequest, isTrue);

    events.add(const PanelCatalogScrollingChanged(scrolling: true));
    expect(frames.hasPendingRequest, isFalse);

    events.add(const PanelCatalogScrollingChanged(scrolling: false));
    expect(frames.hasPendingRequest, isTrue);
  });

  test(
    'the page holding the band the catalogue settled on bakes first',
    () async {
      events.add(
        PanelCatalogScrollSettled(const [ContentKey.unicode('g$_perPage')]),
      );

      for (var i = 0; i < 60 && atlas.spriteOf('g$_perPage') == null; i++) {
        frames.pump();
        await pumpEventQueue();
      }

      expect(atlas.spriteOf('g$_perPage'), isNotNull);
      expect(atlas.spriteOf('g0'), isNull);
    },
  );
}
