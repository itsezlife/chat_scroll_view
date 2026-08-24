import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_scroll_events.dart';

/// Extent-scroll position for [PanelCatalogViewport].
///
/// Owns the absolute content [offset] (logical pixels from the catalog top)
/// and the host navigation entry points ([jumpTo], [scrollBy],
/// [animateTo], [jumpToSection]). This is an **extent** model: offset is a
/// content-y scroll position against a known content height, not an id-relative
/// anchor.
///
/// The bound viewport owns range validity. After each navigation notify it
/// clamps writes to:
///
/// ```text
/// [0, max(0, contentExtent − viewportHeight)]
/// ```
///
/// via [correctOffset] (silent — jump/scroll listeners are not re-fired).
/// Until that correction runs, [offset] MAY briefly sit outside the valid
/// range (e.g. [jumpTo] past the end before the first layout knows
/// `contentExtent`).
///
/// ## Listeners
///
/// Typed [addJumpListener] / [addScrollByListener] and sealed
/// [addScrollListener] / [PanelCatalogScrollEvent]. Same callback twice is a
/// no-op (dedup-on-add). Dispatch iterates a snapshot so listeners MAY
/// add/remove during notify without concurrent modification.
///
/// Jump and scroll-by are separate channels: a [jumpTo] does **not** fire
/// scroll-by listeners and vice versa. [applyOffset] and [correctOffset] do
/// not re-fire jump/scroll-by; [applyOffset] emits
/// [PanelCatalogOffsetChanged] for shell chrome that must track programmatic
/// motion ticks.
///
/// ## Section jump
///
/// [jumpToSection] requests a category/section landing under
/// [PanelCatalogViewport.headerLandingInset] when set, otherwise
/// [PanelCatalogViewport.padding.top]. The bound viewport chooses near-path
/// smooth scroll vs far-path stitch from [isNearPathSectionJump] (flat-row
/// distance gate [kFarPathDistanceGateFactor] plus attached-header shortcut).
///
/// While a jump owns scroll, [isSectionJumpActive] is `true`. Additional
/// [jumpToSection] calls during that window are silent no-ops at the controller
/// (in-flight [Future] returned; section-jump listeners not re-fired). Hosts
/// SHOULD gate strip/category re-taps the same way so selection and target
/// stay aligned. User drag cancels in-flight near scroll or far-path stitch;
/// only then may a new [jumpToSection] start.
///
/// The viewport does **not** dispose this controller. After [dispose],
/// mutating entry points are silent no-ops and listeners are cleared.
final class PanelCatalogController {
  double _offset = 0;
  var _disposed = false;

  /// Absolute content offset in logical pixels (catalog top = `0`).
  ///
  /// Increasing [offset] reveals content further down the catalog. Read is
  /// always available; validity relative to the current viewport is enforced
  /// by the bound render object after navigation / layout.
  double get offset => _offset;

  /// Whether [dispose] has been called.
  ///
  /// Useful for hosts that share a controller across a short-lived overlay
  /// and need to gate late async work.
  bool get isDisposed => _disposed;

  /// Whether a programmatic [jumpToSection] owns scroll motion.
  ///
  /// `true` from path selection through near-path animate or far-path stitch
  /// until the jump completes or user drag cancels it. Hosts use this to
  /// suppress category-strip scroll sync and to ignore strip re-taps while
  /// motion is in flight. Becomes `false` on completion or drag cancel — not
  /// when a superseding [jumpToSection] arrives (those are ignored while
  /// active).
  bool get isSectionJumpActive => _sectionJumpActive;

  // --- Scroll events --------------------------------------------------------

  final _scrollListeners = <ValueChanged<PanelCatalogScrollEvent>>[];

  /// Subscribe to sealed scroll-side events from the bound viewport.
  ///
  /// Adding the same callback twice is a no-op. Unknown removals are no-ops.
  void addScrollListener(ValueChanged<PanelCatalogScrollEvent> callback) {
    if (_scrollListeners.contains(callback)) return;
    _scrollListeners.add(callback);
  }

  /// Unsubscribe from [addScrollListener]. Unknown [callback] is a no-op.
  void removeScrollListener(ValueChanged<PanelCatalogScrollEvent> callback) =>
      _scrollListeners.remove(callback);

  /// Viewport-only emitter. Iterates a snapshot — a listener removing itself
  /// or another listener during dispatch is safe.
  @internal
  void notifyScrollEvent(PanelCatalogScrollEvent event) => _emitScroll(event);

  void _emitScroll(PanelCatalogScrollEvent event) {
    if (_disposed) return;
    for (final cb in List<ValueChanged<PanelCatalogScrollEvent>>.of(
      _scrollListeners,
      growable: false,
    )) {
      cb(event);
    }
  }

  // --- Jump -----------------------------------------------------------------

  final _jumpListeners = <ValueChanged<double>>[];

