import 'dart:math' as math;

import 'package:content_model/content_model.dart';
import 'package:flutter/animation.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_section_action.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Floor for travel-scaled [catalogStitchTravelDuration] (ms).
const int kCatalogStitchTravelDurationMinMs = 300;

/// Cap for travel-scaled [catalogStitchTravelDuration] (ms).
const int kCatalogStitchTravelDurationMaxMs = 1300;

/// Travel-scaled duration for far-path catalog stitch.
///
/// Formula: `((|travel| / viewportHeight) + 1) * 200` ms, clamped to
/// [[kCatalogStitchTravelDurationMinMs], [kCatalogStitchTravelDurationMaxMs]].
/// Short hops stay snappy; long hops feel deliberate without scrolling the gap.
Duration catalogStitchTravelDuration({
  required double travelPx,
  required double viewportHeight,
}) {
  final vh = viewportHeight <= 0 ? 1.0 : viewportHeight;
  final raw = ((travelPx.abs() / vh) + 1.0) * 200.0;
  final ms = raw
      .clamp(
        kCatalogStitchTravelDurationMinMs.toDouble(),
        kCatalogStitchTravelDurationMaxMs.toDouble(),
      )
      .round();
  return Duration(milliseconds: ms);
}

/// Frozen viewport-local geometry for one slot captured before stitch teleport.
///
/// [viewportTop] is the slot top in viewport coordinates at capture time
/// (content-y minus pre-jump scroll offset). Paint adds stitch dy on top of
/// this frozen band — layout slots are not mutated during the flight.
sealed class CatalogStitchCapturedSlot {
  /// Creates a captured slot at [viewportTop] with [height].
  const CatalogStitchCapturedSlot({
    required this.contentTop,
    required this.viewportTop,
    required this.height,
  });

  /// Captured section header band.
  const factory CatalogStitchCapturedSlot.header({
    required double contentTop,
    required double viewportTop,
    required double height,
    required double left,
    required double width,
    required String title,
    required String sectionId,
    CatalogSectionAction? action,
  }) = CatalogStitchCapturedHeader;

  /// Captured skeleton cell.
  const factory CatalogStitchCapturedSlot.skeleton({
    required double contentTop,
    required double viewportTop,
    required double height,
    required double left,
    required double width,
    required CatalogContentBox contentBox,
    required CatalogPlaceholderStyle style,
  }) = CatalogStitchCapturedSkeleton;

  /// Captured empty-message row.
  const factory CatalogStitchCapturedSlot.message({
    required double contentTop,
    required double viewportTop,
    required double height,
    required double left,
    required double width,
    required String text,
  }) = CatalogStitchCapturedMessage;

  /// Captured leaf cell.
  const factory CatalogStitchCapturedSlot.leaf({
    required double contentTop,
    required double viewportTop,
    required double height,
    required double left,
    required double width,
    required String sectionId,
    required int index,
    required CatalogLeaf leaf,
    CatalogContentBox? contentBox,
    CatalogPlaceholderStyle? placeholderStyle,
  }) = CatalogStitchCapturedLeaf;

  /// Content y of the slot top at capture time.
  final double contentTop;

  /// Viewport y of the slot top edge at capture time.
  final double viewportTop;

  /// Slot height in content coordinates.
  final double height;

  /// Viewport y of the slot bottom edge.
  double get viewportBottom => viewportTop + height;
}

/// Captured section header band for stitch outgoing paint.
final class CatalogStitchCapturedHeader extends CatalogStitchCapturedSlot {
  /// Creates a captured header.
  const CatalogStitchCapturedHeader({
    required super.contentTop,
    required super.viewportTop,
    required super.height,
    required this.left,
    required this.width,
    required this.title,
    required this.sectionId,
    this.action,
  });

  /// Content x of the section's left edge at capture time.
  final double left;

  /// Width the header shared with its columns at capture time.
  final double width;

  /// Section title text used to paint the header band.
  final String title;

  /// Section the header belonged to at capture time.
  final String sectionId;

  /// The section's trailing action at capture time.
  final CatalogSectionAction? action;
}

