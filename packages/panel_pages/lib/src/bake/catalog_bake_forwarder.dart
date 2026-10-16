import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/bake/bake_activity_port.dart';

/// Forwards the catalogue's activity to the glyph bake through a
/// [BakeActivityPort], so baking stays out of the way of scrolling and bakes
/// the visible band first.
///
/// - `PanelCatalogScrollingChanged` becomes [BakeActivityPort.reportScrolling]
///   at once, drag included: a finger that holds still is not at rest. This
///   forwarder is the one reporter, so a baker shared with other surfaces
///   keeps waiting until all of them rest.
/// - `PanelCatalogScrollSettled` becomes [BakeActivityPort.prioritise] with
///   the glyphs behind the visible keys, top first. Keys of content that is
///   not a unicode glyph are not baked and are dropped.
///
/// ## Swapping the port
///
/// A baker can be replaced while the page lives (a replan for another cell
/// size or density). Setting [port] tells the old one the surface is not
/// moving, tells the new one if it is, and repeats the last settled band to
/// it, so the new bake starts with what the user is looking at. The forwarder
/// itself lives as long as the page, which is what lets it know about a drag
/// that began before the swap. A forwarder created in the middle of a drag
/// learns of it with the next `PanelCatalogScrollingChanged`.
///
/// Nothing else in the catalogue talks to the baker, and a near-viewport event
/// moves none of this.
final class CatalogBakeForwarder {
  /// Starts forwarding [events] to [port], which may be null while no baker
  /// exists.
  CatalogBakeForwarder({
    required Stream<PanelCatalogScrollEvent> events,
    BakeActivityPort? port,
  }) : _port = port {
    _subscription = events.listen(_onEvent);
  }

  late final StreamSubscription<PanelCatalogScrollEvent> _subscription;
  BakeActivityPort? _port;
  var _scrolling = false;
  List<String>? _settled;
  var _disposed = false;

  /// The baker the activity is forwarded to, or null for none.
  BakeActivityPort? get port => _port;

  set port(BakeActivityPort? next) {
    if (_disposed || identical(_port, next)) return;
    final previous = _port;
    _port = next;
    if (_scrolling) previous?.reportScrolling(reporter: this, scrolling: false);
    if (_scrolling) next?.reportScrolling(reporter: this, scrolling: true);
    final settled = _settled;
    if (settled != null) next?.prioritise(settled);
  }

  /// Stops forwarding and tells the baker the surface is not moving.
  void dispose() {
    if (_disposed) return;
    unawaited(_subscription.cancel());
    if (_scrolling) {
      _port?.reportScrolling(reporter: this, scrolling: false);
    }
    _disposed = true;
    _port = null;
  }

  void _onEvent(PanelCatalogScrollEvent event) {
    switch (event) {
      case PanelCatalogScrollingChanged(:final scrolling):
        if (_scrolling == scrolling) return;
        _scrolling = scrolling;
        if (scrolling) _settled = null;
        _port?.reportScrolling(reporter: this, scrolling: scrolling);
      case PanelCatalogScrollSettled(:final visibleKeys):
        final glyphs = [
          for (final key in visibleKeys)
            if (key case ContentKey$Unicode(:final sequence)) sequence,
        ];
        _settled = glyphs;
        _port?.prioritise(glyphs);
      default:
        break;
    }
  }
}
