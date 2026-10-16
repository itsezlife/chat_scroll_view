import 'package:listen/listen.dart';
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
///
/// Hiding the panel is the exception a page may ask for: with
/// [restartsWhenHidden] set, the catalogue goes back to its start once the
/// presence it follows ([followPresence]) says the panel is no longer shown,
/// so it opens again at the start whether or not the page was mounted then.
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

  /// Whether the catalogue goes back to its start when the panel is hidden.
  ///
  /// The page sets it from its own setting each time it is built.
  bool restartsWhenHidden = false;

  ValueListenable<bool>? _presence;

  /// Follows [visible], the panel's presence as the page's host reports it.
  ///
  /// The same presence again changes nothing; the page calls this on every
  /// mount.
  void followPresence(ValueListenable<bool> visible) {
    if (identical(_presence, visible)) return;
    _presence?.removeListener(_onPresence);
    _presence = visible..addListener(_onPresence);
  }

  void _onPresence() {
    if (!restartsWhenHidden || (_presence?.value ?? true)) return;
    browseOffset = null;
    catalog.jumpTo(0);
  }

  @override
  void dispose() {
    _presence?.removeListener(_onPresence);
    _presence = null;
    catalog.dispose();
  }
}
