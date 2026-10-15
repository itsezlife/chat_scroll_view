import 'dart:async';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_atlas_layout.dart';
import 'package:flutter/foundation.dart';

/// Starts a timer that calls [callback] once after [delay]. The default is
/// `Timer.new`; tests inject `ManualRetentionTimers.start`.
typedef RetentionTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// One claim on resident atlas pages, released exactly once.
///
/// Returned by [GlyphPageResidency.hold] (one page) and
/// [GlyphPageResidency.holdAll] (every page). A hold is a count, never pixels:
/// whoever has one asks the residency for the image when it draws, because the
/// image can go away under memory pressure while the count stays.
final class GlyphPageHold {
  GlyphPageHold._(this._onRelease);

  void Function()? _onRelease;

  /// Whether [release] was called.
  bool get isReleased => _onRelease == null;

  /// Gives the claim back. A second call does nothing, so a count is never
  /// taken from someone else's claim.
  void release() {
    final onRelease = _onRelease;
    _onRelease = null;
    onRelease?.call();
  }
}

/// The resident page images of a glyph atlas and the rules for how long they
/// stay: reference counts per page, a retention time-to-live, and release on
/// memory pressure.
///
/// ## Who keeps a page
///
/// A page is **pinned** while at least one hold covers it: a [hold] per leaf
/// binding (the page its glyph is on) and a [holdAll] for as long as the panel
/// is open, because every page must be resident then, not only the ones in
/// view. Pinned pages stay for ever, so the cache's keep-until-pressure rule
/// holds while a surface is using them.
///
/// ## Retention
///
/// The moment a page is no longer pinned (the panel closed and no binding is
/// left on it) a timer of [retention] starts. A new hold within it cancels the
/// timer, so reopening within the retention needs no reload; when it elapses
/// the page image is released. This is the time-to-live layered on top of
/// keep-until-pressure: it bounds idle memory, and a host sets it.
///
/// ## Memory pressure
///
/// [memoryPressure] releases every page at once, pinned or not: the system
/// asked for memory back and a surface repaints a placeholder until the page
/// is loaded again. Hold counts are untouched, so holds released later still
/// balance. Released pages are announced to [addReleaseListener].
///
/// The residency owns the images it was given: it disposes them on release and
/// on [dispose]. It does not know where pages come from or how they are
/// reloaded; the atlas does.
///
/// Counts live apart from images on purpose. A count tied to the image, or
/// looked up by key when it is given back, would be lost or misapplied when
/// the image is released first; that is the defect that evicting a cache entry
/// under a live binding used to cause.
final class GlyphPageResidency {
  /// Creates a residency that releases unpinned pages after [retention].
  ///
  /// [memoryPressure] is notified when the platform wants memory back
  /// (`SystemMemoryPressure` in production). [startTimer] is for tests.
  GlyphPageResidency({
    this.retention = defaultRetention,
    Listenable? memoryPressure,
    RetentionTimerFactory startTimer = Timer.new,
  }) : assert(!retention.isNegative, 'retention must not be negative'),
       _memoryPressure = memoryPressure,
       _startTimer = startTimer {
    memoryPressure?.addListener(releaseAll);
  }

  /// How long unpinned pages stay resident unless the host says otherwise.
  static const Duration defaultRetention = Duration(seconds: 60);

  /// How long a page stays resident after nothing pins it.
  final Duration retention;

  final Listenable? _memoryPressure;
  final RetentionTimerFactory _startTimer;

  final Map<int, Image> _images = <int, Image>{};
  final Map<int, int> _holds = <int, int>{};
  final Map<int, Timer> _expiry = <int, Timer>{};
  final List<ValueChanged<int>> _releaseListeners = <ValueChanged<int>>[];
  int _openHolds = 0;
  bool _disposed = false;

  /// Indices of the resident pages, ascending.
  List<int> get residentPages => _images.keys.toList()..sort();

