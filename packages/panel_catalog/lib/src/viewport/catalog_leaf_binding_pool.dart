import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart' show VoidCallback;
import 'package:panel_catalog/src/util/constants.dart';
import 'package:panel_catalog/src/util/logger.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// What a still leaf asks of the cache: one frame, shown at once.
const AssetProfile _stillProfile = AssetProfile();

/// What an animated leaf asks of the cache: play while it is shown and the
/// scope's clock runs.
const AssetProfile _playingProfile = AssetProfile(animate: true);

/// One live attach of a visible leaf: the cache binding and what the painter
/// needs to draw it.
///
/// Handed out by [CatalogLeafBindingPool] and valid until the next
/// [CatalogLeafBindingPool.syncVisible] or [CatalogLeafBindingPool.detachAll];
/// a painter reads it while painting and does not keep it, the same rule the
/// binding's own paintable and sprite follow.
final class CatalogBoundLeaf {
  CatalogBoundLeaf._(this.binding, this.spec)
    : _instant = binding.readiness.stage.index >= AssetStage.firstFrame.index;

  /// How long content takes to fade in over its placeholder when it was not
  /// there at attach.
  static const Duration contentFade = Duration(milliseconds: 150);

  /// The attach in the scope's cache.
  final AssetBinding binding;

  /// What was asked of the cache.
  final AssetSpec spec;

  // Whether the content was already there at attach (a memory hit): such a
  // leaf is never faded, so scrolling back over loaded content does not
  // flicker.
  final bool _instant;
  Duration? _fadeStart;
  bool _seen = false;
  bool _shown = false;

  /// Opacity to draw the content at on the frame at [frameTime]: `1` for
  /// content that was there at attach, otherwise rising from `0` over
  /// [contentFade] from the first frame the content is drawn.
  ///
  /// Call it only for a leaf whose binding has content (stage `firstFrame` or
  /// `full`); the fade starts on the first call.
  double opacityAt(Duration frameTime) {
    if (_instant) return 1;
    final start = _fadeStart ??= frameTime;
    final t = (frameTime - start).inMicroseconds / contentFade.inMicroseconds;
    return t.clamp(0.0, 1.0);
  }

  /// Whether the fade is still running at [frameTime].
  bool isFadingAt(Duration frameTime) {
    final start = _fadeStart;
    return !_instant && start != null && frameTime - start < contentFade;
  }
}

/// Attaches the leaves of the visible band to the host's [AssetCacheScope] and
/// detaches the rest.
///
/// Owns the **binding set** of one catalog render body. Does **not** own
/// layout slots, scroll offset or paint: the render object supplies a slot
/// range and reads [boundFor] at paint time.
///
/// ## What is asked of the cache
///
/// A leaf is attached as `attach(key, spec, profile)`:
///
/// - the [AssetSpec] is the leaf's content box ([CatalogLeafSlot.contentExtent]:
///   the glyph box or the whole cell) in physical pixels at the
///   [devicePixelRatio], a template decode when the leaf is tintable. The same
///   content at a size another section's cells need is a second attach;
/// - the [AssetProfile] animates when the leaf does. Whether it plays is the
///   binding's [AssetBinding.visible] flag, kept `true` only while the leaf is
///   in the painted window and, for an animated leaf, no fling is running;
///   the scope's clock adds the host's pause layers.
///
/// ## Page level
///
/// A baked glyph resolves to a sprite and holds its atlas **page** from attach
/// to detach, never pixels; the binding takes and gives back that hold, so
/// this pool holds nothing but bindings. A leaf that leaves the window detaches
/// at the next sync and its page reference goes with it.
///
/// ## Recycle contract
///
/// [syncVisible] keeps bindings for the leaf slots in the index range the owner
/// resolved for its content-y band and detaches the ones that left it. Header
/// slots are ignored. The owner typically passes the viewport band plus one
/// cell of overscan, so short drags do not thrash attach and detach; this pool
/// trusts the range it is given.
///
/// ## Lifecycle
///
/// [detachAll] MUST run when the owning render object detaches or disposes so
/// the cache's counts fall even if the scope is shared with another surface.
/// [replaceScope] detaches before swapping; the owner re-syncs to re-attach the
/// visible band.
///
/// [onChanged] is registered on every binding (typically `markNeedsPaint`) so
/// a better stage, a baked page or an animation frame repaints without a full
/// reproject.
final class CatalogLeafBindingPool {
  /// Creates an empty pool over [scope].
  ///
  /// [onChanged] fires when any attached binding signals. Pass a stable
  /// tear-off: the pool registers it once per binding.
  CatalogLeafBindingPool({
    required AssetCacheScope scope,
    required double devicePixelRatio,
    required VoidCallback onChanged,
  }) : _scope = scope,
       _devicePixelRatio = devicePixelRatio,
       _onChanged = onChanged;

  AssetCacheScope _scope;
  double _devicePixelRatio;
  final VoidCallback _onChanged;

  // Several attaches of one key are rare (a section with other cell sizes), so
  // the inner list is short and a paint lookup allocates nothing.
  final Map<ContentKey, List<CatalogBoundLeaf>> _byKey = {};
  final List<CatalogBoundLeaf> _all = [];

  /// The scope bindings are made on.
  AssetCacheScope get scope => _scope;

