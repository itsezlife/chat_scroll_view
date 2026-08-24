/// Sealed hierarchy of scroll-side events emitted by [PanelCatalogViewport].
///
/// Subscribe via [PanelCatalogController.addScrollListener] to react to user
/// drags / flings / programmatic jumps / section motion without conflating
/// channels — e.g. update sticky shell chrome on every offset tick, dismiss
/// search focus on user drag only, or debounce bottom-bar hide while a fling
/// is in flight.
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

/// Absolute [offset] changed without a jump/scroll-by listener re-fire.
///
/// Emitted for near-path section ticks, [PanelCatalogController.animateTo]
/// ticks, far-path stitch teleports, and silent viewport clamps — any write
/// through [PanelCatalogController.applyOffset]. Shell chrome (sticky search,
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
