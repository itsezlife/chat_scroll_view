import 'package:meta/meta.dart';

/// Where the panel appears and how it takes space: the closed set of
/// **panel presentation** kinds.
///
/// A kind is a value, not behaviour. The pure-Dart policy picks one, the
/// presentation controller holds the active one, and a strategy registered
/// for it draws the panel and publishes its occupancy. The set is sealed so a
/// host or a policy can switch over it exhaustively; a sheet or modal kind
/// would be a new variant.
@immutable
sealed class PanelPresentation {
  const PanelPresentation();

  /// The panel replaces the soft keyboard in the bottom slot.
  const factory PanelPresentation.keyboardReplacement() = KeyboardReplacement;

  /// The panel floats above the content next to the composer.
  const factory PanelPresentation.anchoredPopup() = AnchoredPopup;

  /// The panel is a permanent section at the reading end of the window.
  const factory PanelPresentation.docked() = Docked;

  /// A stable identifier, for keys and diagnostics.
  String get name;

  @override
  bool operator ==(Object other) =>
      other is PanelPresentation && other.runtimeType == runtimeType;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// The panel replaces the soft keyboard in the bottom slot, in flow: the host
/// lifts the composer by its occupancy.
final class KeyboardReplacement extends PanelPresentation {
  /// The keyboard-replacement kind.
  const KeyboardReplacement();

  @override
  String get name => 'keyboardReplacement';
}

/// The panel floats above the content next to the composer and dismisses
/// itself; it takes no space.
final class AnchoredPopup extends PanelPresentation {
  /// The anchored-popup kind.
  const AnchoredPopup();

  @override
  String get name => 'anchoredPopup';
}

/// The panel is a permanent section at the reading end of the window; its
/// width is its inline-end occupancy.
final class Docked extends PanelPresentation {
  /// The docked kind.
  const Docked();

  @override
  String get name => 'docked';
}
