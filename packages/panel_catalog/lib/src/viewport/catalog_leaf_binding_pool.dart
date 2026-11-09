import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart' show VoidCallback;
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/util/constants.dart';
import 'package:panel_catalog/src/util/logger.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

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
/// - the leaf's content box ([CatalogLeafSlot.contentExtent]: the glyph box or
///   the whole cell) as a `AssetPresets.keyboardCell` at the
///   [devicePixelRatio], a template decode when the leaf is tintable. So a
///   playing leaf of at most 90 logical px plays at half rate and decodes at
///   most 160 px, as every small cell of a content panel does. The same
///   content at a size another section's cells need is a second attach;
/// - the [AssetProfile] animates when the leaf does. The binding's
///   [AssetBinding.visible] flag says whether the leaf is in the painted
///   window, and nothing else: a leaf that leaves it gives back what it leased
///   for the screen (`AssetPaintable.leftScreen`), and one that comes back
///   goes on from where it was. A scroll, a fling or a drag against an edge
///   changes nothing for a leaf that stays in the window: it plays on, as in
///   the reference mobile client, whose panel grids never stop their
///   drawables for a scroll (only its chat list does, through
///   `RecyclerListView.setAllowStopHeaveOperations`). The scope's clock adds
///   the host's pause layers.
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
/// ## Held
///
/// While [held] (the viewport's tickers are off: a hidden panel kept mounted,
/// a page of a pager off screen, a panel moving in or out) every binding is
/// [AssetBinding.held]: it keeps its frame, and the lease where that frame
/// lives, and plays nothing. The set only grows then: a leaf that leaves the
/// window keeps its binding, so a layout at another size (a panel that
/// shrinks as it closes) detaches nothing and a show finds every cell as it
/// was. Let go, the next [syncVisible] detaches what is outside the window.
/// The set stays bounded by the largest window synced while held.
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

  /// Whether every binding holds its frame and none is detached; see the
  /// class documentation.
  bool get held => _held;
  bool _held = false;
  set held(bool value) {
    if (_held == value) return;
    _held = value;
    for (final bound in _all) {
      bound.binding.held = value;
    }
  }

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
  /// A leaf is *shown* ([AssetBinding.visible]) when its slot meets
  /// `[paintTop, paintBottom]`. Hidden bindings stay attached and pinned but
  /// the cache does not advance them, and their paintables give back their
  /// leases.
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
        if (inPaint) bound._shown = true;
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
      if (!bound._seen && !_held) {
        _remove(bound, at: i);
        detached++;
      } else if (bound._seen) {
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
  /// Allocates nothing for a key attached once, the common case. Valid while
  /// painting; see [CatalogBoundLeaf].
  CatalogBoundLeaf? boundFor(CatalogLeafSlot slot) {
    final group = _byKey[slot.leaf.key];
    if (group == null) return null;
    if (group.length == 1) return group[0];
    final pixels = _presetFor(slot.leaf, slot.contentExtent).spec.pixelWidth;
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

  // The extent is at least a pixel, however small the box.
  AssetPreset _presetFor(CatalogLeaf leaf, double logicalExtent) =>
      AssetPresets.keyboardCell(
        extent: math.max(logicalExtent, 1 / _devicePixelRatio),
        devicePixelRatio: _devicePixelRatio,
        animate: leaf.animated,
        decodeMode: leaf.tintable
            ? AssetDecodeMode.template
            : AssetDecodeMode.original,
        fit: leaf.contentFit,
      );

  CatalogBoundLeaf _ensure(CatalogLeafSlot slot) {
    final leaf = slot.leaf;
    final preset = _presetFor(leaf, slot.contentExtent);
    final spec = preset.spec;
    final group = _byKey[leaf.key];
    if (group != null) {
      for (final bound in group) {
        if (bound.spec == spec) return bound;
      }
    }
    final binding = _scope.attach(leaf.key, spec, preset.profile)..held = _held;
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
