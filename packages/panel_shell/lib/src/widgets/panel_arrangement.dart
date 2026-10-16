import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/page/panel_page.dart';

/// How the panel's chrome is arranged for the way the user points.
///
/// A presentation chooses it (a keyboard replacement is touched, a popup or a
/// docked section is pointed at); the shell and the pages below it only read
/// it. Nothing here reads the platform.
enum PanelArrangement {
  /// Fingers: the type tabs and the page actions float together at the
  /// bottom and slide away while the content is read; a page puts its strip
  /// at the top, over its content, where it slides away and returns with the
  /// reading, and may place the search field among its content. The default,
  /// and what every presentation did before the arrangement existed.
  touch,

  /// A mouse or trackpad: the type tabs sit above the search field, the
  /// floating bar holds the page actions only and never slides away on its
  /// own, the search field is always the shell's own, and a page pins its
  /// strip at the bottom and does not slide it. Hover and the click cursor are
  /// on, and an empty search shows the whole catalogue.
  pointer;

  /// Whether the floating bar slides away while the content is scrolled.
  ///
  /// A touch idiom: a mouse-wheel step is a scroll like a drag, and one step
  /// would otherwise take the bar out of reach of a cursor that has no way to
  /// bring it back but scrolling the other way.
  bool get barHidesOnScroll => this == touch;

  /// Whether a page's strip (where it is at the top) and inline search field
  /// sit over the content and slide away as it is read.
  ///
  /// A touch idiom, like [barHidesOnScroll]: a cursor has no way to bring a
  /// strip back but scrolling the other way.
  bool get headerSlidesAway => this == touch;

  /// Where the search field of a page that declared [declared] is drawn.
  ///
  /// Under [touch] where the page said. Under [pointer] always `pinned`: the
  /// shell draws the field below the type tabs and above the page.
  SearchPlacement searchPlacementOf(SearchPlacement declared) =>
      this == touch ? declared : SearchPlacement.pinned;

  /// Whether an empty search narrows a page to the content used most.
  ///
  /// Under [touch] opening search shows the short list the keyboard leaves
  /// room for. Under [pointer] the field and the whole catalogue are on
  /// screen together, so clearing the text is all it takes to see the grid.
  bool get narrowsEmptySearch => this == touch;

  /// Whether a secondary click (a mouse's right button) on content opens a
  /// context menu, which takes the place of the buttons a touch page puts in
  /// its section headers.
  ///
  /// A finger has no right button, so under [touch] those actions stay in the
  /// header and a right click does nothing.
  bool get usesContextMenu => this == pointer;
}

/// Provides the [PanelArrangement] the enclosing `PanelShell` was given to the
/// pages below it.
///
/// A page reads it with [of], which answers [PanelArrangement.touch] outside a
/// shell, so a page built on its own (a test, a gallery) arranges itself as it
/// always did.
class PanelArrangementScope extends InheritedWidget {
  /// Provides [arrangement] to [child].
  const PanelArrangementScope({
    required this.arrangement,
    required super.child,
    super.key,
  });

  /// What the subtree is arranged for.
  final PanelArrangement arrangement;

  /// The arrangement in scope, or [PanelArrangement.touch] without one.
  ///
  /// Registers the caller as a dependent: a presentation that changes the
  /// arrangement under a mounted page (a popup docked in place) rebuilds it.
  static PanelArrangement of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PanelArrangementScope>()
          ?.arrangement ??
      PanelArrangement.touch;

  @override
  bool updateShouldNotify(PanelArrangementScope oldWidget) =>
      arrangement != oldWidget.arrangement;
}
