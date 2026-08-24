/// Panel Catalog Viewport — extent-scroll catalog body with paint leaves.
///
/// Owns recycle, cell paint, and section geometry for the **catalog body**.
/// Does **not** own panel chrome (category strip, search, type tabs, pickers)
/// or asset fetch/decode (`CatalogAssetCache` from `catalog_assets`).
///
/// Primary host types: [PanelCatalogViewport], [CatalogDataSource],
/// [PanelCatalogController] ([jumpTo], [scrollBy], [PanelCatalogController.jumpToSection]),
/// leaf/section/presentation models, section landing helpers
/// ([scrollOffsetForSectionHeader], [kFarPathDistanceGateFactor]), and
/// [FakeCatalogDataSource].
///
/// Engine internals (`RenderPanelCatalog`, binding pool, painter, slot
/// projection) are not exported — they live under `src/viewport/`.
library;

export 'src/data/catalog_data_source.dart';
export 'src/data/fake_catalog_data_source.dart';
export 'src/model/catalog_leaf.dart';
export 'src/model/catalog_leaf_presentation.dart';
export 'src/model/catalog_section.dart';
export 'src/viewport/panel_catalog_controller.dart';
export 'src/viewport/panel_catalog_viewport.dart';
export 'src/viewport/catalog_section_navigation.dart'
    show kFarPathDistanceGateFactor, scrollOffsetForSectionHeader;
