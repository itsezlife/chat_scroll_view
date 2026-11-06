import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/page/catalog_page.dart';
import 'package:panel_pages/src/stickers/stickers_page_policy.dart';
import 'package:panel_shell/panel_shell.dart';

/// The stickers page: the packs of [source] as a catalogue of stickers under a
/// strip of the packs, over the shared [CatalogPage] scaffold.
///
/// A thin composition: the sections, geometry, header button and strip are
/// [StickersPagePolicy]'s, the viewport, loading, reporting and the scroll the
/// strip follows are the scaffold's. A tap on a sticker is reported to the
/// shell as a pick of the sticker's own kind; what picking one does (send it)
/// is the host's. The page has no search, and no bake: stickers are content,
/// not glyphs.
///
/// Requires the chrome theme, strings and motion scopes.
class StickersPage extends StatefulWidget {
  /// The stickers page of [host], showing the packs of [source] and drawing
  /// through [assets].
  const StickersPage({
    required this.host,
    required this.source,
    required this.assets,
    super.key,
  });

  /// The page's connection to the shell; fixed for the life of the widget.
  final PanelPageHost host;

  /// The packs, the recents first when the host keeps some: one collection
  /// each. Packs are `CollectionId.set` and the recents `CollectionId.recent`.
  final CollectionSource source;

  /// The asset cache the grid and the strip draw through.
  final AssetCacheScope assets;

  @override
  State<StickersPage> createState() => _StickersPageState();
}

class _StickersPageState extends State<StickersPage> {
  late StickersPagePolicy _policy = StickersPagePolicy(assets: widget.assets);

  @override
  void didUpdateWidget(StickersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.assets, widget.assets)) {
      _policy = StickersPagePolicy(assets: widget.assets);
    }
  }

  @override
  Widget build(BuildContext context) => CatalogPage(
    host: widget.host,
    source: widget.source,
    policy: _policy,
    assets: widget.assets,
    // What the bottom bar and the safe area do not cover: the shell passes the
    // bar's room down in the padding.
    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
  );
}