  /// Subscribe to [jumpTo] events. Callback receives the **requested** offset
  /// (pre-clamp).
  ///
  /// Adding the same callback twice is a no-op. Unknown removals are no-ops.
  void addJumpListener(ValueChanged<double> callback) {
    if (_jumpListeners.contains(callback)) return;
    _jumpListeners.add(callback);
  }

  /// Unsubscribe from [jumpTo] events. Unknown [callback] is a no-op.
  void removeJumpListener(ValueChanged<double> callback) =>
      _jumpListeners.remove(callback);

  /// Jumps to [pixels] and notifies jump listeners.
  ///
  /// Same-value calls (`pixels == offset`) are a silent no-op — listeners are
  /// not notified. After dispose, this is a silent no-op.
  ///
  /// The viewport clamps after notify via [correctOffset]; [offset] MAY
  /// briefly exceed the valid range until that correction runs. Listeners
  /// that read [offset] inside the callback see the requested value, not
  /// necessarily the post-clamp value.
  void jumpTo(double pixels) {
    if (_disposed) return;
    if (_offset == pixels) return;
    final delta = pixels - _offset;
    _offset = pixels;
    _emitScroll(PanelCatalogProgrammaticJump(pixels));
    _emitScroll(PanelCatalogOffsetChanged(pixels, delta));
    for (final cb in List<ValueChanged<double>>.of(
      _jumpListeners,
      growable: false,
    )) {
      cb(pixels);
    }
  }

  // --- Smooth scroll --------------------------------------------------------

  final _animateToListeners = <VoidCallback>[];
  (double target, Duration duration, Curve curve, Completer<void> completer)?
  _pendingAnimateTo;

  /// Pending [animateTo] request while the viewport has not yet consumed it.
  (double target, Duration duration, Curve curve, Completer<void> completer)?
  get pendingAnimateTo => _pendingAnimateTo;

  /// Subscribe to [animateTo] requests. The bound viewport runs near-path
  /// motion and completes the returned [Future].
  void addAnimateToListener(VoidCallback callback) {
    if (_animateToListeners.contains(callback)) return;
    _animateToListeners.add(callback);
  }

  /// Unsubscribe from [animateTo] events. Unknown [callback] is a no-op.
  void removeAnimateToListener(VoidCallback callback) =>
      _animateToListeners.remove(callback);

  /// Smoothly scrolls to absolute [pixels] (220ms decelerate by default).
  ///
  /// Same-value and post-dispose calls complete immediately without scrolling.
  /// Cancels any in-flight [animateTo] request. User drag cancels viewport
  /// motion and completes the pending future without error.
  Future<void> animateTo(
    double pixels, {
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.decelerate,
  }) {
    if (_disposed) return Future.value();
    if ((_offset - pixels).abs() < 0.5) return Future.value();
    _completePendingAnimateTo();

    final completer = Completer<void>();
    _pendingAnimateTo = (pixels, duration, curve, completer);
    if (_animateToListeners.isEmpty) {
      jumpTo(pixels);
      _completePendingAnimateTo();
      return completer.future;
    }
    for (final cb in List<VoidCallback>.of(
      _animateToListeners,
      growable: false,
    )) {
      cb();
    }
    return completer.future;
  }

  /// Completes the pending [animateTo] future. Viewport-only.
  void completePendingAnimateTo() {
    final pending = _pendingAnimateTo;
    if (pending == null) return;
    _pendingAnimateTo = null;
    if (!pending.$4.isCompleted) {
      pending.$4.complete();
    }
  }

  void _completePendingAnimateTo() => completePendingAnimateTo();

  // --- Scroll-by ------------------------------------------------------------

  final _scrollByListeners = <ValueChanged<double>>[];

  /// Subscribe to [scrollBy] events. Callback receives the pixel [delta]
  /// passed to [scrollBy] (not the resulting absolute offset).
  ///
  /// Adding the same callback twice is a no-op.
  void addScrollByListener(ValueChanged<double> callback) {
    if (_scrollByListeners.contains(callback)) return;
    _scrollByListeners.add(callback);
  }

  /// Unsubscribe from [scrollBy] events. Unknown [callback] is a no-op.
  void removeScrollByListener(ValueChanged<double> callback) =>
      _scrollByListeners.remove(callback);

  /// Adds [delta] to [offset] (positive reveals content below).
  ///
  /// **`scrollBy(0)` is a silent no-op** — listeners are not notified.
  /// After dispose, this is a silent no-op.
  ///
  /// After notify, the viewport clamps via [correctOffset]. Drag and wheel
  /// input on the viewport call this path.
  void scrollBy(double delta) {
    if (_disposed) return;
    if (delta == 0) return;
    _offset += delta;
    _emitScroll(PanelCatalogViewportScrolled(delta));
    _emitScroll(PanelCatalogOffsetChanged(_offset, delta));
    for (final cb in List<ValueChanged<double>>.of(
      _scrollByListeners,
      growable: false,
    )) {
      cb(delta);
    }
  }

