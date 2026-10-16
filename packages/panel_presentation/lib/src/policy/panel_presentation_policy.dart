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

  /// A hold on auto-hide ended while the pointer was away from the panel and
  /// its toggle: the panel was kept open past a leave it would have taken,
  /// and goes after a delay instead.
  afterHold,
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

  /// The phone and tablet policy; see [PanelPresentationPolicy$Mobile].
  const factory PanelPresentationPolicy.mobile() =
      PanelPresentationPolicy$Mobile;

  /// The desktop and web policy; see [PanelPresentationPolicy$Desktop].
  const factory PanelPresentationPolicy.desktop() =
      PanelPresentationPolicy$Desktop;

  /// The policy for [family]: mobile for Android and iOS, desktop otherwise.
  factory PanelPresentationPolicy.forFamily(PanelOsFamily family) =>
      family.isMobile
      ? const PanelPresentationPolicy.mobile()
      : const PanelPresentationPolicy.desktop();

  /// The share of the window height a popup takes.
  static const double popupHeightFraction = 0.75;

  /// The shortest a popup is, whatever the window.
  static const double popupMinHeight = 278;

  /// The tallest a popup is, whatever the window.
  static const double popupMaxHeight = 640;

  /// The narrowest a dock is, whatever the user drags it to: the reference
  /// client's third column.
  double get dockMinWidth => 292;

  /// The widest a dock is.
  double get dockMaxWidth => 392;

  /// The room the content keeps beside a dock: a window narrower than this
  /// plus [dockMinWidth] has no dock, and a wider dock gives way to it.
  double get dockMinChatWidth => 380;

  /// The width of the strip along a dock's start edge that resizes it.
  double get dockResizeExtent => 6;

  /// The width of a dock in [window] when the user wants [wanted] (null for
  /// no wish): the wish held between [dockMinWidth] and [dockMaxWidth], then
  /// no wider than leaves [dockMinChatWidth] to the content, and never below
  /// [dockMinWidth] whatever the window.
  ///
  /// The wish is the user's and is kept as it was dragged, so a window that
  /// widens again gives it back.
  double dockWidthIn(PanelWindow window, {double? wanted}) {
    final held = math.min(
      dockMaxWidth,
      math.max(dockMinWidth, wanted ?? dockMinWidth),
    );
    return math.max(
      dockMinWidth,
      math.min(held, window.width - dockMinChatWidth),
    );
  }

  /// The kind opened when the host names none.
  ///
  /// [dockPreferred] is the user's persisted choice to keep the panel docked;
  /// a policy honours it only where [canDock] says docking is possible.
  PanelPresentation defaultKind({
    required PanelWindow window,
    bool dockPreferred = false,
  });

  /// The kind to open: the host's [override] when given, otherwise
  /// [defaultKind].
  ///
  /// An override is not checked against [canDock] or anything else: it is the
  /// host's explicit decision for this call.
  PanelPresentation resolve({
    required PanelWindow window,
    bool dockPreferred = false,
    PanelPresentation? override,
  }) => override ?? defaultKind(window: window, dockPreferred: dockPreferred);

  /// Whether the panel can be docked in [window]: the content and the dock fit
  /// side by side ([dockMinChatWidth] and [dockMinWidth]).
  ///
  /// Not the window class: the reference client docks as soon as the two
  /// minimums fit, and a window that does not fit has no dock however wide the
  /// user would like it.
  bool canDock(PanelWindow window);

  /// Whether a mouse pointer over the toggle opens the panel. Touch and
  /// stylus never do: they click.
  bool get hoverOpens;

  /// How [kind] can be dismissed under this policy.
  Set<PanelDismissal> dismissalsFor(PanelPresentation kind);

  /// How long after the pointer leaves a popup it hides, when no animation is
  /// running.
  ///
  /// Leaving the toggle is not governed by this: the popup's rectangle
  /// touches the toggle's, so the hide of a toggle leave waits only for the
  /// next event pass, which entering the popup cancels. A popup that is still
  /// appearing also hides at that pass rather than after this grace.
  Duration get leaveDelay => const Duration(milliseconds: 300);

  /// How long a popup waits to hide after a hold on auto-hide was released
  /// with the pointer away. There is no other idle timer: a popup nobody has
  /// hovered and nothing held stays until dismissed.
  Duration get afterHoldDelay => const Duration(seconds: 3);

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
    required PanelWindow window,
    bool dockPreferred = false,
  }) => const KeyboardReplacement();

  @override
  bool canDock(PanelWindow window) => false;

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
/// window has the room.
final class PanelPresentationPolicy$Desktop extends PanelPresentationPolicy {
  /// The desktop policy.
  const PanelPresentationPolicy$Desktop();

  @override
  PanelPresentation defaultKind({
    required PanelWindow window,
    bool dockPreferred = false,
  }) =>
      dockPreferred && canDock(window) ? const Docked() : const AnchoredPopup();

  @override
  bool canDock(PanelWindow window) =>
      window.width >= dockMinChatWidth + dockMinWidth;

  @override
  bool get hoverOpens => true;

  @override
  Set<PanelDismissal> dismissalsFor(PanelPresentation kind) => switch (kind) {
    AnchoredPopup() => const {
      PanelDismissal.back,
      PanelDismissal.escape,
      PanelDismissal.outsidePress,
      PanelDismissal.leave,
      PanelDismissal.afterHold,
    },
    // A dock is a standing section: no gesture closes it, the dock control
    // does (and Escape only steps back out of search, which the shell owns).
    Docked() => const {},
    KeyboardReplacement() => const {PanelDismissal.back},
  };

  @override
  bool operator ==(Object other) => other is PanelPresentationPolicy$Desktop;

  @override
  int get hashCode => (PanelPresentationPolicy$Desktop).hashCode;

  @override
  String toString() => 'PanelPresentationPolicy.desktop';
}
