import 'package:listen/listen.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_shell/panel_shell.dart';

/// What a [CatalogPage] keeps across being unmounted: its catalogue controller
/// and the offset it left while search results were shown.
///
/// The shell's controller owns it through the page's `PageControllerRegistry`,
/// so a presentation switch (a popup that becomes a docked panel, a page
/// swiped off screen), a tab switch and a close keep the scroll position. A
/// host that wants to move the catalogue of a page from outside reaches it
/// with `registry.peek<CatalogPageController>(pageId)`.
///
/// A **fresh open** is the exception a page may ask for: with
/// [restartsOnFreshOpen] set, the catalogue goes back to its start when the
/// signal it follows ([followFreshOpen]) arrives, whether or not the page is
/// mounted then, so a page the pager has not built yet opens at its start
/// too.
///
/// A page that keeps more than the catalogue (the emoji page keeps its glyph
/// atlas) extends it: one page id holds one controller, and the scaffold finds
/// the subtype where it asks for this type.
base class CatalogPageController implements PanelPageController {
  /// The catalogue controller of the page: scroll commands, scroll events and
  /// roving focus.
  final PanelCatalogController catalog = PanelCatalogController();

  /// The offset browsing was left at when search results replaced it, to be
  /// restored when they go; null while browsing.
  double? browseOffset;

  /// Whether the catalogue goes back to its start on a fresh open.
  ///
  /// The page sets it from its policy each time it is built.
  bool restartsOnFreshOpen = false;

  Listenable? _freshOpen;

  /// Follows [freshOpen], the signal of a fresh open as the page's host
  /// reports it (`PanelPageHost.freshOpen`).
  ///
  /// The same signal again changes nothing; the page calls this on every
  /// mount.
  void followFreshOpen(Listenable freshOpen) {
    if (identical(_freshOpen, freshOpen)) return;
    _freshOpen?.removeListener(_onFreshOpen);
    _freshOpen = freshOpen..addListener(_onFreshOpen);
  }

  void _onFreshOpen() {
    if (!restartsOnFreshOpen) return;
    // Browsing starts again: an offset kept for the end of a search would
    // send it back to where the last open left it.
    browseOffset = null;
    catalog.jumpTo(0);
  }

  @override
  void dispose() {
    _freshOpen?.removeListener(_onFreshOpen);
    _freshOpen = null;
    catalog.dispose();
  }
}