/// Captured skeleton cell for stitch outgoing paint.
final class CatalogStitchCapturedSkeleton extends CatalogStitchCapturedSlot {
  /// Creates a captured skeleton cell.
  const CatalogStitchCapturedSkeleton({
    required super.contentTop,
    required super.viewportTop,
    required super.height,
    required this.left,
    required this.width,
    required this.contentBox,
    required this.style,
  });

  /// Content x of the cell left edge at capture time.
  final double left;

  /// Cell width at capture time.
  final double width;

  /// The box the skeleton was drawn in.
  final CatalogContentBox contentBox;

  /// The stand-in the skeleton was drawn as.
  final CatalogPlaceholderStyle style;
}

/// Captured empty-message row for stitch outgoing paint.
final class CatalogStitchCapturedMessage extends CatalogStitchCapturedSlot {
  /// Creates a captured message row.
  const CatalogStitchCapturedMessage({
    required super.contentTop,
    required super.viewportTop,
    required super.height,
    required this.left,
    required this.width,
    required this.text,
  });

  /// Content x of the section's left edge at capture time.
  final double left;

  /// The section's usable width at capture time.
  final double width;

  /// The message text.
  final String text;
}

/// Captured leaf cell for stitch outgoing paint.
final class CatalogStitchCapturedLeaf extends CatalogStitchCapturedSlot {
  /// Creates a captured leaf cell.
  const CatalogStitchCapturedLeaf({
    required super.contentTop,
    required super.viewportTop,
    required super.height,
    required this.left,
    required this.width,
    required this.sectionId,
    required this.index,
    required this.leaf,
    this.contentBox,
    this.placeholderStyle,
  });

  /// Content x of the cell left edge at capture time.
  final double left;

  /// Cell width at capture time.
  final double width;

  /// Section the cell belonged to at capture time.
  final String sectionId;

  /// Position of the cell in that section at capture time.
  final int index;

  /// Leaf identity at capture time.
  final CatalogLeaf leaf;

  /// The section's content box override at capture time.
  final CatalogContentBox? contentBox;

  /// The section's placeholder style override at capture time.
  final CatalogPlaceholderStyle? placeholderStyle;
}

/// Captures slots intersecting the pre-jump viewport band.
///
/// [scrollOffset] and [viewportHeight] define the visible content window in
/// content coordinates. Returns viewport-local tops for dual-translate paint.
List<CatalogStitchCapturedSlot> captureCatalogStitchOutgoing({
  required List<CatalogLayoutSlot> slots,
  required double scrollOffset,
  required double viewportHeight,
}) {
  final captured = <CatalogStitchCapturedSlot>[];
  final visibleBottom = scrollOffset + viewportHeight;
  for (final slot in slots) {
    if (slot.bottom <= scrollOffset || slot.top >= visibleBottom) continue;
    final viewportTop = slot.top - scrollOffset;
    switch (slot) {
      case final CatalogHeaderSlot header:
        captured.add(
          CatalogStitchCapturedSlot.header(
            contentTop: slot.top,
            viewportTop: viewportTop,
            height: header.height,
            left: header.left,
            width: header.width,
            title: header.title,
            sectionId: header.sectionId,
            action: header.action,
          ),
        );
      case final CatalogSkeletonSlot skeleton:
        captured.add(
          CatalogStitchCapturedSlot.skeleton(
            contentTop: slot.top,
            viewportTop: viewportTop,
            height: skeleton.height,
            left: skeleton.left,
            width: skeleton.width,
            contentBox: skeleton.contentBox,
            style: skeleton.style,
          ),
        );
      case final CatalogMessageSlot message:
        captured.add(
          CatalogStitchCapturedSlot.message(
            contentTop: slot.top,
            viewportTop: viewportTop,
            height: message.height,
            left: message.left,
            width: message.width,
            text: message.text,
          ),
        );
      case final CatalogLeafSlot leaf:
        captured.add(
          CatalogStitchCapturedSlot.leaf(
            contentTop: slot.top,
            viewportTop: viewportTop,
            height: leaf.height,
            left: leaf.left,
            width: leaf.width,
            sectionId: leaf.sectionId,
            index: leaf.index,
            leaf: leaf.leaf,
            contentBox: leaf.contentBoxOverride,
            placeholderStyle: leaf.placeholderStyleOverride,
          ),
        );
    }
  }
  return captured;
}

