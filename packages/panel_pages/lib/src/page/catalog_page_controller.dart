import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_shell/panel_shell.dart';

/// What a [CatalogPage] keeps across being unmounted: its catalogue controller
/// and the offset it left while search results were shown.
///
/// The shell's controller owns it through the page's `PageControllerRegistry`,
/// so a presentation switch (a popup that becomes a docked panel, a page
/// swiped off screen) finds the same scroll position again. A host that wants
/// to move the catalogue of a page from outside reaches it with
/// `registry.peek<CatalogPageController>(pageId)`.
final class CatalogPageController implements PanelPageController {
  /// The catalogue controller of the page: scroll commands, scroll events and
  /// roving focus.
  final PanelCatalogController catalog = PanelCatalogController();

  /// The offset browsing was left at when search results replaced it, to be
  /// restored when they go; null while browsing.
  double? browseOffset;

  @override
  void dispose() => catalog.dispose();
}
