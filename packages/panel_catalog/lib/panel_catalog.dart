/// Panel Catalog Viewport — extent-scroll catalog body with paint leaves.
///
/// Owns recycle, cell paint, and section geometry for the **catalog body**.
/// Does **not** own panel chrome (category strip, search, type tabs, pickers)
/// or asset fetch/decode (`CatalogAssetCache` from `catalog_assets`).
///
/// Primary host types: [PanelCatalogViewport], [CatalogSnapshot] (published
/// through a `ValueObservable` from `content_model`),
/// [PanelCatalogController] ([jumpTo], [scrollBy],
/// [PanelCatalogController.jumpToSection], [PanelCatalogController.events]),
/// [PanelCatalogThemeData], [PanelCatalogTheme], the leaf value
/// ([CatalogLeaf], [CatalogLeafHit]) and the section models ([CatalogSection],
/// [SectionLayout]), and section landing helpers ([scrollOffsetForSectionHeader],
/// [kFarPathDistanceGateFactor] flat-row near/far gate). Fakes live in
/// `package:panel_catalog/testing.dart`.
///
/// [PanelCatalogThemeData] / [PanelCatalogTheme] supply host paint tokens;
/// [PanelCatalogViewport] resolves [CatalogLeafPaintTheme] for the engine.
///
/// Engine internals (`RenderPanelCatalog`, binding pool, painter, slot
/// projection) are not exported — they live under `src/viewport/`.
/// Theme types live under `src/theme/`.
library;

export 'src/data/catalog_snapshot.dart';
export 'src/model/catalog_glyph_box.dart'
    show
        catalogGlyphBoxExtent,
        kCatalogGlyphBoxFraction,
        kCirclePlaceholderRadiusFactor;
export 'src/model/catalog_leaf.dart';
export 'src/model/catalog_leaf_hit.dart';
export 'src/model/catalog_section.dart';
export 'src/model/section_layout.dart';
export 'src/theme/panel_catalog_theme.dart';
export 'src/viewport/catalog_grid_metrics.dart' show largestCatalogGlyphBox;
export 'src/viewport/catalog_scroll_position.dart';
export 'src/viewport/panel_catalog_controller.dart';
export 'src/viewport/panel_catalog_scroll_events.dart';
export 'src/viewport/panel_catalog_viewport.dart';
export 'src/viewport/catalog_section_navigation.dart'
    show kFarPathDistanceGateFactor, scrollOffsetForSectionHeader;
