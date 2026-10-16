import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:meta/meta.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/policy/panel_os_family.dart';
import 'package:panel_presentation/src/policy/panel_window.dart';

/// A way the user or the system closes the panel.
enum PanelDismissal {
  /// The system back gesture or button, or a close intent of the host.
  back,

  /// The Escape key.
  escape,

  /// A press outside the panel.
  outsidePress,

  /// The pointer left the panel and its toggle.
  leave,

  /// No interaction for a while.
  idle,
}

/// The **presentation policy**: which kind the panel takes, what opens it,
/// what dismisses it, how big a popup is and which motion role animates it.
///
/// Plain values and decisions with no widgets and no platform reads, in the
/// shape of the selection policy: a sealed family with a mobile and a desktop
/// variant, chosen by OS family, never forked by conditional import. The host
/// may pass its own variant or override the kind of a single call.
///
/// The policy decides; a strategy registered with the controller draws the
/// kind it is given and publishes its occupancy.
@immutable
sealed class PanelPresentationPolicy {
  const PanelPresentationPolicy();

  /// The policy for [family]: mobile for Android and iOS, desktop otherwise.
  factory PanelPresentationPolicy.forFamily(PanelOsFamily family) =>
      family.isMobile
      ? const PanelPresentationPolicy$Mobile()
      : const PanelPresentationPolicy$Desktop();

  /// The share of the window height a popup takes.
  static const double popupHeightFraction = 0.75;

  /// The shortest a popup is, whatever the window.
  static const double popupMinHeight = 278;

  /// The tallest a popup is, whatever the window.
  static const double popupMaxHeight = 640;

  /// The kind opened when the host names none.
  ///
  /// [dockPreferred] is the user's persisted choice to keep the panel docked;
  /// a policy honours it only where [canDock] says docking is possible.
  PanelPresentation defaultKind({
    required PanelWindowClass windowClass,
    bool dockPreferred = false,
  });

  /// The kind to open: the host's [override] when given, otherwise
  /// [defaultKind].
  ///
  /// An override is not checked against [canDock] or anything else: it is the
  /// host's explicit decision for this call.
  PanelPresentation resolve({
    required PanelWindowClass windowClass,
    bool dockPreferred = false,
    PanelPresentation? override,
  }) =>
      override ??
      defaultKind(windowClass: windowClass, dockPreferred: dockPreferred);

  /// Whether the panel can be docked in a window of class [windowClass].
  bool canDock(PanelWindowClass windowClass);

  /// Whether a mouse pointer over the toggle opens the panel. Touch and
  /// stylus never do: they click.
  bool get hoverOpens;

  /// How [kind] can be dismissed under this policy.
  Set<PanelDismissal> dismissalsFor(PanelPresentation kind);

  /// How long after the pointer leaves a popup and its toggle it hides.
  Duration get leaveDelay => const Duration(milliseconds: 300);

  /// How long a popup without interaction waits before hiding.
  Duration get idleDelay => const Duration(seconds: 3);

  /// The height of a popup in a window [windowHeight] tall: three quarters
  /// of it, kept within [popupMinHeight] and [popupMaxHeight].
  double popupHeight({required double windowHeight}) => math.min(
    popupMaxHeight,
    math.max(popupMinHeight, windowHeight * popupHeightFraction),
  );

  /// The motion role of [kind] appearing.
  MotionRole showRole(PanelPresentation kind) => switch (kind) {
    AnchoredPopup() => MotionRole.popupShow,
    KeyboardReplacement() || Docked() => MotionRole.panelSlide,
  };

  /// The motion role of [kind] disappearing.
  MotionRole hideRole(PanelPresentation kind) => switch (kind) {
    AnchoredPopup() => MotionRole.popupHide,
    KeyboardReplacement() || Docked() => MotionRole.panelSlide,
  };

  /// The motion role of one kind replacing another while the panel stays up.
  MotionRole get switchRole => MotionRole.presentationSwitch;
}

/// The phone and tablet policy: the panel replaces the soft keyboard, a
/// touch opens it and only back dismisses it.
final class PanelPresentationPolicy$Mobile extends PanelPresentationPolicy {
  /// The mobile policy.
  const PanelPresentationPolicy$Mobile();

  @override
  PanelPresentation defaultKind({
    required PanelWindowClass windowClass,
    bool dockPreferred = false,
  }) => const KeyboardReplacement();

  @override
  bool canDock(PanelWindowClass windowClass) => false;

  @override
  bool get hoverOpens => false;

  @override
  Set<PanelDismissal> dismissalsFor(PanelPresentation kind) => const {
    PanelDismissal.back,
  };

  @override
  bool operator ==(Object other) => other is PanelPresentationPolicy$Mobile;

  @override
  int get hashCode => (PanelPresentationPolicy$Mobile).hashCode;

  @override
  String toString() => 'PanelPresentationPolicy.mobile';
}

/// The desktop and web policy: an anchored popup that hover opens and that
/// dismisses itself, or a docked section when the user prefers it and the
/// window is wide.
final class PanelPresentationPolicy$Desktop extends PanelPresentationPolicy {
  /// The desktop policy.
  const PanelPresentationPolicy$Desktop();

  @override
  PanelPresentation defaultKind({
    required PanelWindowClass windowClass,
    bool dockPreferred = false,
  }) => dockPreferred && canDock(windowClass)
      ? const Docked()
      : const AnchoredPopup();

  @override
  bool canDock(PanelWindowClass windowClass) => windowClass.isWide;

  @override
  bool get hoverOpens => true;

  @override
  Set<PanelDismissal> dismissalsFor(PanelPresentation kind) => switch (kind) {
    AnchoredPopup() => const {
      PanelDismissal.back,
      PanelDismissal.escape,
      PanelDismissal.outsidePress,
      PanelDismissal.leave,
      PanelDismissal.idle,
    },
    KeyboardReplacement() || Docked() => const {PanelDismissal.back},
  };

  @override
  bool operator ==(Object other) => other is PanelPresentationPolicy$Desktop;

  @override
  int get hashCode => (PanelPresentationPolicy$Desktop).hashCode;

  @override
  String toString() => 'PanelPresentationPolicy.desktop';
}