  /// Replaces the scope; detaches every existing binding first.
  ///
  /// Does not re-attach: the owner MUST [syncVisible] afterwards.
  void replaceScope(AssetCacheScope scope) {
    if (identical(_scope, scope)) return;
    detachAll();
    _scope = scope;
  }

  /// The density specs are computed at. A change makes every attached spec
  /// stale; the next [syncVisible] swaps the bindings for ones at the new
  /// size.
  set devicePixelRatio(double value) => _devicePixelRatio = value;

  /// Number of bindings currently attached.
  ///
  /// Bounded by the last [syncVisible] window, not by the catalogue size.
  int get attachedCount => _all.length;

  /// Syncs attaches to the leaf slots in `slots[start, end)`.
  ///
  /// The caller resolves the index range for its content-y window (binary
  /// search over the ascending [slots]), so this walk is proportional to the
  /// visible band, never to the catalogue. The range is trusted: every leaf in
  /// it is kept attached, so it MUST NOT include slots outside the intended
  /// window.
  ///
  /// A leaf is *shown* when its slot meets `[paintTop, paintBottom]` and, if
  /// it animates, [animate] is true (false while a fling runs). Hidden
  /// bindings stay attached and pinned but the cache does not advance them.
  ///
  /// [pinnedKeys] are kept attached and shown even when outside the window,
  /// used during far-path stitch so outgoing strip bindings survive the
  /// teleport. [top] / [bottom] are the attach window the range was resolved
  /// for; they feed diagnostics only.
  void syncVisible({
    required List<CatalogLayoutSlot> slots,
    required int start,
    required int end,
    required double paintTop,
    required double paintBottom,
    required bool animate,
    required double top,
    required double bottom,
    Set<ContentKey>? pinnedKeys,
  }) {
    for (final bound in _all) {
      bound
        .._seen = false
        .._shown = false;
    }
    for (var i = start; i < end; i++) {
      if (slots[i] case final CatalogLeafSlot slot) {
        final bound = _ensure(slot);
        bound._seen = true;
        final inPaint = slot.bottom >= paintTop && slot.top <= paintBottom;
        if (inPaint && (animate || !slot.leaf.animated)) bound._shown = true;
      }
    }
    if (pinnedKeys != null && pinnedKeys.isNotEmpty) {
      for (final bound in _all) {
        if (pinnedKeys.contains(bound.binding.key)) {
          bound
            .._seen = true
            .._shown = true;
        }
      }
    }
    var detached = 0;
    for (var i = _all.length - 1; i >= 0; i--) {
      final bound = _all[i];
      if (!bound._seen) {
        _remove(bound, at: i);
        detached++;
      } else {
        bound.binding.visible = bound._shown;
      }
    }
    if (LogCategory.binding.enabled && (_all.isNotEmpty || detached > 0)) {
      var ready = 0;
      var loading = 0;
      for (final bound in _all) {
        if (bound.binding.readiness.isFinal) {
          ready++;
        } else {
          loading++;
        }
      }
      Log.fine(.binding, 'sync', {
        'winTop': LogFormat.f(top),
        'winBot': LogFormat.f(bottom),
        'attached': _all.length,
        'detached': detached,
        'final': ready,
        'loading': loading,
      });
    }
  }

  /// The attach that draws [slot]'s leaf, or null when it has none (outside the
  /// last synced window).
  ///
  /// Allocates nothing. Valid while painting; see [CatalogBoundLeaf].
  CatalogBoundLeaf? boundFor(CatalogLeafSlot slot) {
    final group = _byKey[slot.leaf.key];
    if (group == null) return null;
    if (group.length == 1) return group[0];
    final pixels = _pixelsOf(slot.contentExtent);
    for (final bound in group) {
      if (bound.spec.pixelWidth == pixels) return bound;
    }
    return group[0];
  }

  /// Detaches every binding and clears the set. Idempotent; safe during
  /// detach and dispose even if [syncVisible] never ran.
  void detachAll() {
    for (final bound in _all) {
      bound.binding.detach();
    }
    _all.clear();
    _byKey.clear();
  }

  int _pixelsOf(double logicalExtent) =>
      (logicalExtent * _devicePixelRatio).ceil().clamp(1, 1 << 20);

  CatalogBoundLeaf _ensure(CatalogLeafSlot slot) {
    final leaf = slot.leaf;
    final pixels = _pixelsOf(slot.contentExtent);
    final mode = leaf.tintable
        ? AssetDecodeMode.template
        : AssetDecodeMode.original;
    final group = _byKey[leaf.key];
    if (group != null) {
      for (final bound in group) {
        final spec = bound.spec;
        if (spec.pixelWidth == pixels && spec.decodeMode == mode) return bound;
      }
    }
    final spec = AssetSpec(
      pixelWidth: pixels,
      pixelHeight: pixels,
      decodeMode: mode,
    );
    final binding = _scope.attach(
      leaf.key,
      spec,
      leaf.animated ? _playingProfile : _stillProfile,
    );
    binding.addListener(_onChanged);
    final bound = CatalogBoundLeaf._(binding, spec);
    (_byKey[leaf.key] ??= []).add(bound);
    _all.add(bound);
    return bound;
  }

  void _remove(CatalogBoundLeaf bound, {required int at}) {
    bound.binding.detach();
    _all.removeAt(at);
    final group = _byKey[bound.binding.key];
    if (group == null) return;
    group.remove(bound);
    if (group.isEmpty) _byKey.remove(bound.binding.key);
  }
}
