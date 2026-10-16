import 'package:content_model/content_model.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';

/// Sealed hierarchy of scroll-side events emitted by [PanelCatalogViewport].
///
/// Subscribe via [PanelCatalogController.events] to react to user drags /
/// flings / programmatic jumps / section motion without conflating channels —
/// e.g. update sticky shell chrome on every offset tick, dismiss search focus
/// on user drag only, or debounce bottom-bar hide while a fling is in flight.
///
/// ## Three kinds
///
/// The motion events ([PanelCatalogUserDragStart] through
/// [PanelCatalogOffsetChanged]) say what moved the catalog. The activity
/// events ([PanelCatalogScrollingChanged], [PanelCatalogScrollSettled]) are
/// derived from them by the viewport and say whether the catalog is moving at
/// all, so a page that paces background work (a glyph bake) reads two facts
/// instead of re-deriving them from every motion event.
///
/// The section event ([PanelCatalogCurrentSectionChanged]) says which section
/// the viewport is in, for a page's strip.
///
/// The focus event ([PanelCatalogFocusChanged]) is neither motion nor
/// activity: it says which leaf holds roving focus.
///
/// The proximity event ([PanelCatalogSectionNearViewport]) is neither: it says
/// that an edge of a section is close to what the user sees, so a page can
/// load the section or load more of it. It is no motion and does not move the
/// activity facts, so whoever paces background work on them is unaffected.
sealed class PanelCatalogScrollEvent {
  const PanelCatalogScrollEvent();
}

/// User touched the viewport and started dragging.
final class PanelCatalogUserDragStart extends PanelCatalogScrollEvent {
  /// Emitted when the user begins dragging the catalog body.
  const PanelCatalogUserDragStart();
}

/// User lifted the finger after a drag. [velocity] is terminal pixel/second
/// velocity in content space (positive reveals content below).
final class PanelCatalogUserDragEnd extends PanelCatalogScrollEvent {
  /// Emitted when the user lifts their finger after a drag.
  const PanelCatalogUserDragEnd(this.velocity);

  /// Terminal drag velocity in pixels/second; positive reveals lower content.
  final double velocity;
}

/// The drag was cancelled without a release (the pointer was lost or the
/// viewport left the tree).
final class PanelCatalogUserDragCancel extends PanelCatalogScrollEvent {
  /// Emitted when a drag ends without [PanelCatalogUserDragEnd].
  const PanelCatalogUserDragCancel();
}

/// A fling simulation just started after drag end.
final class PanelCatalogFlingStart extends PanelCatalogScrollEvent {
  /// Emitted when inertial scrolling begins after a drag release.
  const PanelCatalogFlingStart(this.velocity);

  /// Initial fling velocity in pixels/second (content-offset space).
  final double velocity;
}

/// The fling simulation just terminated (naturally or cancelled).
final class PanelCatalogFlingEnd extends PanelCatalogScrollEvent {
  /// Emitted when the fling simulation finishes or is cancelled.
  const PanelCatalogFlingEnd();
}

/// [PanelCatalogController.jumpTo] repositioned the catalog.
final class PanelCatalogProgrammaticJump extends PanelCatalogScrollEvent {
  /// Emitted when [PanelCatalogController.jumpTo] sets a new absolute offset.
  const PanelCatalogProgrammaticJump(this.offset);

  /// Requested absolute content offset in logical pixels.
  final double offset;
}

/// Smooth scroll to an absolute offset started.
final class PanelCatalogAnimateStart extends PanelCatalogScrollEvent {
  /// Emitted when [PanelCatalogController.animateTo] begins scrolling.
  const PanelCatalogAnimateStart(this.offset, this.duration);

  /// Target absolute content offset.
  final double offset;

  /// Requested animation length.
  final Duration duration;
}

/// Smooth scroll to an absolute offset finished.
final class PanelCatalogAnimateEnd extends PanelCatalogScrollEvent {
  /// Emitted when an [PanelCatalogController.animateTo] animation completes.
  const PanelCatalogAnimateEnd(this.offset);

  /// Absolute content offset when the animation settled.
  final double offset;
}

