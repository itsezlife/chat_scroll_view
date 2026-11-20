import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// What a page's scroll hands the sheet: the part of each drag and fling
/// that moves the sheet rather than the page.
///
/// The sheet state implements it; the scroll position below calls it.
@internal
abstract interface class AttachSheetDrive {
  /// Whether drags move the sheet at all now.
  bool get takesDrags;

  /// Whether the sheet is at its top, where an upward drag scrolls the
  /// page.
  bool get isAtTop;

  /// A drag started.
  void dragStarted();

  /// Whether the sheet wants the drag in progress to end now (it turned
  /// into the discard question); the scroll then ends it and releases.
  bool get endsDrag;

  /// Moves the sheet by [delta] (positive downward); returns the part the
  /// sheet did not take, for the page.
  double dragSheet(double delta);

  /// The page's own fling ran into its start moving at [velocity] (positive
  /// downward): the sheet carries it on, as one list with the page.
  void carryFling(double velocity);

  /// A drag ended with [velocity] (positive downward). True when the sheet
  /// settles on its own; false to let the page fling. [handBack] starts a
  /// page fling of a scroll velocity, for a sheet fling that reaches the top.
  bool release(double velocity, void Function(double scrollVelocity) handBack);
}

/// The scroll controller a page attaches to its scrollable so the sheet and
/// the page share one drag: an upward drag raises the sheet until it is at
/// its top and then scrolls the page; a downward drag scrolls the page back
/// to its start and then lowers the sheet.
///
/// The sheet provides it as the `PrimaryScrollController` of the page, so a
/// scrollable with `primary: true` (the default for a vertical one with no
/// controller) takes it.
@internal
final class AttachSheetScrollController extends ScrollController {
  /// A controller handing drags to [drive].
  AttachSheetScrollController(this.drive);

  /// The sheet the drags go to.
  final AttachSheetDrive drive;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _AttachSheetScrollPosition(
    drive: drive,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _AttachSheetScrollPosition extends ScrollPositionWithSingleContext {
  _AttachSheetScrollPosition({
    required this.drive,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final AttachSheetDrive drive;
  VoidCallback? _cancelDrag;

  bool get _atStart => pixels <= minScrollExtent + precisionErrorTolerance;

  @override
  void applyNewDimensions() {
    super.applyNewDimensions();
    // A page too short to scroll still moves the sheet: the drag is the
    // sheet's whatever the page's extent, unless the page turned user
    // scrolling off (a gesture of its own).
    if (physics.allowUserScrolling) context.setCanDrag(true);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    drive.dragStarted();
    _cancelDrag = dragCancelCallback;
    return super.drag(details, dragCancelCallback);
  }

  @override
  void applyUserOffset(double delta) {
    // `delta` is in the scroll's terms: positive when the finger moves down.
    if (!drive.takesDrags) return super.applyUserOffset(delta);
    final movesSheet = delta < 0 ? !drive.isAtTop : _atStart;
    if (!movesSheet) return super.applyUserOffset(delta);
    final rest = drive.dragSheet(delta);
    if (drive.endsDrag) {
      // Detach the scrollable from the drag, then end it as a release with
      // no velocity, as a cancelled drag ends.
      final cancel = _cancelDrag;
      _cancelDrag = null;
      cancel?.call();
      goBallistic(0);
      return;
    }
    if (rest != 0) super.applyUserOffset(rest);
  }

  // A page's fling that reaches its start hands what is left of it to the
  // sheet, which goes on moving down: the page and the sheet are one list,
  // so one fling from the top of a scrolled page carries the sheet to its
  // rest instead of stopping there.
  @override
  double setPixels(double newPixels) {
    final activity = this.activity;
    if (activity is BallisticScrollActivity &&
        newPixels < minScrollExtent &&
        pixels > minScrollExtent - precisionErrorTolerance &&
        drive.takesDrags) {
      final velocity = activity.velocity;
      final overscroll = super.setPixels(minScrollExtent);
      goIdle();
      // A scroll velocity is negative toward the start; the sheet's is
      // positive downward.
      if (velocity < 0) drive.carryFling(-velocity);
      return overscroll;
    }
    return super.setPixels(newPixels);
  }

  @override
  void goBallistic(double velocity) {
    _cancelDrag = null;
    // A scroll velocity is positive when the content moves up, the finger
    // up; the sheet's is positive downward.
    if (drive.release(-velocity, _flingPage)) {
      super.goBallistic(0);
      return;
    }
    super.goBallistic(velocity);
  }

  void _flingPage(double scrollVelocity) => super.goBallistic(scrollVelocity);
}
