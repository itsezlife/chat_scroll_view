import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

// Regenerate with `flutter test --update-goldens test/goldens`.
//
// What a section paints beyond its leaves: skeleton leaves while it loads (one
// row each in the three placeholder styles), a header with a trailing action,
// and the message row of a loaded section with nothing in it. Nothing ever
// arrives (the producer answers nothing), so the leaves of the action section
// stay placeholders. The sticker wash is painted at a fixed frame time, seven
// tenths of the way through its sweep. flutter_test renders text with the Ahem
// font, so titles, labels and messages do not depend on the host platform. The
// action is a label: an icon is a glyph of a font the test run does not load.
//
// The goldens were generated on macOS. Pixel-exact comparison on another
// platform (CI runs Linux) is unconfirmed: if edge anti-aliasing of the
// rounded shapes differs there, regenerate on the pinned platform or add a
// tolerance comparator, and record it here.
const _loadingSticker = CatalogSection(
  id: 'stickers',
  title: 'Stickers',
  leaves: [],
  state: CatalogSectionState.loading,
  skeletonCount: 3,
  contentBox: CatalogContentBox.cell,
  placeholderStyle: CatalogPlaceholderStyle.shapedWash,
);

final _scenarios = <String, ({List<CatalogSection> sections, Size size})>{
  'skeleton': (
    sections: [
      const CatalogSection(
        id: 'emoji',
        title: 'Emoji',
        leaves: [],
        state: CatalogSectionState.loading,
        skeletonCount: 3,
      ),
      const CatalogSection(
        id: 'custom',
        title: 'Custom',
        leaves: [],
        state: CatalogSectionState.failed,
        skeletonCount: 3,
        placeholderStyle: CatalogPlaceholderStyle.thumbFirst,
      ),
      _loadingSticker,
    ],
    size: const Size(216, 312),
  ),
  'header_action': (
    sections: [
      CatalogSection(
        id: 'recent',
        title: 'Recent',
        action: const CatalogSectionAction(id: 'clear', label: 'Clear'),
        leaves: [
          for (var i = 0; i < 3; i++)
            CatalogLeaf.document(
              'custom-$i',
              semanticKind: SemanticKind.customEmoji,
              mediaForm: MediaForm.still,
            ),
        ],
      ),
    ],
    size: const Size(216, 104),
  ),
  'empty_row': (
    sections: [
      const CatalogSection(
        id: 'saved',
        title: 'Saved',
        leaves: [],
        emptyMessage: 'Nothing yet',
      ),
    ],
    size: const Size(216, 104),
  ),
};

void main() {
  // Goldens sit next to this file, also when test/unit_test.dart runs it.
  setUpAll(
    () => goldenFileComparator = LocalFileComparator(
      Uri.file('test/goldens/section_states_golden_test.dart'),
    ),
  );
  final variants = {
    'light': PanelCatalogThemeData.light,
    'dark': PanelCatalogThemeData.dark,
  };

  for (final MapEntry(key: scenario, value: setup) in _scenarios.entries) {
    for (final MapEntry(key: name, value: theme) in variants.entries) {
      testWidgets('$scenario, $name tokens', (tester) async {
        final snapshots = FakeCatalogSnapshotSource(sections: setup.sections);
        final controller = PanelCatalogController();
        final assets = AssetCacheScope(producer: _SilentProducer());
        addTearDown(() {
          snapshots.dispose();
          controller.dispose();
          assets.dispose();
        });

        await tester.binding.setSurfaceSize(setup.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: PanelCatalogTheme(
              data: theme,
              child: RepaintBoundary(
                key: const ValueKey('viewport'),
                child: ColoredBox(
                  color: name == 'dark'
                      ? const Color(0xFF17212B)
                      : const Color(0xFFFFFFFF),
                  child: PanelCatalogViewport(
                    snapshots: snapshots,
                    assets: assets,
                    controller: controller,
                    spanCount: 3,
                    cellExtent: 72,
                    headerExtent: 32,
                  ),
                ),
              ),
            ),
          ),
        );
        final render = tester.renderObject<RenderPanelCatalog>(
          find.byType(PanelCatalogViewport),
        );
        render.debugFrameTime = () =>
            Duration(microseconds: theme.washPeriod.inMicroseconds * 7 ~/ 10);
        render.markNeedsPaint();
        await tester.pump();

        await expectLater(
          find.byKey(const ValueKey('viewport')),
          matchesGoldenFile('${scenario}_$name.png'),
        );
      });
    }
  }
}

/// A producer that never reports: every attempt hangs.
final class _SilentProducer implements AssetProducer {
  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) => _SilentTask();
}

final class _SilentTask implements AssetTask {
  @override
  void cancel() {}
}