/// [PanelCatalogController.scrollBy] shifted the catalog (user or fling tick).
final class PanelCatalogViewportScrolled extends PanelCatalogScrollEvent {
  /// Emitted when [PanelCatalogController.scrollBy] applies a pixel delta.
  const PanelCatalogViewportScrolled(this.delta);

  /// Pixel delta applied this step; positive reveals content below.
  final double delta;
}

/// [PanelCatalogController.jumpToSection] started engine-owned motion.
final class PanelCatalogSectionJumpStart extends PanelCatalogScrollEvent {
  /// Emitted when a section jump begins (near animate or far stitch).
  ///
  /// [farPath] is `true` when emitted after the far-path offset teleport
  /// ([PanelCatalogOffsetChanged] has already run). Near-path jumps emit
  /// before smooth scroll begins. Shell chrome SHOULD refresh geometry on
  /// every [PanelCatalogSectionJumpStart] and [PanelCatalogOffsetChanged].
  const PanelCatalogSectionJumpStart(
    this.sectionIndex,
    this.targetOffset, {
    this.farPath = false,
  });

  /// Target section index (`0..sectionCount−1`).
  final int sectionIndex;

  /// Landing scroll offset the jump is driving toward.
  final double targetOffset;

  /// Whether this jump selected far-path stitch rather than near animate.
  final bool farPath;
}

/// [PanelCatalogController.jumpToSection] motion settled or was cancelled.
final class PanelCatalogSectionJumpEnd extends PanelCatalogScrollEvent {
  /// Emitted when a section jump completes or user drag cancels it.
  const PanelCatalogSectionJumpEnd(this.sectionIndex);

  /// Section index that owned the completed jump.
  final int sectionIndex;
}

/// Absolute [offset] changed.
///
/// Emitted with every [PanelCatalogProgrammaticJump] and
/// [PanelCatalogViewportScrolled], and alone for near-path section ticks,
/// [PanelCatalogController.animateTo] ticks and far-path stitch teleports.
/// The viewport's silent range clamp emits nothing. Shell chrome (sticky search,
/// category strip) SHOULD listen here to stay aligned during programmatic
/// motion.
final class PanelCatalogOffsetChanged extends PanelCatalogScrollEvent {
  /// Emitted when the bound viewport writes a new absolute offset.
  const PanelCatalogOffsetChanged(this.offset, this.delta);

  /// New absolute content offset after the write.
  final double offset;

  /// `newOffset − previousOffset`; may be `0` when coalesced same-frame.
  final double delta;
}

/// The catalog started or stopped moving, as one fact over every way it can
/// move.
///
/// `scrolling: true` is published at once when the catalog starts to move: an
/// offset write (drag, wheel, fling tick, jump, animation tick), a drag in
/// progress (a finger that holds still is not at rest), or a fling / section
/// jump / stitch in flight between two ticks. `scrolling: false` follows one
/// quiet frame after all of that has ended, immediately before
/// [PanelCatalogScrollSettled]. Consecutive events always differ in
/// [scrolling].
///
/// A viewport that leaves the tree while the catalog is moving publishes
/// `scrolling: false` first, so a listener that paused work is never left
/// waiting.
final class PanelCatalogScrollingChanged extends PanelCatalogScrollEvent {
  /// Emitted when the viewport's moving / resting state changes.
  const PanelCatalogScrollingChanged({required this.scrolling});

  /// Whether the catalog is moving now.
  final bool scrolling;
}

/// The catalog came to rest, or its visible band changed while at rest.
///
/// [visibleKeys] lists the content on screen, top first, in projection order,
/// so a listener can prioritise the work for what the user sees (the glyph
/// bake bakes the page holding the visible band first). Published once per
/// rest, one quiet frame after the last motion, and again when a new snapshot
/// or geometry changes what is on screen while nothing moves. Never published
/// while the catalog moves.
final class PanelCatalogScrollSettled extends PanelCatalogScrollEvent {
  /// Emitted when the catalog is at rest, with the content in view.
  PanelCatalogScrollSettled(List<ContentKey> visibleKeys)
    : visibleKeys = List<ContentKey>.unmodifiable(visibleKeys);

  /// Keys of the leaves in the visible band, top first. Unmodifiable.
  final List<ContentKey> visibleKeys;
}

