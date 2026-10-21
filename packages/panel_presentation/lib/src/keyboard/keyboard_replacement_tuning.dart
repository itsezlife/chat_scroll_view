import 'package:meta/meta.dart';
import 'package:panel_presentation/src/policy/panel_window.dart';

/// The numbers the keyboard-replacement presentation is tuned with.
///
/// Plain values so a host can adjust one without forking the strategy. The
/// defaults are the shipped ones: the search expansion, the hand-off timeout
/// and the default keyboard height of the reference client; the larger-window
/// heights and the cold-open delay are chosen defaults.
@immutable
final class KeyboardReplacementTuning {
  /// A tuning with every value given or defaulted.
  const KeyboardReplacementTuning({
    this.compactHeight = 200,
    this.mediumHeight = 260,
    this.expandedHeight = 320,
    this.searchExpansion = 175,
    this.searchReserve = 62,
    this.handOffTimeout = const Duration(seconds: 1),
    this.settleConfirmation = const Duration(milliseconds: 80),
    this.coldOpenDelay = const Duration(milliseconds: 50),
    this.settleTolerance = 2,
    this.sheetCornerRadius = 29,
  });

  /// The panel content height, when no keyboard height is known, in a
  /// compact window (a phone).
  final double compactHeight;

  /// The default content height in a medium window.
  final double mediumHeight;

  /// The default content height in an expanded window.
  final double expandedHeight;

  /// How much taller than its keyboard-sized height the panel grows while
  /// search is open.
  final double searchExpansion;

  /// The vertical space the expanded panel leaves for the composer and a
  /// margin, besides the top safe area: the expansion never covers it.
  final double searchReserve;

  /// How long a hand-off to the soft keyboard waits for the keyboard before
  /// it gives up and closes the panel on its own.
  final Duration handOffTimeout;

  /// How long a settled reading of a raised keyboard must stand, with no
  /// other reading after it, before the slot takes the keyboard to be up.
  ///
  /// A hide and a show that cross (the panel opened over the keyboard and
  /// left for it again within a few frames) can report one settled reading
  /// at the keyboard's full height between zeros; taken at its word, the
  /// panel would hand over to a keyboard that is about to fall and rise
  /// again. Zero takes every settled reading at once.
  final Duration settleConfirmation;

  /// How long a cold open waits, after the panel has been built, before it
  /// starts to move, so the page mounts while nothing animates.
  final Duration coldOpenDelay;

  /// How far, in logical pixels, a keyboard height may sit under the height
  /// being held and still count as the same height.
  final double settleTolerance;

  /// The radius of the sheet's top corners, seen once the panel has grown to
  /// its height: a moving sheet is clipped by the slot it grows in, so its
  /// corners show only at rest.
  final double sheetCornerRadius;

  /// The default content height in a window of class [windowClass].
  double defaultHeightFor(PanelWindowClass windowClass) =>
      switch (windowClass) {
        PanelWindowClass.compact => compactHeight,
        PanelWindowClass.medium => mediumHeight,
        PanelWindowClass.expanded => expandedHeight,
      };

  @override
  bool operator ==(Object other) =>
      other is KeyboardReplacementTuning &&
      other.compactHeight == compactHeight &&
      other.mediumHeight == mediumHeight &&
      other.expandedHeight == expandedHeight &&
      other.searchExpansion == searchExpansion &&
      other.searchReserve == searchReserve &&
      other.handOffTimeout == handOffTimeout &&
      other.settleConfirmation == settleConfirmation &&
      other.coldOpenDelay == coldOpenDelay &&
      other.settleTolerance == settleTolerance &&
      other.sheetCornerRadius == sheetCornerRadius;

  @override
  int get hashCode => Object.hash(
    compactHeight,
    mediumHeight,
    expandedHeight,
    searchExpansion,
    searchReserve,
    handOffTimeout,
    settleConfirmation,
    coldOpenDelay,
    settleTolerance,
    sheetCornerRadius,
  );
}
