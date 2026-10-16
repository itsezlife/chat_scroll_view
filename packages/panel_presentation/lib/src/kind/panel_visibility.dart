import 'package:meta/meta.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';

/// Whether and how the panel is on screen: the sealed **visibility state** of
/// the presentation controller.
///
/// Four phases, with the active [PanelPresentation] kind where there is one.
/// An impossible combination, such as a hidden panel with a kind, cannot be
/// built. [PanelVisibility$Showing] and [PanelVisibility$Hiding] are the
/// phases in which the panel moves; a strategy settles them when its motion
/// ends.
@immutable
sealed class PanelVisibility {
  const PanelVisibility();

  /// The panel is animating in as [kind].
  const factory PanelVisibility.showing(PanelPresentation kind) =
      PanelVisibility$Showing;

  /// The panel is at rest on screen as [kind].
  const factory PanelVisibility.shown(PanelPresentation kind) =
      PanelVisibility$Shown;

  /// The panel is animating out as [kind].
  ///
  /// [waitForIme] asks the strategy to keep the bottom space until the soft
  /// keyboard has taken it over, so closing the panel to type does not flash
  /// the composer down and up. Only the keyboard-replacement strategy reads
  /// it.
  const factory PanelVisibility.hiding(
    PanelPresentation kind, {
    bool waitForIme,
  }) = PanelVisibility$Hiding;

  /// The panel is not shown.
  static const PanelVisibility hidden = PanelVisibility$Hidden();

  /// The active kind, or null when hidden.
  PanelPresentation? get kind;

  /// Whether the panel is on screen, including while it slides in or out.
  bool get isVisible => switch (this) {
    PanelVisibility$Hidden() => false,
    PanelVisibility$Showing() ||
    PanelVisibility$Shown() ||
    PanelVisibility$Hiding() => true,
  };

  /// Whether the panel is moving: showing or hiding.
  bool get isMoving => switch (this) {
    PanelVisibility$Showing() || PanelVisibility$Hiding() => true,
    PanelVisibility$Hidden() || PanelVisibility$Shown() => false,
  };

  /// Whether the panel is animating in.
  bool get isShowing => switch (this) {
    PanelVisibility$Showing() => true,
    PanelVisibility$Hidden() ||
    PanelVisibility$Shown() ||
    PanelVisibility$Hiding() => false,
  };

  /// Whether the panel is animating out.
  bool get isHiding => switch (this) {
    PanelVisibility$Hiding() => true,
    PanelVisibility$Hidden() ||
    PanelVisibility$Showing() ||
    PanelVisibility$Shown() => false,
  };

  /// The same phase with [kind] swapped; hidden stays hidden.
  PanelVisibility withKind(PanelPresentation kind) => switch (this) {
    PanelVisibility$Hidden() => this,
    PanelVisibility$Showing() => PanelVisibility.showing(kind),
    PanelVisibility$Shown() => PanelVisibility.shown(kind),
    PanelVisibility$Hiding(:final waitForIme) => PanelVisibility.hiding(
      kind,
      waitForIme: waitForIme,
    ),
  };
}

/// The panel is not shown.
final class PanelVisibility$Hidden extends PanelVisibility {
  /// Hidden.
  const PanelVisibility$Hidden();

  @override
  PanelPresentation? get kind => null;

  @override
  bool operator ==(Object other) => other is PanelVisibility$Hidden;

  @override
  int get hashCode => (PanelVisibility$Hidden).hashCode;

  @override
  String toString() => 'PanelVisibility.hidden';
}

/// The panel is animating in.
final class PanelVisibility$Showing extends PanelVisibility {
  /// Showing as [kind].
  const PanelVisibility$Showing(this.kind);

  @override
  final PanelPresentation kind;

  @override
  bool operator ==(Object other) =>
      other is PanelVisibility$Showing && other.kind == kind;

  @override
  int get hashCode => Object.hash(PanelVisibility$Showing, kind);

  @override
  String toString() => 'PanelVisibility.showing($kind)';
}

/// The panel is at rest on screen.
final class PanelVisibility$Shown extends PanelVisibility {
  /// Shown as [kind].
  const PanelVisibility$Shown(this.kind);

  @override
  final PanelPresentation kind;

  @override
  bool operator ==(Object other) =>
      other is PanelVisibility$Shown && other.kind == kind;

  @override
  int get hashCode => Object.hash(PanelVisibility$Shown, kind);

  @override
  String toString() => 'PanelVisibility.shown($kind)';
}

/// The panel is animating out.
final class PanelVisibility$Hiding extends PanelVisibility {
  /// Hiding as [kind], optionally handing the bottom space to the keyboard.
  const PanelVisibility$Hiding(this.kind, {this.waitForIme = false});

  @override
  final PanelPresentation kind;

  /// Whether the strategy keeps the bottom space until the keyboard takes it.
  final bool waitForIme;

  @override
  bool operator ==(Object other) =>
      other is PanelVisibility$Hiding &&
      other.kind == kind &&
      other.waitForIme == waitForIme;

  @override
  int get hashCode => Object.hash(PanelVisibility$Hiding, kind, waitForIme);

  @override
  String toString() =>
      'PanelVisibility.hiding($kind${waitForIme ? ', waitForIme' : ''})';
}
