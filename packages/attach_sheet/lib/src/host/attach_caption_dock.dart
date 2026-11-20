import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What stands under a caption bar, from the host: the soft keyboard's
/// place, a panel (an emoji page) that can take it, and the swap between
/// the two, as the host's own composer has them.
///
/// The sheet puts the bar on [buildPlace]: the place is as tall as the
/// raised keyboard or the panel in its place, whichever stands, the bottom
/// safe area included, and moves with them; the bar pads [fieldBottomPad]
/// below its island, the part of the safe area the place does not cover.
/// So the bar is never lifted by the keyboard's inset on its own: the place
/// already holds it.
///
/// A dock lives as long as the bar it was made for; the sheet disposes it.
abstract interface class AttachCaptionDock {
  /// Fires when [panelUp] changes.
  Listenable get changes;

  /// Whether the panel stands (or is coming) in the keyboard's place: the
  /// bar's button then offers the keyboard.
  bool get panelUp;

  /// The bar's panel button: the panel in the keyboard's place, or the
  /// keyboard back in the panel's.
  void togglePanel();

  /// A tap on the caption field.
  void onFieldTap();

  /// A pointer went down on the caption field.
  void onFieldPointerDown();

  /// The pointer on the caption field lifted or was cancelled.
  void onFieldPointerEnd();

  /// The bar's bottom pad below its island: the safe area less what the
  /// place covers.
  ValueListenable<double> get fieldBottomPad;

  /// The place under the bar.
  Widget buildPlace(BuildContext context);

  /// Back: the dock's own steps first (a hand-off under way ends, the panel
  /// closes). True when it took the press.
  bool handleBack();

  /// The panel goes, the keyboard staying down; nothing when it is down.
  void closePanel();

  /// Frees what the dock made.
  void dispose();
}
