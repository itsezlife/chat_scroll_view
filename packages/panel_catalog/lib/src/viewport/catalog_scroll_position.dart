import 'package:flutter/animation.dart';

/// The one contract a bound viewport offers its [PanelCatalogController]:
/// where the catalog is, how far it can go, and the four ways to move it.
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
}