  /// Raw bytes of the resident pages (RGBA8888, mip levels excluded).
  int get residentBytes => _images.values.fold<int>(
    0,
    (sum, image) =>
        sum + image.width * image.height * GlyphAtlasLayout.bytesPerPixel,
  );

  /// Whether page [pageIndex] is resident.
  bool isResident(int pageIndex) => _images.containsKey(pageIndex);

  /// The image of page [pageIndex], or null when it is not resident. Read it
  /// when drawing and never keep it: it can be released at any time.
  Image? imageOf(int pageIndex) => _images[pageIndex];

  /// How many holds cover page [pageIndex]: those on the page itself plus
  /// every [holdAll].
  int holdCount(int pageIndex) => (_holds[pageIndex] ?? 0) + _openHolds;

  /// Takes ownership of [image] as page [pageIndex], replacing (and
  /// disposing) any image already there. Disposed at once after [dispose].
  void admit(int pageIndex, Image image) {
    if (_disposed) {
      image.dispose();
      return;
    }
    _images.remove(pageIndex)?.dispose();
    _images[pageIndex] = image;
    _startExpiryIfUnpinned(pageIndex);
  }

  /// Pins page [pageIndex], resident or not, until the hold is released.
  GlyphPageHold hold(int pageIndex) {
    if (_disposed) return GlyphPageHold._(null);
    _holds[pageIndex] = (_holds[pageIndex] ?? 0) + 1;
    _expiry.remove(pageIndex)?.cancel();
    return GlyphPageHold._(() => _releaseHold(pageIndex));
  }

  /// Pins every page until the hold is released: the panel is open.
  GlyphPageHold holdAll() {
    if (_disposed) return GlyphPageHold._(null);
    _openHolds++;
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _expiry.clear();
    return GlyphPageHold._(_releaseOpenHold);
  }

  /// Calls [listener] with the index of each page that is released.
  void addReleaseListener(ValueChanged<int> listener) =>
      _releaseListeners.add(listener);

  /// Removes a listener added with [addReleaseListener].
  void removeReleaseListener(ValueChanged<int> listener) =>
      _releaseListeners.remove(listener);

  /// Disposes every resident image now, whatever holds there are.
  void releaseAll() {
    if (_disposed) return;
    for (final page in residentPages) {
      _release(page);
    }
  }

  /// Disposes the images, cancels the timers and stops listening. Holds that
  /// are released afterwards do nothing. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _memoryPressure?.removeListener(releaseAll);
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _expiry.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _holds.clear();
    _releaseListeners.clear();
  }

  bool _isPinned(int pageIndex) => holdCount(pageIndex) > 0;

  void _releaseHold(int pageIndex) {
    if (_disposed) return;
    final left = (_holds[pageIndex] ?? 0) - 1;
    if (left > 0) {
      _holds[pageIndex] = left;
      return;
    }
    _holds.remove(pageIndex);
    _startExpiryIfUnpinned(pageIndex);
  }

  void _releaseOpenHold() {
    if (_disposed) return;
    _openHolds--;
    if (_openHolds > 0) return;
    for (final page in _images.keys.toList()) {
      _startExpiryIfUnpinned(page);
    }
  }

  void _startExpiryIfUnpinned(int pageIndex) {
    if (!_images.containsKey(pageIndex) ||
        _isPinned(pageIndex) ||
        _expiry.containsKey(pageIndex)) {
      return;
    }
    _expiry[pageIndex] = _startTimer(retention, () {
      _expiry.remove(pageIndex);
      if (!_isPinned(pageIndex)) _release(pageIndex);
    });
  }

  void _release(int pageIndex) {
    _expiry.remove(pageIndex)?.cancel();
    final image = _images.remove(pageIndex);
    if (image == null) return;
    image.dispose();
    for (final listener in List<ValueChanged<int>>.of(_releaseListeners)) {
      listener(pageIndex);
    }
  }
}
