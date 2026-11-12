import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';

/// A content preview the host opened over the grid, as the grid draws it.
///
/// While one is open ([PanelCatalogViewport.leafPreview] is set) the grid
/// paints no press wash, no press scale and no hover wash, pinned or under
/// the mouse: a finger or a mouse moving over the cells under the preview
/// marks none of them. The cell whose content the preview shows ([shrunk])
/// is drawn smaller instead, at [shrunkScale], and follows the preview from
/// cell to cell; under `CatalogPreviewFeedback.hover` (a pointer) it keeps
/// the hover box instead, at its full size, and the box follows the preview.
///
/// The scale moves linearly at [scaleSpeed]: a cell that becomes [shrunk]
/// goes from where it is (its press scale, for the cell that was held) down
/// to [shrunkScale], and one that stops being it, or every one when the
/// preview closes, goes back up to 1 at the same pace.
@immutable
final class CatalogLeafPreview {
  /// A preview open over the grid; [shrunk] is the cell it shows, or null for
  /// a preview whose cell is not drawn smaller.
  const CatalogLeafPreview({this.shrunk});

  /// The cell whose content the preview shows, drawn at [shrunkScale]; null
  /// for none.
  final CatalogLeafHit? shrunk;

  /// The scale the previewed cell is drawn at.
  static const double shrunkScale = 0.8;

  /// How fast a cell's scale moves, per millisecond: from 1 to [shrunkScale]
  /// in 80 ms.
  static const double scaleSpeed = 1 / 400;

  @override
  bool operator ==(Object other) =>
      other is CatalogLeafPreview && other.shrunk == shrunk;

  @override
  int get hashCode => Object.hash(CatalogLeafPreview, shrunk);

  @override
  String toString() => 'CatalogLeafPreview(shrunk: $shrunk)';
}

/// The scales of the cells a [CatalogLeafPreview] shrinks or lets go, moved
/// toward their targets frame by frame.
///
/// Cells are keyed by their position (section id and index), as hits are.
/// A cell at 1 that is not the target is forgotten.
final class CatalogLeafPreviewScale {
  /// Moves the scales on frames of [vsync]'s tickers; [onChanged] asks for a
  /// paint.
  CatalogLeafPreviewScale({
    required TickerProvider vsync,
    required this.onChanged,
  }) : _vsync = vsync;

  final TickerProvider _vsync;

  /// Called whenever a scale moved.
  final VoidCallback onChanged;

  final _scales = <(String, int), double>{};
  (String, int)? _target;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// The scale [sectionId]'s cell [index] is drawn at, or null when it is
  /// not shrunk.
  double? scaleOf(String sectionId, int index) => _scales[(sectionId, index)];

  /// Shrinks [cell] and lets every other go; null lets them all go. A cell
  /// newly shrunk starts from [from] (the scale it is drawn at now).
  void shrink(CatalogLeafHit? cell, {double from = 1}) {
    final target = switch (cell) {
      final cell? => (cell.sectionId, cell.index),
      null => null,
    };
    if (target == _target) return;
    _target = target;
    if (target != null) _scales.putIfAbsent(target, () => from);
    _run();
  }

  void _run() {
    final ticker = _ticker ??= _vsync.createTicker(_tick);
    if (_settled) {
      ticker.stop();
      return;
    }
    if (!ticker.isActive) {
      _last = Duration.zero;
      ticker.start();
    }
    onChanged();
  }

  bool get _settled =>
      _scales.entries.every((entry) => entry.value == _targetOf(entry.key));

  double _targetOf((String, int) key) =>
      key == _target ? CatalogLeafPreview.shrunkScale : 1;

  void _tick(Duration elapsed) {
    final step =
        (elapsed - _last).inMicroseconds / 1000 * CatalogLeafPreview.scaleSpeed;
    _last = elapsed;
    for (final key in _scales.keys.toList()) {
      final target = _targetOf(key);
      final scale = _scales[key]!;
      final next = scale < target
          ? (scale + step).clamp(scale, target)
          : (scale - step).clamp(target, scale);
      if (next == 1 && key != _target) {
        _scales.remove(key);
      } else {
        _scales[key] = next;
      }
    }
    if (_settled) _ticker?.stop();
    onChanged();
  }

  /// Stops and forgets every scale. Idempotent.
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    _scales.clear();
    _target = null;
  }
}
