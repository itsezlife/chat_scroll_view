import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';
import 'package:panel_catalog/src/viewport/catalog_scroll_position.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_scroll_events.dart';

/// Extent-scroll controller for [PanelCatalogViewport], in the style of a
/// scroll controller: the viewport **attaches** one position and the host
/// commands it through this object.
///
/// The offset is an absolute content-y position (logical pixels from the
/// catalog top) against a known content height, not an id-relative anchor.
/// While a viewport is attached it owns the offset, clamps it to
///
/// ```text
/// [0, max(0, contentExtent − viewportHeight)]
/// ```
///
/// and answers [offset], [viewportExtent], [contentExtent] and
/// [maxScrollExtent] from its geometry. Until its first layout the offset MAY
/// sit outside that range (a [jumpTo] past the end waits for the extent).
///
/// ## Commands
///
/// [jumpTo], [scrollBy], [animateTo] and [jumpToSection] are forwarded to the
/// attached position. Same-value [jumpTo], `scrollBy(0)` and an [animateTo]
/// within half a pixel are silent no-ops.
///
/// ## Without a viewport
///
/// Commands never fail for lack of a viewport: the controller **commits** the
/// target and the viewport that attaches next starts from it, so a host can
/// position the catalog before it is mounted, or while a keep-alive page is
/// off-screen. [offset] reads the committed value and the motion events are
/// published as if the jump had happened.
///
/// - [jumpTo] and [scrollBy] move the committed offset.
/// - [animateTo] commits its target as a jump and completes at once: there is
///   nothing to animate.
/// - [jumpToSection] needs the projected layout, so it stays pending (the
///   returned future incomplete) and is applied when a viewport attaches; a
///   later call before then retargets the same pending request and returns the
///   same future.
/// - Detaching keeps the offset the viewport reached.
///
/// ## Events
///
/// [events] is the one typed Observable of what the viewport does: drag,
/// fling, programmatic jump, animate, section jump, offset ticks, the derived
/// scrolling / settled activity, and [PanelCatalogSectionNearViewport] for
/// pages that load sections as they come close. It replaces per-kind listener
/// channels. Same listener twice is a no-op; dispatch iterates a snapshot so
/// listeners MAY add or remove listeners while it runs.
///
/// ## Section jump
///
/// [jumpToSection] requests a category / section landing under
/// [PanelCatalogViewport.headerLandingInset] when set, otherwise
/// [PanelCatalogViewport.padding.top]. The bound viewport chooses near-path
/// smooth scroll vs far-path stitch from [isNearPathSectionJump] (flat-row
/// distance gate [kFarPathDistanceGateFactor] plus attached-header shortcut).
///
/// While a jump owns scroll, [isSectionJumpActive] is `true`. Additional
/// [jumpToSection] calls during that window are silent no-ops (the in-flight
/// [Future] is returned). Hosts SHOULD gate strip / category re-taps the same
/// way so selection and target stay aligned. User drag cancels an in-flight
/// near scroll or far-path stitch; only then may a new [jumpToSection] start.
///
/// The viewport does **not** dispose this controller. After [dispose], every
/// command is a silent no-op, pending futures are completed and listeners are
/// dropped.
final class PanelCatalogController {
  final _events = EventNotifier<PanelCatalogScrollEvent>();
  CatalogScrollPosition? _position;
  double _offset = 0;
  (int sectionIndex, Completer<void> completer)? _pendingSectionJump;
  var _disposed = false;

  /// What the viewport does, as one typed stream of synchronous events.
  ///
  /// See [PanelCatalogScrollEvent] for the catalogue. Events for commands
  /// given while no viewport is attached are published by the controller; for
  /// an attached viewport, by the viewport.
  EventObservable<PanelCatalogScrollEvent> get events => _events;

  /// Absolute content offset in logical pixels (catalog top = `0`).
  ///
  /// The attached viewport's offset, else the committed one. Increasing
  /// [offset] reveals content further down the catalog.
  double get offset => _position?.pixels ?? _offset;

  /// Height of the attached viewport; `0` before its first layout or when no
  /// viewport is attached.
  double get viewportExtent => _position?.viewportExtent ?? 0;

  /// Height of the projected catalog (padding included); `0` before the first
  /// layout or when no viewport is attached.
  double get contentExtent => _position?.contentExtent ?? 0;

  /// Largest valid [offset]: `max(0, contentExtent − viewportExtent)`; `0`
  /// before the first layout or when no viewport is attached.
  double get maxScrollExtent => _position?.maxScrollExtent ?? 0;

  /// Whether a viewport is attached.
  bool get hasPosition => _position != null;

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
  /// motion is in flight. Always `false` while no viewport is attached.
  bool get isSectionJumpActive => _position?.isSectionJumpActive ?? false;

