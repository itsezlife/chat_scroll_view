import 'dart:math' as math;

import 'package:listen/listen.dart';

/// What the sticky header reads of the catalogue's scroll.
///
/// The catalogue's controller is adapted to it by the page; a test supplies
/// its own. Offsets are in logical pixels from the start of the content.
abstract interface class CatalogScrollMetrics {
  /// The absolute scroll offset, as last written.
  double get offset;

  /// The largest offset the layout allows, or 0 before it is known.
  double get maxScrollExtent;

  /// Whether the catalogue is moving by itself toward a section.
  bool get isSectionJumpActive;
}

/// The geometry of a catalogue page's **sticky header**: the strip that slides
/// away as the user reads on and returns as they read back, and the search
/// field that is the first thing in the content, scrolls away with it and pins
/// to the top once search opens.
///
/// ## What it owns
///
/// The four values the page paints from: [stripOffset] (how far the strip is
/// slid up, `0` to `-stripExtent`), [searchOffset] (the field's own offset from
/// the top of the page), and the two hairlines [stripShadow] and
/// [searchShadow] that show while content passes under the header. All of it is
/// derived from the catalogue's scroll and from three facts the page tells it
/// (search open, strip shown, strip extent), by the rules below.
///
/// **Does not own** any widget, the animation of a reveal (the page animates
/// [stripOffset] through [setStripOffset]), the catalogue's padding, or the
/// scroll itself.
///
/// ## Rules
///
/// * **Idle browse.** The field sits in the [searchExtent] band under the
///   strip and scrolls with the content: `searchOffset = stripExtent − offset`,
///   never above `−searchExtent`.
/// * **Strip.** While the strip shows, reading on hides it by the distance
///   scrolled and reading back brings it back at once, but not while the
///   field's band is still under it (the page is within `searchExtent` of its
///   start) and never during a jump to a section. At the very top it is fully
///   shown.
/// * **Search open.** The field is pinned (`searchOffset = 0`), the strip is
///   not shown, and the field's hairline shows exactly while content has
///   scrolled under it.
/// * **Strip hairline.** Shows while any of the strip is on screen and the
///   strip's lower edge is over content: the field's band has left, or the
///   field's lower edge is above the strip's. A strip that has slid away
///   leaves no hairline at the page's edge.
///
/// A mutable accumulator by role: [scrolled] adds to a position that persists
/// between calls, unlike the immutable activities it consumes.
final class CatalogStickyHeader {
  /// A header whose strip is [stripExtent] tall and whose field is
  /// [searchExtent] tall; an extent of 0 says there is none of that part.
  CatalogStickyHeader({required this.stripExtent, required this.searchExtent});

  /// Height of the strip, or 0 for a page without one.
  final double stripExtent;

  /// Height of the field's band, or 0 for a page that places none.
  final double searchExtent;

  final _stripOffset = ValueNotifier<double>(0);
  final _searchOffset = ValueNotifier<double>(0);
  final _stripShadow = ValueNotifier<bool>(false);
  final _searchShadow = ValueNotifier<bool>(false);
  var _searchOpen = false;
  var _stripShown = true;
  var _disposed = false;

  /// How far the strip is slid up: `0` shown, `-stripExtent` gone.
  ValueListenable<double> get stripOffset => _stripOffset;

  /// The field's offset from the top of the page.
  ValueListenable<double> get searchOffset => _searchOffset;

  /// Whether the hairline under the strip shows.
  ValueListenable<bool> get stripShadow => _stripShadow;

  /// Whether the hairline under the field shows.
  ValueListenable<bool> get searchShadow => _searchShadow;

  // How far below the strip's lower edge the hairline looks for the field.
  static const double _shadowProbe = 2;

  bool get _hasStrip => stripExtent > 0;

  /// Tells the header whether search is open and whether the strip is part of
  /// the page now (it is not while search is open or results show), and
  /// recomputes from [metrics].
  void configure({
    required bool searchOpen,
    required bool stripShown,
    required CatalogScrollMetrics metrics,
  }) {
    if (_disposed) return;
    _searchOpen = searchOpen;
    _stripShown = stripShown;
    sync(metrics);
  }

  /// Recomputes the field's offset and both hairlines from [metrics]: call it
  /// whenever the catalogue's offset changed, also when it moved by itself.
  void sync(CatalogScrollMetrics metrics) {
    if (_disposed) return;
    final offset = _geometryOffset(metrics);
    if (_searchOpen) {
      _searchOffset.value = 0;
      _searchShadow.value = _effectiveOffset(metrics) > 0.5;
      _stripShadow.value = false;
      return;
    }
    if (searchExtent <= 0 && !_hasStrip) return;

    final top = stripExtent;
    final ty = math.max(top - offset, -searchExtent);
    _searchOffset.value = ty;
    _searchShadow.value = false;

    final stripBottom = stripExtent + _stripOffset.value;
    final spacerBottom = ty + searchExtent;
    final spacerGone = offset >= top + searchExtent - 0.5;
    _stripShadow.value =
        _hasStrip &&
        _stripShown &&
        stripBottom > 0 &&
        (spacerGone || spacerBottom < stripBottom + _shadowProbe);
  }

  /// The catalogue scrolled by [delta] (positive: reading on); hides or reveals
  /// the strip by it, then recomputes from [metrics].
  void scrolled(double delta, CatalogScrollMetrics metrics) {
    if (_disposed) return;
    _hideOrReveal(delta, metrics);
    sync(metrics);
  }

  /// Slides the strip to [offset] (clamped to `0` to `-stripExtent`): the page
  /// calls it for every frame of a reveal.
  void setStripOffset(double offset, CatalogScrollMetrics metrics) {
    if (_disposed) return;
    final next = offset.clamp(-stripExtent, 0.0);
    if (next == _stripOffset.value) return;
    _stripOffset.value = next;
    sync(metrics);
  }

  /// Stops notifying. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stripOffset.dispose();
    _searchOffset.dispose();
    _stripShadow.dispose();
    _searchShadow.dispose();
  }

  void _hideOrReveal(double delta, CatalogScrollMetrics metrics) {
    if (!_hasStrip ||
        !_stripShown ||
        metrics.isSectionJumpActive ||
        delta == 0) {
      return;
    }
    final offset = _effectiveOffset(metrics);
    if (delta > 0) {
      // At the very top the strip is always whole.
      if (offset <= 0) {
        _stripOffset.value = 0;
        return;
      }
      // Reading on while the field's band is still within reach keeps the
      // strip: the field scrolls away under it first.
      if (offset <= searchExtent) return;
    }
    final hidden = (_stripOffset.value - delta).clamp(-stripExtent, 0.0);
    if (hidden != _stripOffset.value) _stripOffset.value = hidden;
  }

  // The offset clamped to the range the layout allows: the catalogue notifies
  // before the viewport clamps a scroll, so raw offsets overshoot.
  double _effectiveOffset(CatalogScrollMetrics metrics) {
    final raw = metrics.offset;
    final max = metrics.maxScrollExtent;
    if (max <= 0) return math.max(raw, 0);
    return raw.clamp(0.0, max);
  }

  // During a section jump the maximum may be stale (a far jump teleports
  // beyond what was laid out), so only the lower bound applies.
  double _geometryOffset(CatalogScrollMetrics metrics) =>
      metrics.isSectionJumpActive
      ? math.max(metrics.offset, 0)
      : _effectiveOffset(metrics);
}
