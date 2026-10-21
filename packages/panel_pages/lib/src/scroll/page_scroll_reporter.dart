import 'dart:async';

import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_shell/panel_shell.dart';

/// Turns the catalogue's scroll events into the typed [PageScrollActivity] a
/// page reports to the shell.
///
/// The shell derives the bottom bar from these values alone and reads no
/// clock, so the mapping is the whole rule and lives here, in one place:
///
/// - A step of the catalogue (`PanelCatalogViewportScrolled`) is a
///   [PageScrollDrag], or a [PageScrollFling] between a fling's start and end.
///   A pointer-wheel step has no drag around it and is a drag step.
/// - The catalogue's own motion (a jump, an animation, a section jump) is
///   one [PageScrollJump] however many events announce it; the next one is
///   reported again once the catalogue came to rest or a finger took over.
///   Its offset ticks carry no deltas to the shell.
/// - Rest is [PageScrollIdle], reported when the viewport says it stopped
///   moving (one quiet frame after the last motion), at an end of the content
///   when [atEdge] says so.
///
/// Only the selected page's reports reach the bar; the page host drops the
/// others, so a reporter does not need to know whether its page is active.
final class PageScrollReporter {
  /// Starts reporting [events] through [report].
  ///
  /// [atEdge] is asked when the catalogue rests, to tell whether it rests at
  /// its start or its end.
  PageScrollReporter({
    required Stream<PanelCatalogScrollEvent> events,
    required void Function(PageScrollActivity activity) report,
    required bool Function() atEdge,
  }) : _report = report,
       _atEdge = atEdge {
    _subscription = events.listen(_onEvent);
  }

  late final StreamSubscription<PanelCatalogScrollEvent> _subscription;
  final void Function(PageScrollActivity activity) _report;
  final bool Function() _atEdge;

  var _flinging = false;
  var _jumping = false;
  var _disposed = false;

  void _onEvent(PanelCatalogScrollEvent event) {
    switch (event) {
      case PanelCatalogUserDragStart():
        _jumping = false;
      case PanelCatalogFlingStart():
        _flinging = true;
      case PanelCatalogFlingEnd():
        _flinging = false;
      case PanelCatalogViewportScrolled(:final delta):
        _report(_flinging ? PageScrollFling(delta) : PageScrollDrag(delta));
      case PanelCatalogProgrammaticJump() ||
          PanelCatalogAnimateStart() ||
          PanelCatalogSectionJumpStart():
        _startJump();
      case PanelCatalogScrollingChanged(scrolling: false):
        _jumping = false;
        _report(PageScrollIdle(atEdge: _atEdge()));
      default:
        break;
    }
  }

  void _startJump() {
    if (_jumping) return;
    _jumping = true;
    _report(const PageScrollJump());
  }

  /// Stops reporting.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
  }
}