  // --- Commands -------------------------------------------------------------

  /// Jumps to [pixels].
  ///
  /// Same-value calls (`pixels == offset`) and calls after dispose are silent
  /// no-ops. The attached viewport clamps after publishing: listeners that
  /// read [offset] inside the callback see the requested value, not
  /// necessarily the clamped one.
  void jumpTo(double pixels) {
    if (_disposed) return;
    final position = _position;
    if (position != null) {
      position.jumpTo(pixels);
      return;
    }
    if (_offset == pixels) return;
    final delta = pixels - _offset;
    _offset = pixels;
    _events
      ..publish(PanelCatalogProgrammaticJump(pixels))
      ..publish(PanelCatalogOffsetChanged(pixels, delta));
  }

  /// Adds [delta] to the offset (positive reveals content below).
  ///
  /// **`scrollBy(0)` is a silent no-op**, as is any call after dispose. The
  /// attached viewport clamps afterwards. Drag and wheel input on the viewport
  /// take this path.
  void scrollBy(double delta) {
    if (_disposed) return;
    if (delta == 0) return;
    final position = _position;
    if (position != null) {
      position.scrollBy(delta);
      return;
    }
    _offset += delta;
    _events
      ..publish(PanelCatalogViewportScrolled(delta))
      ..publish(PanelCatalogOffsetChanged(_offset, delta));
  }

  /// Smoothly scrolls to absolute [pixels] (220ms decelerate by default).
  ///
  /// Same-value (within half a pixel) and post-dispose calls complete
  /// immediately without scrolling. A new call cancels an in-flight one; user
  /// drag cancels viewport motion and completes the future without error.
  /// While no viewport is attached the target is committed as a [jumpTo].
  Future<void> animateTo(
    double pixels, {
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.decelerate,
  }) {
    if (_disposed) return Future.value();
    if ((offset - pixels).abs() < 0.5) return Future.value();
    final position = _position;
    if (position != null) {
      return position.animateTo(pixels, duration: duration, curve: curve);
    }
    jumpTo(pixels);
    return Future.value();
  }

  /// Scrolls so [sectionIndex]'s header lands under the viewport top inset.
  ///
  /// Out-of-range [sectionIndex] completes immediately without scrolling or
  /// toggling [isSectionJumpActive].
  ///
  /// **Re-entry:** while [isSectionJumpActive] is `true`, this is a silent
  /// no-op — returns the in-flight [Future], does not retarget motion. User
  /// drag on the viewport cancels the active jump first; the next call after
  /// cancel starts fresh.
  ///
  /// While no viewport is attached the request stays pending until one
  /// attaches (see class docs). Path selection (near smooth scroll vs far
  /// stitch) is viewport-owned via [isNearPathSectionJump].
  ///
  /// After [dispose], returns an immediately-completed future.
  Future<void> jumpToSection(int sectionIndex) {
    if (_disposed) return Future.value();
    final position = _position;
    if (position != null) return position.jumpToSection(sectionIndex);
    final pending = _pendingSectionJump;
    final completer = pending?.$2 ?? Completer<void>();
    _pendingSectionJump = (sectionIndex, completer);
    return completer.future;
  }

  // --- Viewport side --------------------------------------------------------

  /// Publishes [event] to [events] listeners. Viewport-only.
  @internal
  void publish(PanelCatalogScrollEvent event) => _events.publish(event);

  /// Binds [position] as the one attached viewport. Viewport-only.
  ///
  /// The viewport reads [offset] **before** attaching and starts from it, so
  /// a committed target is applied. A section jump committed while unbound is
  /// then handed to [position]. Replaces a previously attached position,
  /// which is forgotten without being told.
  @internal
  void attach(CatalogScrollPosition position) {
    if (_disposed) return;
    _position = position;
    final pending = _pendingSectionJump;
    if (pending == null) return;
    _pendingSectionJump = null;
    unawaited(
      position.jumpToSection(pending.$1).whenComplete(() {
        if (!pending.$2.isCompleted) pending.$2.complete();
      }),
    );
  }

  /// Unbinds [position] and keeps the offset it reached as the committed one.
  /// Viewport-only. Ignored when [position] is not the attached one.
  @internal
  void detach(CatalogScrollPosition position) {
    if (!identical(_position, position)) return;
    _offset = position.pixels;
    _position = null;
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Drops all listeners and marks the controller disposed. Idempotent.
  ///
  /// Completes a pending [jumpToSection]. An attached viewport keeps its own
  /// offset but can no longer be commanded or publish events here.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pending = _pendingSectionJump;
    _pendingSectionJump = null;
    if (pending != null && !pending.$2.isCompleted) pending.$2.complete();
    _position = null;
    _events.dispose();
  }
}
