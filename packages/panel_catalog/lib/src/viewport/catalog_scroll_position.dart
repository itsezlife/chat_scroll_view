import 'package:flutter/animation.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';
import 'package:panel_catalog/src/viewport/catalog_focus.dart';

/// The one contract a bound viewport offers its [PanelCatalogController]:
/// where the catalog is, how far it can go, the four ways to move it, and which
/// leaf holds roving focus and how that moves.
///
/// The render object implements this and attaches itself to the controller
/// while it is in the tree; the controller forwards the host's commands to
/// it. Hosts never implement or call this type: they command the controller,
/// which keeps working, with committed-target semantics, while nothing is
/// attached. Fakes of this contract live in `package:panel_catalog/testing.dart`.
///
/// ## Offset and extents
///
/// [pixels] is the absolute content offset in logical pixels, catalog top =
/// `0`. The position keeps it inside `[0, maxScrollExtent]` once it has a
/// size; before the first layout it may sit outside that range (a jump past
/// the end waits for the extent to be known).
///
/// ## Focus
///
/// [focusedLeaf] is the one cell that holds roving focus, or null. It belongs
/// to the position: it ends when the position does, and the position drops it
/// when a snapshot no longer has the cell. Focus commands answer whether they
/// changed or found anything, and publish a focus event on the controller when
/// the focused cell changes. Moving focus scrolls the cell into view (under
/// the landing inset) and brings the header of a section along when the cell
/// is in its first row.
///
/// ## Commands
///
/// Every command is relative to the attached position and is a silent no-op
/// when it changes nothing. Each publishes its own scroll events on the
/// controller; the controller does not publish for an attached position.
abstract interface class CatalogScrollPosition {
  /// Absolute content offset in logical pixels.
  double get pixels;

  /// Height of the viewport, or `0` before the first layout.
  double get viewportExtent;

  /// Total height of the projected catalog, padding included, or `0` before
  /// the first layout.
  double get contentExtent;

  /// Largest valid [pixels]: `max(0, contentExtent - viewportExtent)`, or `0`
  /// before the first layout.
  double get maxScrollExtent;

  /// Whether a section jump owns scroll motion.
  bool get isSectionJumpActive;

  /// Moves to [pixels] at once, cancelling programmatic motion and any fling.
  void jumpTo(double pixels);

  /// Moves by [delta] (positive reveals content below).
  void scrollBy(double delta);

  /// Scrolls smoothly to [pixels]; completes when the motion ends or is
  /// cancelled.
  Future<void> animateTo(
    double pixels, {
    required Duration duration,
    required Curve curve,
  });

  /// Lands the header of section [sectionIndex] under the viewport's top
  /// inset; completes when the motion ends or is cancelled.
  ///
  /// An out-of-range index completes at once without moving.
  Future<void> jumpToSection(int sectionIndex);

  /// The viewport's box in global coordinates, or null before the first
  /// layout.
  Rect? get viewportBounds;

  /// The cell [hit] names, as a rectangle in global coordinates under the
  /// current offset, or null when there is no such cell. It may lie partly
  /// or wholly outside the viewport.
  Rect? leafBounds(CatalogLeafHit hit);

  /// The cell that holds roving focus, or null.
  CatalogLeafHit? get focusedLeaf;

  /// Gives focus to the cell [index] of section [sectionId], scrolling it into
  /// view when [reveal]. Returns false, changing nothing, when there is no such
  /// cell.
  bool focusLeaf(String sectionId, int index, {required bool reveal});

  /// Moves focus by [move] and scrolls the cell it lands on into view.
  ///
  /// With no focus, a move enters the grid instead of stepping: [first] and
  /// [last] land on the ends, any other move on the first leaf in view.
  /// Returns false, changing nothing, where there is nowhere to go.
  bool moveFocus(CatalogFocusMove move);

  /// Reports the focused cell to the shell's tap, as a tap on it would.
  /// Returns false when nothing has focus or the shell has no tap.
  bool activateFocusedLeaf();

  /// Ends focus. A no-op when none is held.
  void clearFocus();
}
