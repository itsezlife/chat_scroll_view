import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/material.dart';
import 'package:panel_catalog/src/data/catalog_data_source.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/theme/panel_catalog_theme.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_controller.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';

/// Extent-scroll catalog body with recycled paint leaves.
///
/// Host-facing shell over [RenderPanelCatalog]: a [LeafRenderObjectWidget]
/// (no element children). Catalog cells are **paint leaves** on a clipped
/// canvas — not per-cell widgets — so a large unicode panel stays cheap to
/// scroll and recycle.
///
/// Layout fills the parent's constraints ([RenderBox.size] is the viewport).
/// Content taller than the viewport scrolls by absolute
/// [PanelCatalogController.offset] against a known content extent produced by
/// projecting [CatalogDataSource.sections] into header + grid slots.
/// Intrinsic height is `0` (viewport-sized body, not content-sized).
///
/// Does **not** own panel chrome (category strip, search, type tabs, pickers),
/// asset fetch/decode ([CatalogAssetCache]), or catalog fetch orchestration
/// ([CatalogDataSource]). This widget only listens, projects, binds the
/// visible band, and paints.
///
/// ## Scroll and recycle
///
/// Drag and pointer-wheel update [controller] via [PanelCatalogController.scrollBy];
/// the render object clamps with [PanelCatalogController.correctOffset].
/// [PanelCatalogController.jumpToSection] lands a section header under
/// [padding.top] via near-path smooth scroll when [isNearPathSectionJump]
/// passes ([kFarPathDistanceGateFactor] flat rows, not `spanCount ×` that
/// value), or via far-path [CatalogFarStitch] when the gate fails. Re-entry
/// while [PanelCatalogController.isSectionJumpActive] is ignored at the
/// controller; hosts SHOULD gate category strip the same way. Drag-end with
/// enough velocity starts a ballistic fling; pointer-down while flinging
/// cancels the coast and suppresses leaf tap/long-press for that pointer.
/// User drag cancels an in-flight near-path scroll or far-path stitch.
/// [PanelCatalogController.isSectionJumpActive] is `true` during programmatic
/// section motion so hosts can suppress strip sync.
/// Asset bindings attach only for leaves in the visible window plus
/// one [cellExtent] of overscan; readiness flips mark paint dirty without a
/// full catalog reproject.
///
/// ## Hit-test and shell callbacks
///
/// The viewport is the sole hit target. Pointers map to [CatalogLeaf] via
/// content geometry (not per-cell [GestureDetector] / [InkWell]). Optional
/// [onLeafTap] / long-press callbacks forward leaf identity to the catalog
/// shell. [leafLongPressEligible] optionally limits which leaves register a
/// long-press recognizer (ineligible leaves stay tap-only). Press feedback is
/// painted from [PanelCatalogTheme] — scale on glyph content, list-selector
/// highlight on the full cell rect. A fling-cancel tap does not insert a leaf.
///
/// ## Theme
///
/// Requires a [PanelCatalogTheme] ancestor. [PanelCatalogTheme.of] →
/// [PanelCatalogThemeData] → [CatalogLeafPaintTheme.resolve] (DPR applied once)
/// → engine [RenderPanelCatalog.paintTheme]. Hosts customize
/// [PanelCatalogThemeData] only; the viewport owns density resolution and the
/// single snapshot handoff.
class PanelCatalogViewport extends LeafRenderObjectWidget {
  /// Creates an extent-scroll catalog body backed by [dataSource],
  /// [assetCache], and [controller].
  ///
  /// [spanCount] MUST be ≥ 1. [cellExtent] / [headerExtent] SHOULD be > 0;
  /// zero collapses rows/headers to empty bands but does not assert.
  /// Negative [padding] is undefined.
  ///
  /// Long-press is all-or-nothing: when [onLeafLongPressStart] is null, move
  /// and end are ignored and no long-press recognizer is registered. When
  /// start is wired, [leafLongPressEligible] optionally limits which leaves
  /// register the recognizer (plain glyphs stay tap-only).
  const PanelCatalogViewport({
    required this.dataSource,
    required this.assetCache,
    required this.controller,
    this.spanCount = 8,
    this.cellExtent = 48,
    this.headerExtent = 32,
    this.padding = EdgeInsets.zero,
    this.headerLandingInset,
    this.cacheType = CatalogAssetCacheType.keyboard,
    this.onLeafTap,
    this.onLeafLongPressStart,
    this.onLeafLongPressMove,
    this.onLeafLongPressEnd,
    this.leafLongPressEligible,
    super.key,
  });

  /// Authoritative catalog contents for this surface.
  ///
  /// The render object registers [CatalogDataSource.addDataListener] while
  /// attached and reprojects slots when the source notifies. Empty
  /// [CatalogDataSource.sections] is a confirmed empty catalog (headers only
  /// if sections exist with empty leaf lists — see projection rules).
  ///
  /// The viewport MUST NOT fetch inside layout/paint; subclasses of
  /// [CatalogDataSource] own fetch and call [CatalogDataSource.notifyDataChanged]
  /// once per logical mutation.
  final CatalogDataSource dataSource;

  /// Process-wide asset cache for leaf readiness and decode.
  ///
  /// The viewport binds **visible** leaves only (plus overscan) via
  /// [CatalogAssetCache.attach] and detaches the rest. Hosts MUST NOT treat
  /// this widget as a fetch/decode owner — decode lives in the cache;
  /// presentation is projected from readiness + leaf kind
  /// (`CatalogLeafPresentation`).
  final CatalogAssetCache assetCache;