/// An edge of a section of the catalog.
enum CatalogSectionEdge {
  /// The top of the section: its header band.
  leading,

  /// The bottom of the section: the end of its last row. This is the edge a
  /// page watches to load more of a loaded section.
  trailing,
}

/// An edge of a section came close enough to the viewport that its owner
/// should load the section or load more of it.
///
/// "Close enough" is the viewport band widened by the viewport's
/// `sectionNearExtent` on both sides: an edge is near while it lies inside that
/// window. The event is published once as an edge comes inside, not while it
/// stays; it is published again when the edge leaves the window and comes back.
/// An edge that is already near is announced again when the section it belongs
/// to is published with a different number of leaves
/// ([CatalogSectionEdge.trailing] only: the end of a section that grew is a
/// different end), so a page that paginates is asked again while the end it
/// loaded up to is still in reach, until it is not. A change of state alone
/// (loading to failed) asks nothing: a retry is the owner's decision.
///
/// A jump that teleports (a far section jump, `jumpTo`) announces only the
/// edges in the window it lands on; sections it flew over are never announced.
/// Events of one evaluation come in section order, leading before trailing.
final class PanelCatalogSectionNearViewport extends PanelCatalogScrollEvent {
  /// Emitted when [edge] of section [sectionId] comes near the viewport.
  const PanelCatalogSectionNearViewport(this.sectionId, this.edge);

  /// [CatalogSection.id] of the section.
  final String sectionId;

  /// Which edge of the section is near.
  final CatalogSectionEdge edge;

  @override
  bool operator ==(Object other) =>
      other is PanelCatalogSectionNearViewport &&
      other.sectionId == sectionId &&
      other.edge == edge;

  @override
  int get hashCode => Object.hash(sectionId, edge);

  @override
  String toString() => 'PanelCatalogSectionNearViewport($sectionId, $edge)';
}

/// Roving focus moved to another leaf, or ended.
///
/// Published by [PanelCatalogController.focusLeaf], [moveFocus] and
/// [clearFocus], and by the viewport when the leaf that held focus is gone from
/// a new snapshot or the viewport leaves the tree. Not published when focus
/// stays on the same cell, even if the leaf value there changed.
final class PanelCatalogFocusChanged extends PanelCatalogScrollEvent {
  /// Emitted when the focused cell changes; [leaf] is null when focus ended.
  const PanelCatalogFocusChanged(this.leaf);

  /// The cell that holds focus now, or null when none does.
  final CatalogLeafHit? leaf;

  @override
  bool operator ==(Object other) =>
      other is PanelCatalogFocusChanged && other.leaf == leaf;

  @override
  int get hashCode => Object.hash(PanelCatalogFocusChanged, leaf);

  @override
  String toString() => 'PanelCatalogFocusChanged($leaf)';
}

/// The section the viewport is in changed.
///
/// A section is current from the moment its header reaches the landing line
/// (the viewport's `headerLandingInset`, else its top padding) until the next
/// section's header does. At the end of content that scrolls the last section
/// is current when its header is in view, because a section too short to bring
/// its header to the line could otherwise never be the one a jump to it lands
/// in. Before the first header reaches the line, the first section is current.
///
/// Published once per change, from the first layout that has sections, and
/// again when new sections change which one is current (or its index). It is
/// derived from the offset alone: it says nothing about why the catalogue
/// moved, so a strip that is driving a section jump itself ignores it while
/// `PanelCatalogController.isSectionJumpActive`. No event while there are no
/// sections.
final class PanelCatalogCurrentSectionChanged extends PanelCatalogScrollEvent {
  /// Emitted when section [sectionId], at [sectionIndex], became current.
  const PanelCatalogCurrentSectionChanged(this.sectionIndex, this.sectionId);

  /// Position of the section in the snapshot, from zero.
  final int sectionIndex;

  /// [CatalogSection.id] of the section.
  final String sectionId;

  @override
  bool operator ==(Object other) =>
      other is PanelCatalogCurrentSectionChanged &&
      other.sectionIndex == sectionIndex &&
      other.sectionId == sectionId;

  @override
  int get hashCode => Object.hash(sectionIndex, sectionId);

  @override
  String toString() =>
      'PanelCatalogCurrentSectionChanged($sectionIndex, $sectionId)';
}
