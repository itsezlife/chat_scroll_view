import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

// Regenerate with `flutter test --update-goldens test/goldens`.
//
// One row of the three loading paints a leaf can stand in with: the circle of
// a glyph that is not baked yet, the thumb-first silhouette of custom or
// animated content, and the sticker wash. Nothing ever arrives (the producer
// answers nothing), so each stays a placeholder. The wash is painted at a fixed
// frame time, seven tenths of the way through its sweep, so its band sits over
// the sticker's cell in every run. flutter_test renders text with the Ahem
// font, so the header does not depend on the host platform.
//
// The goldens were generated on macOS. Pixel-exact comparison on another
// platform (CI runs Linux) is unconfirmed: if edge anti-aliasing of the
// rounded shapes differs there, regenerate on the pinned platform or add a
// tolerance comparator, and record it here.
void main() {
  final variants = {
    'light': PanelCatalogThemeData.light,
    'dark': PanelCatalogThemeData.dark,
  };

  for (final MapEntry(key: name, value: theme) in variants.entries) {
    testWidgets('circle, thumb-first and wash placeholders, $name tokens', (
      tester,
    ) async {
      final snapshots = FakeCatalogSnapshotSource()
        ..replaceSections([
          CatalogSection(
            id: 'placeholders',
            title: 'Loading',
            leaves: [
              CatalogLeaf.unicode('😀'),
              CatalogLeaf.document(
                'custom',
                semanticKind: SemanticKind.customEmoji,
                mediaForm: MediaForm.still,
              ),
              CatalogLeaf.document(
                'sticker',
                semanticKind: SemanticKind.sticker,
                mediaForm: MediaForm.still,
              ),
            ],
          ),
        ]);
      final controller = PanelCatalogController();
      // No glyph source and a producer that never answers: nothing is baked and
      // nothing loads.
      final assets = AssetCacheScope(producer: _SilentProducer());
      addTearDown(() {
        snapshots.dispose();
        controller.dispose();
        assets.dispose();
      });

      await tester.binding.setSurfaceSize(const Size(216, 112));
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
      tester
          .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
          .debugFrameTime = () =>
          Duration(microseconds: theme.washPeriod.inMicroseconds * 7 ~/ 10);
      tester
          .renderObject<RenderPanelCatalog>(find.byType(PanelCatalogViewport))
          .markNeedsPaint();
      await tester.pump();

      await expectLater(
        find.byKey(const ValueKey('viewport')),
        matchesGoldenFile('placeholders_$name.png'),
      );
    });
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
