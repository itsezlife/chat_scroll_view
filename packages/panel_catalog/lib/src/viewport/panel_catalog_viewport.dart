import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/src/data/catalog_snapshot.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';
import 'package:panel_catalog/src/model/section_layout.dart';
import 'package:panel_catalog/src/theme/panel_catalog_theme.dart';
import 'package:panel_catalog/src/viewport/catalog_grid_metrics.dart';
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
/// projecting [CatalogSnapshot.sections] into header + grid slots, each
/// section by its own [CatalogSection.layout] (the viewport's [spanCount],
/// [cellExtent] and [headerExtent] are the defaults a section inherits).
/// Intrinsic height is `0` (viewport-sized body, not content-sized).
///
/// Does **not** own panel chrome (category strip, search, type tabs, pickers),
/// asset fetch/decode (the host's [AssetCacheScope]), or catalog fetch orchestration
/// (the owner of [snapshots]). This widget only listens, projects, binds the
/// visible band, and paints.
///
/// ## Scroll and recycle
///
/// Drag and pointer-wheel move the attached position
/// ([PanelCatalogController.scrollBy]); the render object clamps to the valid
/// range afterwards.
/// [PanelCatalogController.jumpToSection] lands a section header under
/// [padding.top] via near-path smooth scroll when
/// [CatalogSectionNavigation.isNearPathSectionJump] passes
/// ([CatalogSectionNavigation.farPathDistanceGateFactor] flat rows, counted at
/// each section's own column count, not `spanCount ×` that value), or via
/// far-path [CatalogFarStitch] when the gate fails. Re-entry
/// while [PanelCatalogController.isSectionJumpActive] is ignored at the
/// controller; hosts SHOULD gate category strip the same way. Drag-end with
/// enough velocity starts a ballistic fling; pointer-down while flinging
/// cancels the coast and suppresses leaf tap/long-press for that pointer.
/// User drag cancels an in-flight near-path scroll or far-path stitch.
/// [PanelCatalogController.isSectionJumpActive] is `true` during programmatic
/// section motion so hosts can suppress strip sync.
/// Asset bindings attach only for leaves in the visible window plus
/// one default [cellExtent] of overscan; a better stage on a binding marks
/// paint dirty without a full catalog reproject. The window is found by binary search
/// over one ascending slot list, so its cost follows the visible band whatever
/// mix of section layouts the catalog holds.
///
/// ## Hit-test and shell callbacks
///
/// The viewport is the sole hit target. Pointers map to a [CatalogLeafHit]
/// via content geometry (not per-cell [GestureDetector] / [InkWell]); a hit is
/// the cell, [CatalogLeafHit.sectionId] and [CatalogLeafHit.index], with the
/// leaf it holds, so the same content key in two sections is two hits. Optional
/// [onLeafTap] / long-press callbacks forward the hit to the catalog shell.
/// [leafLongPressEligible] optionally limits which cells register a long-press
/// recognizer (ineligible cells stay tap-only). Press feedback is
/// painted from [PanelCatalogTheme] — scale on glyph content, list-selector
/// highlight on the full cell rect. A fling-cancel tap does not insert a leaf.
///
/// ## Sections
///
/// A [CatalogSection] paints by its [CatalogSection.state]: skeleton leaves
/// after its leaves while it is loading or failed (no error UI, nothing
/// attached to [assets]), its leaves or its empty-message row when loaded. A
/// header may carry a trailing [CatalogSectionAction]; a tap on it reaches
/// [onSectionAction]. [PanelCatalogController.events] tells the owner of
/// [snapshots] when a section is close enough to load or paginate
/// ([PanelCatalogSectionNearViewport]).
///
/// ## Direction, semantics, focus and cursor
///
/// Cells fill each row start to end in the direction of the [Directionality]
/// above the viewport (or of the section's own [SectionLayout.grid]
/// `textDirection`), so a right-to-left grid begins at the right edge; only x
/// changes, never rows, extents or landing offsets, and content is never
/// mirrored. With assistive technology running, the viewport describes the
/// window it binds (the visible band plus one cell of overscan) as semantic
/// nodes whose actions reach [onLeafTap], [onLeafLongPressStart] and
/// [onSectionAction]; no node exists for the rest of the catalogue. Roving
/// focus is the controller's ([PanelCatalogController.moveFocus]): the focused
/// leaf is painted with the press highlight, scrolled into view and activated
/// through [onLeafTap]. The viewport shows the click cursor over a leaf the
/// shell can tap or long-press and over a header action it listens to.
///
/// ## Theme
///
/// Requires a [PanelCatalogTheme] ancestor. [PanelCatalogTheme.of] →
/// [PanelCatalogThemeData] → [CatalogLeafPaintTheme.resolve] (DPR applied once)
/// → engine [RenderPanelCatalog.paintTheme]. Hosts customize
/// [PanelCatalogThemeData] only; the viewport owns density resolution and the
/// single snapshot handoff.
///
/// ## Density
///
/// Density is read from the [MediaQuery] of the viewport's own subtree, so it
/// is the density of the view the viewport sits in and follows that view's
/// resize / display change. It is never read from the platform's first view.
/// Assets are asked for at that density.
///
/// ## Assets
///
/// The viewport attaches through the host's [assets] and paints the
/// [AssetPaintable] each binding exposes; it names no cache implementation and
/// no atlas. A paintable with a sprite is drawn in one batched atlas draw per
/// page; any other paints itself. Which strategy draws unicode glyphs (baked
/// sprites on a platform that bakes, text where it does not) is decided by how
/// the host builds the scope, not here. A leaf that cannot load keeps its
/// placeholder.
class PanelCatalogViewport extends LeafRenderObjectWidget {
  /// Creates an extent-scroll catalog body backed by [snapshots], [assets]
  /// and [controller].
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
    required this.snapshots,
    required this.assets,
    required this.controller,
    this.spanCount = 8,
    this.cellExtent = 48,
    this.headerExtent = 32,
    this.padding = EdgeInsets.zero,
    this.headerLandingInset,
    this.onLeafTap,
    this.onLeafSecondaryTap,
    this.onLeafLongPressStart,
    this.onLeafLongPressMove,
    this.onLeafLongPressEnd,
    this.leafLongPressEligible,
    this.leafLongPressDelay,
    this.pinnedLeaf,
    this.onSectionAction,
    this.sectionNearExtent,
    super.key,
  });

  /// The largest glyph box any of [layouts] draws a glyph in, for a viewport
  /// of [maxWidth] with these defaults and [padding].
  ///
  /// A host that bakes glyphs has **one** baked size per atlas, so it sizes it
  /// for the largest box and every section draws the same sprites scaled down:
  /// sizing for a smaller one would blur the sections with larger cells, and a
  /// second atlas for them would double the resident pages. Pass the layout of
  /// each section the atlas serves (`null` is the viewport default); with
  /// none, the default's box is returned. The box is
  /// [CatalogContentBox.glyphBoxExtent] of the resolved cell, the very formula
  /// the painter draws with.
  static double largestGlyphBox({
    required Iterable<SectionLayout?> layouts,
    required int spanCount,
    required double cellExtent,
    required EdgeInsets padding,
    required double maxWidth,
  }) {
    double boxOf(SectionLayout? layout) => CatalogGridMetrics.resolve(
      layout,
      spanCount: spanCount,
      cellExtent: cellExtent,
      headerExtent: 0,
      padding: padding,
      maxWidth: maxWidth,
    ).glyphBoxExtent;

    var largest = 0.0;
    var any = false;
    for (final layout in layouts) {
      any = true;
      largest = math.max(largest, boxOf(layout));
    }
    return any ? largest : boxOf(null);
  }

  /// Authoritative catalog contents for this surface, as an immutable
  /// [CatalogSnapshot] the host publishes.
  ///
  /// The render object listens while attached and reprojects slots when the
  /// listenable signals. Empty [CatalogSnapshot.sections] is a confirmed
  /// empty catalog (headers only if sections exist with empty leaf lists —
  /// see projection rules).
  ///
  /// The viewport MUST NOT fetch inside layout/paint; the owner of the
  /// listenable fetches and publishes one new snapshot per logical mutation
  /// (assigning the final snapshot once, not each step).
  final listen.ValueListenable<CatalogSnapshot> snapshots;

  /// The host's asset cache, shared with every other surface that draws
  /// content.
  ///
  /// The viewport attaches **visible** leaves only (plus overscan) through
  /// [AssetCacheScope.attach] and detaches the rest; a baked glyph's binding
  /// holds its atlas page for as long as it is attached. Hosts MUST NOT treat
  /// this widget as a fetch/decode owner: decode lives in the cache, and what
  /// is painted comes from the binding plus the leaf's descriptor facts
  /// ([CatalogLeaf.placeholderStyle]).
  ///
  /// Whoever owns the bake listens to [PanelCatalogController.events]
  /// ([PanelCatalogScrollingChanged] and [PanelCatalogScrollSettled] with the
  /// visible keys); the viewport tells no atlas anything.
  ///
  /// Swapping the scope detaches every binding made on the old one. The host
  /// disposes it; the viewport never does.
  final AssetCacheScope assets;

  /// Absolute content-offset and navigation entry points ([jumpTo], [scrollBy],
  /// [PanelCatalogController.jumpToSection]) and the scroll-event stream.
  ///
  /// Catalog top = `0`. The bound render object attaches itself as the
  /// controller's position and clamps to `[0, max(0, contentExtent −
  /// viewportHeight)]` after each navigation. [offset] MAY briefly sit outside
  /// that range until clamp runs (e.g. [jumpTo] past the end before layout
  /// knows extent).
  ///
  /// The viewport does **not** dispose this controller.
  final PanelCatalogController controller;

  /// Default leaf columns of a section whose layout leaves its span unset.
  /// MUST be ≥ 1.
  ///
  /// Changing span reprojects every slot and may change content extent
  /// (fewer columns → taller content).
  final int spanCount;

  /// Default cell pitch in content coordinates (row height and nominal width
  /// unit before usable-width division) of a section whose layout sets none.
  ///
  /// Also the visible-band **overscan** unit, whatever the sections' own
  /// pitches: bindings extend one [cellExtent] above and below the viewport so
  /// short drags do not thrash attach/detach every frame. Changing pitch
  /// reprojects and re-syncs the bind window.
  final double cellExtent;

  /// Default section header band height in content coordinates.
  ///
  /// Every [CatalogSection] emits a header band even when its leaf list is
  /// empty — empty sections still reserve header extent for strip / jump
  /// landing. A section's layout may set its own. Changing this reprojects
  /// content extent.
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

  /// Shell tap when the user selects a cell.
  ///
  /// Null disables tap recognition (scroll drag still works). Header and
  /// padding taps are silent — no synthetic hit.
  final ValueChanged<CatalogLeafHit>? onLeafTap;

  /// Shell secondary tap: a mouse right click (button up) on a cell, with the
  /// cell and the global position of the click.
  ///
  /// Only a mouse reports it. The secondary button never taps, presses
  /// (no press animation) or long-presses a cell, whether this is wired or
  /// not; wiring it only makes the click reach the host. Null leaves the
  /// button silent. What the click opens is the host's.
  final void Function(CatalogLeafHit hit, Offset globalPosition)?
  onLeafSecondaryTap;

  /// Shell long-press start (picker / contextual leaf actions).
  ///
  /// Null disables the long-press recognizer. When non-null, a long-press
  /// wins the arena after the timeout and cancels [onLeafTap] for that
  /// pointer on leaves where [leafLongPressEligible] allows registration.
  final void Function(CatalogLeafHit hit, LongPressStartDetails details)?
  onLeafLongPressStart;

  /// Shell long-press drag update while a long-press session is live.
  ///
  /// Ignored when [onLeafLongPressStart] is null.
  final void Function(CatalogLeafHit hit, LongPressMoveUpdateDetails details)?
  onLeafLongPressMove;

  /// Shell long-press end.
  ///
  /// Ignored when [onLeafLongPressStart] is null.
  final void Function(CatalogLeafHit hit, LongPressEndDetails details)?
  onLeafLongPressEnd;

  /// Host policy for which leaves register a long-press recognizer.
  ///
  /// Null treats every leaf as eligible when [onLeafLongPressStart] is wired.
  /// Return false when the shell has no long-press action for that leaf so
  /// tap is not cancelled after the long-press timeout (e.g. plain unicode
  /// glyphs without variant picker, vs recents or tone-capable bases).
  final bool Function(CatalogLeafHit hit)? leafLongPressEligible;

  /// How long a press on a cell must last to be a long press, per cell and
  /// per pointer kind; null from the callback, or no callback, is the
  /// platform's timeout.
  ///
  /// A host that wants a mouse to open its long-press surface at once answers
  /// [Duration.zero] for [PointerDeviceKind.mouse]: the long press then starts
  /// as the event loop turns after the button went down (a click that lifts
  /// sooner stays a tap), so a surface can be up while the button is still
  /// held.
  final Duration? Function(CatalogLeafHit hit, PointerDeviceKind kind)?
  leafLongPressDelay;

  /// The cell a transient surface the host opened (a picker) is over, or null.
  ///
  /// While set, that cell keeps its hover wash wherever the mouse moves and
  /// the mouse wheel does not scroll, so the surface stays where it was
  /// opened and the cell it belongs to stays marked. Two effects of one
  /// state: the host has the interaction.
  final CatalogLeafHit? pinnedLeaf;

  /// Shell reaction to a tapped section header action, with the id of the
  /// [CatalogSection] and the [CatalogSectionAction.id].
  ///
  /// Null disables recognition (the header is silent; scroll drag still works).
  /// The viewport paints the action and owns its hit area, and decides nothing
  /// about what the action does.
  final void Function(String sectionId, String actionId)? onSectionAction;

  /// How far beyond the viewport, above and below, a section edge counts as
  /// near for [PanelCatalogSectionNearViewport], in content coordinates.
  ///
  /// Null is one viewport height. `0` is the viewport band itself. Larger
  /// values load earlier, at the price of loading sections the user may never
  /// reach.
  final double? sectionNearExtent;

  @override
  RenderPanelCatalog createRenderObject(BuildContext context) {
    final theme = PanelCatalogTheme.of(context, listen: true);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final textDirection = Directionality.of(context);
    return RenderPanelCatalog(
      snapshots: snapshots,
      assets: assets,
      devicePixelRatio: dpr,
      controller: controller,
      spanCount: spanCount,
      cellExtent: cellExtent,
      headerExtent: headerExtent,
      padding: padding,
      textDirection: textDirection,
      headerLandingInset: headerLandingInset,
      paintTheme: CatalogLeafPaintTheme.resolve(theme, devicePixelRatio: dpr),
      onLeafTap: onLeafTap,
      onLeafSecondaryTap: onLeafSecondaryTap,
      onLeafLongPressStart: onLeafLongPressStart,
      onLeafLongPressMove: onLeafLongPressMove,
      onLeafLongPressEnd: onLeafLongPressEnd,
      leafLongPressEligible: leafLongPressEligible,
      leafLongPressDelay: leafLongPressDelay,
      pinnedLeaf: pinnedLeaf,
      onSectionAction: onSectionAction,
      sectionNearExtent: sectionNearExtent,
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
      ..snapshots = snapshots
      ..assets = assets
      ..devicePixelRatio = dpr
      ..controller = controller
      ..spanCount = spanCount
      ..cellExtent = cellExtent
      ..headerExtent = headerExtent
      ..padding = padding
      ..textDirection = Directionality.of(context)
      ..headerLandingInset = headerLandingInset
      ..paintTheme = CatalogLeafPaintTheme.resolve(theme, devicePixelRatio: dpr)
      ..onLeafTap = onLeafTap
      ..onLeafSecondaryTap = onLeafSecondaryTap
      ..onLeafLongPressStart = onLeafLongPressStart
      ..onLeafLongPressMove = onLeafLongPressMove
      ..onLeafLongPressEnd = onLeafLongPressEnd
      ..leafLongPressEligible = leafLongPressEligible
      ..leafLongPressDelay = leafLongPressDelay
      ..pinnedLeaf = pinnedLeaf
      ..onSectionAction = onSectionAction
      ..sectionNearExtent = sectionNearExtent;
  }
}
