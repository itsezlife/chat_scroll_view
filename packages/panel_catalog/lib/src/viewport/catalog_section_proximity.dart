import 'package:panel_catalog/src/model/catalog_section.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_scroll_events.dart';

/// Which section edges are near the viewport, and which just became so.
///
/// Pure bookkeeping over the section bands: it knows no render object, no
/// controller and no clock. The render object asks [update] after every change
/// of offset or layout and publishes what it reports.
///
/// An edge is near when it lies inside the window the caller names (the
/// viewport band widened by the near extent). The first and last band in the
/// window are found by binary search over the ascending bands, and nothing is
/// computed while the window covers the same edges as the last call and no
/// section changed, so a frame of scrolling costs two searches per edge kind
/// when no edge moved.
final class CatalogSectionProximity {
  // Near edges as of the last evaluation. A record carries the leaf count for
  // the trailing edge only, so a section that grew reads as a new end while
  // its start does not.
  Set<(String, CatalogSectionEdge, int)> _near = {};
  Set<(String, CatalogSectionEdge, int)> _scratch = {};

  // The ranges of bands whose leading / trailing edge was inside the window at
  // the last evaluation, and whether the sections changed since.
  var _lo = 0;
  var _hi = 0;
  var _trailingLo = 0;
  var _trailingHi = 0;
  var _dirty = true;

  /// The sections or their geometry changed: evaluate again even if the same
  /// bands are in the window.
  void invalidate() => _dirty = true;

  /// Forgets what was near, so the next [update] announces every near edge
  /// again. For a viewport that leaves the tree and comes back.
  void reset() {
    _near = {};
    _scratch = {};
    _lo = _hi = _trailingLo = _trailingHi = 0;
    _dirty = true;
  }

  /// Reports through [onNear] the edges inside `[windowTop, windowBottom]` that
  /// were not near at the last call, in section order, leading before
  /// trailing.
  ///
  /// [bands] and [sections] are the same length and aligned.
  void update({
    required List<CatalogSectionBand> bands,
    required List<CatalogSection> sections,
    required double windowTop,
    required double windowBottom,
    required void Function(String sectionId, CatalogSectionEdge edge) onNear,
  }) {
    final lo = _firstWhere(bands, (b) => b.top >= windowTop);
    final hi = _firstWhere(bands, (b) => b.top > windowBottom);
    final trailingLo = _firstWhere(bands, (b) => b.bottom >= windowTop);
    final trailingHi = _firstWhere(bands, (b) => b.bottom > windowBottom);
    if (!_dirty &&
        lo == _lo &&
        hi == _hi &&
        trailingLo == _trailingLo &&
        trailingHi == _trailingHi) {
      return;
    }
    _dirty = false;
    _lo = lo;
    _hi = hi;
    _trailingLo = trailingLo;
    _trailingHi = trailingHi;

    final next = _scratch..clear();
    final first = lo < trailingLo ? lo : trailingLo;
    final last = hi > trailingHi ? hi : trailingHi;
    final announce = <(String, CatalogSectionEdge, int)>[];
    for (var i = first; i < last; i++) {
      final id = sections[i].id;
      if (i >= lo && i < hi) {
        final key = (id, CatalogSectionEdge.leading, 0);
        next.add(key);
        if (!_near.contains(key)) announce.add(key);
      }
      if (i >= trailingLo && i < trailingHi) {
        final key = (
          id,
          CatalogSectionEdge.trailing,
          sections[i].leaves.length,
        );
        next.add(key);
        if (!_near.contains(key)) announce.add(key);
      }
    }
    _scratch = _near;
    _near = next;
    for (final (id, edge, _) in announce) {
      onNear(id, edge);
    }
  }

  // First index whose band satisfies [test], bands being ordered so that it
  // holds from there on; [bands].length when none does.
  static int _firstWhere(
    List<CatalogSectionBand> bands,
    bool Function(CatalogSectionBand band) test,
  ) {
    var lo = 0;
    var hi = bands.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (test(bands[mid])) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }
}
