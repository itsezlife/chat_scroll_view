/// The shared page scaffold of the panel.
///
/// [CatalogPage] is the widget every catalogue page composes: it hosts the
/// `panel_catalog` viewport on the collections of a `CollectionSource`, loads
/// sections as they come near, shows search results for the shell's query,
/// reports picks and scroll activity to the shell, binds the keys of roving
/// focus and hands the catalogue's motion and visible band to a glyph bake
/// through a [BakeActivityPort]. A [CatalogPagePolicy] answers what depends on
/// the kind of content (section geometry, leaf facts and tag, pick, long press,
/// top strip, declared actions), so a page is a thin composition of a source
/// and a policy.
///
/// Depends on `panel_shell`, `panel_catalog`, `catalog_assets`, `content_model`
/// and `chrome_foundation`; never on a data payload, codec or fetcher
/// (`scripts/check` enforces that). Fakes and the [BakeActivityPort] contract
/// are in `package:panel_pages/testing.dart`.
library;

export 'src/assets/page_assets.dart';
export 'src/bake/bake_activity_port.dart';
export 'src/bake/catalog_bake_forwarder.dart';
export 'src/bake/glyph_atlas_bake_port.dart';
export 'src/input/catalog_keyboard_focus.dart';
export 'src/page/catalog_page.dart';
export 'src/page/catalog_page_controller.dart';
export 'src/page/catalog_page_model.dart';
export 'src/page/catalog_strip.dart';
export 'src/policy/catalog_page_policy.dart';
export 'src/scroll/page_scroll_reporter.dart';
export 'src/snapshot/catalog_snapshot_builder.dart';
export 'src/theme/chrome_catalog_theme.dart';
