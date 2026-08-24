import 'package:flutter/foundation.dart';

/// Extent-scroll position for [PanelCatalogViewport].
///
/// Owns the absolute content [offset] (logical pixels from the catalog top)
/// and the host navigation entry points ([jumpTo], [scrollBy]). This is an
/// **extent** model: offset is a content-y scroll position against a known
/// content height, not an id-relative anchor.
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
/// Typed [addJumpListener] / [addScrollByListener]. Same callback twice is a
/// no-op (dedup-on-add). Dispatch iterates a snapshot so listeners MAY
/// add/remove during notify without concurrent modification.
///
/// Jump and scroll-by are separate channels: a [jumpTo] does **not** fire
/// scroll-by listeners and vice versa. Silent [correctOffset] clamps notify
/// neither channel.
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
    _offset = pixels;
    for (final cb in List<ValueChanged<double>>.of(
      _jumpListeners,
      growable: false,
    )) {
      cb(pixels);
    }
  }

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
    for (final cb in List<ValueChanged<double>>.of(
      _scrollByListeners,
      growable: false,
    )) {
      cb(delta);
    }
  }

  // --- Viewport correction --------------------------------------------------

  /// Silently writes a clamped [pixels] without notifying jump/scroll listeners.
  ///
  /// Owned by the bound viewport’s range clamp. Navigation that must notify
  /// listeners uses [jumpTo] / [scrollBy] instead — a host [correctOffset]
  /// write is invisible to those channels.
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
  /// After dispose, [jumpTo] / [scrollBy] / [correctOffset] are silent
  /// no-ops. Safe to call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _jumpListeners.clear();
    _scrollByListeners.clear();
  }
}
