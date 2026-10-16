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
  /// own, the search field is where the page declared it (in its content, it
  /// scrolls away with it and never pins), and a page pins its strip at the
  /// bottom and does not slide it. Hover and the click cursor are on.
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

  /// Whether the bar offers [action] under this arrangement.
  ///
  /// Backspace is a touch idiom: a soft keyboard that the panel replaced has
  /// no backspace key of its own, a physical one does, and the desktop
  /// reference client's panel has no such button.
  bool offersAction(PageAction action) =>
      this == touch || action.id != PageAction.backspaceId;

  /// Whether an inline search field pins to the top of the page once search
  /// opens, instead of staying in the content where it scrolls away.
  ///
  /// A touch idiom: a finger has the keyboard up and the results below the
  /// field, so the field stays in reach. A cursor scrolls the field away like
  /// any content, as the reference client's does.
  bool get pinsSearchWhenOpen => this == touch;

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
