import 'package:catalog_assets/glyph_atlas.dart';
import 'package:content_model/content_model.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// TEMPORARY SHIM: forwards the catalogue's scrolling and settled events to the
/// [GlyphAtlas] the page owns, so the bake keeps pausing while the catalogue
/// moves and baking the visible band first.
///
/// The viewport names no atlas; the page that plans one listens to
/// [PanelCatalogController.events] and tells it. This is that page's half until
/// the emoji page of `panel_pages` owns the atlas (the page makes the same two
/// calls: [GlyphAtlas.reportScrolling] with a reporter of its own and
/// [GlyphAtlas.prioritise] with the glyphs behind the settled keys). Deleted
/// with `chat_chrome`.
///
/// One forwarder reports as one reporter, so an atlas shared with other
/// reporters still pauses until all of them rest.
final class CatalogAtlasBakeForwarder {
  /// Starts forwarding [events] to [atlas].
  CatalogAtlasBakeForwarder({
    required this.atlas,
    required EventObservable<PanelCatalogScrollEvent> events,
  }) : _events = events {
    _events.addListener(_onEvent);
  }

  /// The atlas this forwarder reports to.
  final GlyphAtlas atlas;

  final EventObservable<PanelCatalogScrollEvent> _events;
  var _scrolling = false;
  var _disposed = false;

  /// Stops forwarding and tells the atlas the catalogue is not moving.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events.removeListener(_onEvent);
    _setScrolling(scrolling: false);
  }

  void _onEvent(PanelCatalogScrollEvent event) {
    switch (event) {
      case PanelCatalogScrollingChanged(:final scrolling):
        _setScrolling(scrolling: scrolling);
      case PanelCatalogScrollSettled(:final visibleKeys):
        atlas.prioritise([
          for (final key in visibleKeys)
            if (key is ContentKey$Unicode) key.sequence,
        ]);
      default:
        break;
    }
  }

  void _setScrolling({required bool scrolling}) {
    if (_scrolling == scrolling) return;
    _scrolling = scrolling;
    atlas.reportScrolling(reporter: this, scrolling: scrolling);
  }
}