  // --- Section jump ---------------------------------------------------------

  final _sectionJumpListeners = <ValueChanged<int>>[];
  (int sectionIndex, Completer<void> completer)? _pendingSectionJump;
  var _sectionJumpActive = false;

  /// Subscribe to [jumpToSection] requests. Callback receives the section
  /// index (`0..sectionCount−1`).
  ///
  /// The bound viewport handles path selection and completes the returned
  /// [Future]. Adding the same callback twice is a no-op.
  void addSectionJumpListener(ValueChanged<int> callback) {
    if (_sectionJumpListeners.contains(callback)) return;
    _sectionJumpListeners.add(callback);
  }

  /// Unsubscribe from [jumpToSection] events. Unknown [callback] is a no-op.
  void removeSectionJumpListener(ValueChanged<int> callback) =>
      _sectionJumpListeners.remove(callback);

  /// Scrolls so [sectionIndex]'s header lands under the viewport top inset.
  ///
  /// Out-of-range [sectionIndex] completes immediately without scrolling or
  /// toggling [isSectionJumpActive].
  ///
  /// **Re-entry:** while [isSectionJumpActive] is `true`, this is a silent
  /// no-op — returns the in-flight [Future], does not notify section-jump
  /// listeners, and does not retarget motion. User drag on the viewport
  /// cancels the active jump first; the next call after cancel starts fresh.
  ///
  /// Path selection (near smooth scroll vs far stitch) is viewport-owned via
  /// [isNearPathSectionJump].
  ///
  /// After [dispose], returns an immediately-completed future.
  Future<void> jumpToSection(int sectionIndex) {
    if (_disposed) return Future.value();
    if (_sectionJumpActive) {
      return _pendingSectionJump?.$2.future ?? Future.value();
    }

    final completer = Completer<void>();
    _pendingSectionJump = (sectionIndex, completer);
    for (final cb in List<ValueChanged<int>>.of(
      _sectionJumpListeners,
      growable: false,
    )) {
      cb(sectionIndex);
    }
    return completer.future;
  }

  /// Called by the bound viewport when section-jump activity starts or ends.
  ///
  /// Hosts MUST NOT call this — use [isSectionJumpActive] read-only.
  void setSectionJumpActive(bool active) {
    if (_disposed) return;
    _sectionJumpActive = active;
  }

  /// Completes the pending [jumpToSection] future when [sectionIndex] matches
  /// the pending request (or any pending request when [sectionIndex] is null).
  ///
  /// Viewport-only. Unknown indices are no-ops.
  void completePendingSectionJump({int? sectionIndex}) {
    final pending = _pendingSectionJump;
    if (pending == null) return;
    if (sectionIndex != null && pending.$1 != sectionIndex) return;
    _pendingSectionJump = null;
    if (!pending.$2.isCompleted) {
      pending.$2.complete();
    }
  }

  void _completePendingSectionJump() {
    completePendingSectionJump();
  }

  /// Pending section jump, if any — used when attaching after an early request.
  (int sectionIndex, Completer<void> completer)? get pendingSectionJump =>
      _pendingSectionJump;

  // --- Viewport offset writes -----------------------------------------------

  /// Writes [pixels] and emits [PanelCatalogOffsetChanged].
  ///
  /// Viewport-only: near-path section ticks, [animateTo], and far-path stitch
  /// teleports use this instead of [correctOffset] so shell chrome can react
  /// during programmatic motion. Does not notify jump/scroll-by listeners.
  void applyOffset(double pixels) {
    if (_disposed) return;
    if (_offset == pixels) return;
    final delta = pixels - _offset;
    _offset = pixels;
    _emitScroll(PanelCatalogOffsetChanged(pixels, delta));
  }

  /// Silently writes [pixels] without notifying listeners.
  ///
  /// Owned by the bound viewport’s range clamp. Navigation that must notify
  /// listeners uses [jumpTo] / [scrollBy] / [applyOffset] instead.
  ///
  /// Same-value and post-dispose calls are silent no-ops.
  void correctOffset(double pixels) {
    if (_disposed) return;
    if (_offset == pixels) return;
    _offset = pixels;
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Drops all listeners and marks the controller disposed. Idempotent.
  ///
  /// After dispose, [jumpTo] / [scrollBy] / [animateTo] / [jumpToSection] /
  /// [correctOffset] / [applyOffset] are silent no-ops. Safe to call more than
  /// once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _completePendingSectionJump();
    _completePendingAnimateTo();
    _sectionJumpActive = false;
    _jumpListeners.clear();
    _scrollByListeners.clear();
    _sectionJumpListeners.clear();
    _animateToListeners.clear();
    _scrollListeners.clear();
  }
}
