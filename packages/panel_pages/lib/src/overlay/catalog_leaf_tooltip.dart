import 'dart:async';
import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/overlay/chrome_overlay_scopes.dart';

/// The tooltip of a mouse resting on a cell: one line of text by the cursor,
/// in the nearest `Overlay`.
///
/// It follows the reference desktop client's tooltip, which is the same for
/// every widget there:
///
/// - Each time the mouse reaches another cell, a [delay] starts over. A
///   tooltip already up stays up meanwhile.
/// - When the delay ends, the text of the cell under the mouse then is shown
///   at the cursor as it is then; no text, or no cell, hides the tooltip.
/// - A tooltip up hides once the cursor is more than [moveTolerance] away
///   from where it showed (counted as `|dx| + |dy|`), or the mouse leaves.
///   Staying on the same cell after that brings nothing back: only another
///   cell starts the delay again.
/// - It shows and hides at once, with no fade, and takes no input.
///
/// The page owns one, feeds it what the viewport reports ([hover]) and tells
/// it when the mouse left ([leave]) or another surface opened ([hide]). What
/// the text is, it asks [textOf] when the delay ends.
final class CatalogLeafTooltip {
  /// A tooltip asking [textOf] for the text of a cell.
  CatalogLeafTooltip({
    required this.textOf,
    this.delay = defaultDelay,
    this.moveTolerance = defaultMoveTolerance,
  });

  /// How long the mouse rests on a cell before its tooltip shows.
  static const Duration defaultDelay = Duration(seconds: 1);

  /// How far the cursor may move from where the tooltip showed: the
  /// platform's drag start distance on the desktop.
  static const double defaultMoveTolerance = 10;

  /// The text for a cell, or null for none.
  final String? Function(CatalogLeafHit hit) textOf;

  /// How long the mouse rests on a cell before its tooltip shows.
  final Duration delay;

  /// How far the cursor may move from where the tooltip showed.
  final double moveTolerance;

  Timer? _timer;
  OverlayEntry? _entry;
  CatalogLeafHit? _hit;
  var _cursor = Offset.zero;
  Offset? _shownAt;
  var _disposed = false;

  /// Whether the tooltip is up.
  bool get isShown => _entry != null;

  /// Takes a report of the cell under the mouse ([hit], null for none) and
  /// of the cursor's global position, as the viewport gives it. [context] is
  /// where the tooltip takes its overlay, theme and direction from.
  void hover(CatalogLeafHit? hit, Offset globalPosition, BuildContext context) {
    if (_disposed) return;
    _cursor = globalPosition;
    if (_shownAt case final shown?) {
      final moved = globalPosition - shown;
      if (moved.dx.abs() + moved.dy.abs() > moveTolerance) _remove();
    }
    if (_sameCell(hit, _hit)) {
      _hit = hit;
      return;
    }
    _hit = hit;
    _timer?.cancel();
    _timer = hit == null ? null : Timer(delay, () => _show(context));
  }

  /// The mouse left the cells: the tooltip goes, and nothing waits to show.
  void leave() {
    _hit = null;
    hide();
  }

  /// Takes the tooltip down and stops waiting, for a surface that opened
  /// over the cells (a menu, a picker).
  void hide() {
    _timer?.cancel();
    _timer = null;
    _remove();
  }

  /// Takes the tooltip down for good. Idempotent.
  void dispose() {
    if (_disposed) return;
    hide();
    _disposed = true;
  }

  static bool _sameCell(CatalogLeafHit? a, CatalogLeafHit? b) =>
      a?.sectionId == b?.sectionId && a?.index == b?.index;

  void _show(BuildContext context) {
    _timer = null;
    final hit = _hit;
    final text = hit == null || !context.mounted ? null : textOf(hit);
    if (text == null || text.isEmpty) {
      _remove();
      return;
    }
    _remove();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final scopes = ChromeOverlayScopes.capture(context);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final cursor = overlayBox.globalToLocal(_cursor);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _shownAt = _cursor;
    _entry = OverlayEntry(
      builder: (context) => scopes.wrap(
        IgnorePointer(
          child: CustomSingleChildLayout(
            delegate: _TooltipLayout(cursor: cursor, rtl: rtl),
            child: _TooltipBox(text: text),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _remove() {
    _shownAt = null;
    _entry
      ?..remove()
      ..dispose();
    _entry = null;
  }
}

/// The box: a 1 px edge, 5 and 2 px of padding and 13 px text, rounded at 3,
/// with no shadow.
class _TooltipBox extends StatelessWidget {
  const _TooltipBox({required this.text});

  final String text;

  static const double _edge = 1;
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(5, 2, 5, 2);
  static const double _radius = 3;
  static const double _maxWidth = 800;
  static const int _maxLines = 12;

  @override
  Widget build(BuildContext context) {
    final panel = ChromeThemeScope.panelOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: panel.tooltipFill,
          border: Border.all(color: panel.tooltipBorder, width: _edge),
          borderRadius: BorderRadius.circular(_radius),
        ),
        child: Padding(
          padding: _padding + const EdgeInsets.all(_edge),
          child: Text(
            text,
            maxLines: _maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: panel.tooltipText,
              fontSize: 13,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the reference desktop client puts a tooltip: its top-left corner 20
/// px before and below the cursor (the corner mirrors in right-to-left text),
/// kept [_skip] px inside the window, and flipped above the cursor when it
/// would run past the bottom.
class _TooltipLayout extends SingleChildLayoutDelegate {
  _TooltipLayout({required this.cursor, required this.rtl});

  final Offset cursor;
  final bool rtl;

  static const Offset _shift = Offset(-20, 20);
  static const double _skip = 10;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final w = childSize.width;
    final h = childSize.height;
    var x = rtl ? cursor.dx - w - _shift.dx : cursor.dx + _shift.dx;
    var y = cursor.dy + _shift.dy;
    if (size.width - _skip < x + w && x + w > cursor.dx) {
      x = math.max(size.width - _skip - w, cursor.dx - w);
    }
    if (_skip > x && x < cursor.dx) x = math.min(cursor.dx, _skip);
    if (size.height - _skip < y + h) y = cursor.dy - h - _skip;
    if (y < 0) y = math.min(cursor.dy + _shift.dy, size.height - h);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_TooltipLayout oldDelegate) =>
      oldDelegate.cursor != cursor || oldDelegate.rtl != rtl;
}
