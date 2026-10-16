import 'package:catalog_assets/glyph_atlas.dart';
import 'package:content_model/content_model.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_scroll_events.dart';

/// TEMPORARY SHIM: forwards the viewport's scrolling / settled events to the
/// [GlyphAtlas] its cache carries, so the bake keeps pausing while the
/// catalogue moves and baking the visible band first.
///
/// Deleted when the viewport binds through the asset-cache scope and stops
/// seeing the atlas: the page that owns the atlas then listens to
/// [PanelCatalogController.events] itself and makes the same two calls
/// ([GlyphAtlas.reportScrolling] with a reporter of its own,
/// [GlyphAtlas.prioritise] with the glyphs behind the settled keys).
///
/// One bridge reports as one reporter, so an atlas shared with other
/// reporters still pauses until all of them rest.
final class CatalogAtlasBakeBridge {
  /// Starts forwarding [events] to [atlas]. [scrolling] is the state to report
  /// at once, for a bridge created while the catalogue is already moving.
  CatalogAtlasBakeBridge({
    required this.atlas,
    required EventObservable<PanelCatalogScrollEvent> events,
    bool scrolling = false,
  }) : _events = events {
    _events.addListener(_onEvent);
    if (scrolling) _setScrolling(scrolling: true);
  }

  /// The atlas this bridge reports to.
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
