import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';

void main() {
  group('FakeBakeActivityPort', () {
    BakeActivityPortContract.run(() {
      final port = FakeBakeActivityPort();
      return (port: port, isHeldBack: () => port.isScrolling);
    });
  });

  group('GlyphAtlasBakePort', () {
    BakeActivityPortContract.run(() {
      final frames = FakeBakeFrameSource();
      final visible = ValueNotifier<bool>(true);
      final opening = ValueNotifier<bool>(false);
      final atlas = GlyphAtlas(
        index: GlyphAtlasIndex(['a', 'b']),
        rasteriser: FakeGlyphRasteriser(),
        store: FakeGlyphPageStore(),
        frames: frames,
        clock: ManualBakeClock().read,
        panelVisible: visible,
        panelOpening: opening,
      )..start();
      addTearDown(() {
        atlas.dispose();
        visible.dispose();
        opening.dispose();
      });
      return (
        port: GlyphAtlasBakePort(atlas),
        isHeldBack: () => !frames.hasPendingRequest,
      );
    });
  });
}
