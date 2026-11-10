import 'package:flutter/animation.dart';

/// The ink of a section header's trailing action under a mouse: a fill
/// under the hovered action, and a ripple from a press that grows over
/// [grow] (ease out quint) and fades over [fade] once the press ends. The
/// desktop feedback of a chrome button, painted by the viewport, since the
/// action is drawn by it and no widget wraps it.
///
/// Owns its two controllers and which action is hovered or pressed. Does
/// **not** own hit-testing or the paint: the render object tells it where the
/// mouse and the press are, and the painter reads [hovered] and [press].
final class CatalogActionInk {
  /// Idle ink whose controllers tick on [vsync]; [onChanged] repaints.
  CatalogActionInk({required TickerProvider vsync, required this.onChanged})
    : _grow = AnimationController(vsync: vsync, duration: grow),
      _alpha = AnimationController(vsync: vsync, duration: fade) {
    _grow.addListener(onChanged);
    _alpha
      ..addListener(onChanged)
      ..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) _pressed = null;
      });
  }

  /// How long the ripple takes to grow over the action: 650 ms.
  static const Duration grow = Duration(milliseconds: 650);

  /// How long the ripple takes to fade once the press ends: 200 ms.
  static const Duration fade = Duration(milliseconds: 200);

  /// The curve the ripple grows on.
  static const Curve growCurve = Curves.easeOutQuint;

  /// Called whenever what is drawn changed.
  final VoidCallback onChanged;

  final AnimationController _grow;
  final AnimationController _alpha;
  String? _hovered;
  String? _pressed;
  Offset _origin = Offset.zero;

  /// The section whose action the mouse is over, or null.
  String? get hovered => _hovered;

  /// The press drawn now: the section, where it went down (content
  /// coordinates), how far it has grown (0 to 1, eased) and its alpha (0 to
  /// 1); null while none is.
  ({String sectionId, Offset origin, double grown, double alpha})? get press =>
      switch (_pressed) {
        final section? when _alpha.value > 0 => (
          sectionId: section,
          origin: _origin,
          grown: growCurve.transform(_grow.value),
          alpha: _alpha.value,
        ),
        _ => null,
      };

  /// The mouse is over the action of [sectionId], or over none.
  void hover(String? sectionId) {
    if (_hovered == sectionId) return;
    _hovered = sectionId;
    onChanged();
  }

  /// A press went down at [origin] (content coordinates) on the action of
  /// [sectionId].
  void pressDown(String sectionId, Offset origin) {
    _pressed = sectionId;
    _origin = origin;
    _alpha.value = 1;
    _grow.forward(from: 0).ignore();
    onChanged();
  }

  /// The press ended (up or cancel): the ripple fades.
  void release() {
    if (_pressed == null) return;
    _alpha.reverse().ignore();
  }

  /// Frees the controllers.
  void dispose() {
    _grow.dispose();
    _alpha.dispose();
  }
}