/// Content keys of captured outgoing leaves (for binding pin during stitch).
Set<ContentKey> catalogStitchOutgoingLeafKeys(
  List<CatalogStitchCapturedSlot> outgoing,
) {
  return {
    for (final slot in outgoing)
      if (slot case CatalogStitchCapturedLeaf(:final leaf)) leaf.key,
  };
}

/// Whether [slot] was captured in the outgoing strip (skip incoming dual-translate).
bool catalogStitchSlotIsOutgoing(
  CatalogLayoutSlot slot,
  List<CatalogStitchCapturedSlot> outgoing,
) {
  for (final captured in outgoing) {
    switch ((slot, captured)) {
      case (
        CatalogHeaderSlot header,
        CatalogStitchCapturedHeader capturedHeader,
      ):
        if (header.top == capturedHeader.contentTop) return true;
      case (CatalogLeafSlot leafSlot, CatalogStitchCapturedLeaf capturedLeaf):
        // The cell, not its content: the same key in another section is a
        // different cell and must still travel as incoming.
        if (leafSlot.sectionId == capturedLeaf.sectionId &&
            leafSlot.index == capturedLeaf.index) {
          return true;
        }
      case (
        CatalogSkeletonSlot skeleton,
        CatalogStitchCapturedSkeleton capturedSkeleton,
      ):
        if (skeleton.top == capturedSkeleton.contentTop &&
            skeleton.left == capturedSkeleton.left) {
          return true;
        }
      case (
        CatalogMessageSlot message,
        CatalogStitchCapturedMessage capturedMessage,
      ):
        if (message.top == capturedMessage.contentTop) return true;
      default:
        continue;
    }
  }
  return false;
}

/// Computes dual-translate travel after stitch teleport + layout.
///
/// Outgoing strip extents come from capture-time viewport geometry; incoming
/// band from post-jump visible slots (excluding outgoing identity matches).
/// Returns at least `1` px.
double measureCatalogStitchTravel({
  required List<CatalogStitchCapturedSlot> outgoing,
  required List<CatalogLayoutSlot> incomingVisible,
  required bool towardNewer,
  required double scrollOffset,
  required double viewportHeight,
}) {
  var outgoingTop = double.infinity;
  var outgoingBottom = 0.0;
  for (final slot in outgoing) {
    if (slot.viewportTop < outgoingTop) outgoingTop = slot.viewportTop;
    if (slot.viewportBottom > outgoingBottom) {
      outgoingBottom = slot.viewportBottom;
    }
  }
  if (outgoingTop == double.infinity) outgoingTop = 0.0;

  var incomingTop = double.infinity;
  var incomingBottom = 0.0;
  var hasIncoming = false;
  for (final slot in incomingVisible) {
    if (catalogStitchSlotIsOutgoing(slot, outgoing)) continue;
    final top = slot.top - scrollOffset;
    final bottom = top + slot.height;
    hasIncoming = true;
    if (top < incomingTop) incomingTop = top;
    if (bottom > incomingBottom) incomingBottom = bottom;
  }

  final finalHeight = towardNewer
      ? outgoingBottom
      : viewportHeight - outgoingTop;
  final scrollLength = hasIncoming
      ? finalHeight +
            (towardNewer ? -incomingTop : incomingBottom - viewportHeight)
      : math.max(finalHeight, viewportHeight);
  return math.max<double>(scrollLength.abs(), 1);
}

/// Paint-time Y delta for one outgoing captured slot during stitch flight.
double catalogStitchOutgoingPaintDy({
  required bool towardNewer,
  required double travel,
  required double progress,
}) {
  return towardNewer ? -travel * progress : travel * progress;
}