  /// Absolute content-offset and navigation entry points ([jumpTo], [scrollBy],
  /// [PanelCatalogController.jumpToSection]).
  ///
  /// Catalog top = `0`. After each navigation notify the bound render object
  /// clamps to `[0, max(0, contentExtent − viewportHeight)]` via
  /// [PanelCatalogController.correctOffset] (silent — jump/scroll listeners
  /// are not re-fired). [offset] MAY briefly sit outside that range until
  /// clamp runs (e.g. [jumpTo] past the end before layout knows extent).
  ///
  /// The viewport does **not** dispose this controller.
  final PanelCatalogController controller;

  /// Leaf columns in the grid. MUST be ≥ 1.
  ///
  /// Changing span reprojects every slot and may change content extent
  /// (fewer columns → taller content).
  final int spanCount;

  /// Square cell pitch in content coordinates (row height and nominal width
  /// unit before usable-width division).
  ///
  /// Also the visible-band **overscan** unit: bindings extend one
  /// [cellExtent] above and below the viewport so short drags do not thrash
  /// attach/detach every frame. Changing pitch reprojects and re-syncs the
  /// bind window.
  final double cellExtent;

  /// Section header band height in content coordinates.
  ///
  /// Every [CatalogSection] emits a header band of this height even when its
  /// leaf list is empty — empty sections still reserve header extent for
  /// strip / jump landing. Changing this reprojects content extent.
  final double headerExtent;

  /// Insets included in content extent (top/bottom) and cell x (left/right).
  ///
  /// Horizontal padding reduces usable width before dividing into
  /// [spanCount] columns. Negative values are undefined.
  final EdgeInsets padding;

  /// Top inset for [PanelCatalogController.jumpToSection] header landing.
  ///
  /// When null, [padding.top] is used. Host shells that reserve extra content
  /// padding (e.g. a sticky search spacer folded into [padding.top]) but park
  /// section headers under a shorter overlay band (category strip only) MUST
  /// set this to the strip inset so landing math matches legacy flat-list
  /// behavior.
  final double? headerLandingInset;

  /// Attach size class passed to [CatalogAssetCache.attach] for each leaf.
  ///
  /// Replacing the type detaches every binding before re-attach on the next
  /// sync.
  final CatalogAssetCacheType cacheType;

  /// Shell tap when the user selects a leaf.
  ///
  /// Null disables tap recognition (scroll drag still works). Header and
  /// padding taps are silent — no synthetic leaf.
  final ValueChanged<CatalogLeaf>? onLeafTap;

  /// Shell long-press start (picker / contextual leaf actions).
  ///
  /// Null disables the long-press recognizer. When non-null, a long-press
  /// wins the arena after the timeout and cancels [onLeafTap] for that
  /// pointer on leaves where [leafLongPressEligible] allows registration.
  final void Function(CatalogLeaf leaf, LongPressStartDetails details)?
  onLeafLongPressStart;

  /// Shell long-press drag update while a long-press session is live.
  ///
  /// Ignored when [onLeafLongPressStart] is null.
  final void Function(CatalogLeaf leaf, LongPressMoveUpdateDetails details)?
  onLeafLongPressMove;

  /// Shell long-press end.
  ///
  /// Ignored when [onLeafLongPressStart] is null.
  final void Function(CatalogLeaf leaf, LongPressEndDetails details)?
  onLeafLongPressEnd;

  /// Host policy for which leaves register a long-press recognizer.
  ///
  /// Null treats every leaf as eligible when [onLeafLongPressStart] is wired.
  /// Return false when the shell has no long-press action for that leaf so
  /// tap is not cancelled after the long-press timeout (e.g. plain unicode
  /// glyphs without variant picker, vs recents or tone-capable bases).
  final bool Function(CatalogLeaf leaf)? leafLongPressEligible;

  @override
  RenderPanelCatalog createRenderObject(BuildContext context) {
    final theme = PanelCatalogTheme.of(context, listen: true);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return RenderPanelCatalog(
      dataSource: dataSource,
      assetCache: assetCache,
      controller: controller,
      spanCount: spanCount,
      cellExtent: cellExtent,
      headerExtent: headerExtent,
      padding: padding,
      headerLandingInset: headerLandingInset,
      cacheType: cacheType,
      paintTheme: CatalogLeafPaintTheme.resolve(theme, devicePixelRatio: dpr),
      onLeafTap: onLeafTap,
      onLeafLongPressStart: onLeafLongPressStart,
      onLeafLongPressMove: onLeafLongPressMove,
      onLeafLongPressEnd: onLeafLongPressEnd,
      leafLongPressEligible: leafLongPressEligible,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPanelCatalog renderObject,
  ) {
    final theme = PanelCatalogTheme.of(context, listen: true);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    renderObject
      ..dataSource = dataSource
      ..assetCache = assetCache
      ..controller = controller
      ..spanCount = spanCount
      ..cellExtent = cellExtent
      ..headerExtent = headerExtent
      ..padding = padding
      ..headerLandingInset = headerLandingInset
      ..cacheType = cacheType
      ..paintTheme = CatalogLeafPaintTheme.resolve(theme, devicePixelRatio: dpr)
      ..onLeafTap = onLeafTap
      ..onLeafLongPressStart = onLeafLongPressStart
      ..onLeafLongPressMove = onLeafLongPressMove
      ..onLeafLongPressEnd = onLeafLongPressEnd
      ..leafLongPressEligible = leafLongPressEligible;
  }
}