/// Paint-time Y delta for one incoming visible slot during stitch flight.
///
/// When [measured] is false, [provisionalTravel] (typically viewport height)
/// keeps incoming fully off-screen until post-jump measure runs.
double catalogStitchIncomingPaintDy({
  required bool towardNewer,
  required double travel,
  required double progress,
  required bool measured,
  required double provisionalTravel,
}) {
  final effectiveTravel = measured ? travel : provisionalTravel;
  final t = measured ? progress : 0.0;
  return towardNewer ? effectiveTravel * (1 - t) : -effectiveTravel * (1 - t);
}

/// Far-path stitch animation driver for catalog section jumps.
///
/// Owns jumped/measured/progress state and one [AnimationController] per flight.
/// Does **not** capture slots, teleport offset, or paint — the render object
/// calls [begin], [applyMeasure], and reads [progress] each tick.
final class CatalogFarStitch {
  /// Creates idle stitch state bound to [vsync].
  CatalogFarStitch({
    required TickerProvider vsync,
    required VoidCallback onTick,
  }) : _vsync = vsync,
       _onTick = onTick;

  final TickerProvider _vsync;
  final VoidCallback _onTick;

  AnimationController? _controller;
  bool _active = false;
  bool _jumped = false;
  bool _measured = false;
  double _progress = 0;
  double _scrollLength = 0;
  bool _towardNewer = true;

  /// Whether a far-path stitch flight owns section-jump motion.
  bool get isActive => _active;

  /// Whether content offset has teleported to the destination.
  ///
  /// True from [begin] until settle/cancel. Paint uses dual-translate while
  /// jumped even before [measured].
  bool get jumped => _jumped;

  /// Whether post-jump travel has been measured and progress is advancing.
  ///
  /// False during the layout pass that supplies [scrollLength]; incoming paint
  /// uses [catalogStitchIncomingPaintDy] provisional off-screen offsets until
  /// this flips true.
  bool get measured => _measured;

  /// Eased stitch progress in `[0, 1]` after measure; `0` before measure.
  double get progress => _progress;

  /// Measured dual-translate travel in px (≥ 1 after [applyMeasure]).
  double get scrollLength => _scrollLength;

  /// Scroll direction: `true` when destination offset is greater than origin.
  bool get towardNewer => _towardNewer;

  /// Starts a stitch flight. Idempotent while already active.
  void begin({required bool towardNewer}) {
    cancel();
    _active = true;
    _jumped = true;
    _measured = false;
    _progress = 0;
    _scrollLength = 0;
    _towardNewer = towardNewer;
  }

  /// Supplies measured travel and starts the progress animation.
  ///
  /// No-op when not [jumped] or already [measured]. [scrollLength] MUST be ≥ 1.
  Future<void> applyMeasure({
    required double scrollLength,
    required double viewportHeight,
  }) {
    if (!_active || !_jumped || _measured) {
      return Future.value();
    }
    _scrollLength = math.max(scrollLength, 1);
    _measured = true;
    _progress = 0;

    final controller = AnimationController(
      vsync: _vsync,
      duration: catalogStitchTravelDuration(
        travelPx: _scrollLength,
        viewportHeight: viewportHeight,
      ),
    );
    _controller = controller;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutQuint,
    );

    void listener() {
      _progress = animation.value;
      _onTick();
    }

    controller.addListener(listener);
    var disposed = false;
    void disposeController() {
      if (disposed) return;
      disposed = true;
      controller.removeListener(listener);
      animation.dispose();
      controller.dispose();
      if (identical(_controller, controller)) {
        _controller = null;
      }
    }

    final future = controller.forward().orCancel.catchError((_) {});
    return future.whenComplete(() {
      disposeController();
      if (_active && _measured) {
        _progress = 1;
        _active = false;
        _jumped = false;
        _measured = false;
      }
    });
  }

  /// Aborts an in-flight stitch without applying further ticks.
  ///
  /// Idempotent. Clears active/jumped/measured state.
  void cancel() {
    _controller?.stop();
    _controller = null;
    _active = false;
    _jumped = false;
    _measured = false;
    _progress = 0;
    _scrollLength = 0;
  }

  /// Releases animation resources. Idempotent.
  void dispose() => cancel();
}
