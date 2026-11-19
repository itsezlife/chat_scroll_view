import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';

/// How the confirm box offers the send options.
enum ConfirmBoxOptions {
  /// "Group items", "Send as documents" and "Remember" checkboxes under the
  /// previews.
  checkboxes,

  /// A More menu in the header: Add, Send as media / file(s), Group /
  /// Ungroup all, spoilers, caption up / down.
  moreMenu,
}

/// How per-item actions show on a preview.
enum ConfirmBoxItemActions {
  /// An edit / delete pill on every thumb, and a right-click menu.
  pillAndMenu,

  /// A pill on hover (always on a touch screen).
  hoverPill,
}

/// How the title names what the box sends.
enum ConfirmBoxTitles {
  /// "N photos selected" / "N files selected"; one item: "Send photo",
  /// "Send video", "Send file".
  selected,

  /// "Send N Photos" / "Send N Videos" / "Send N Files" (mixed or
  /// documents), "Send GIF".
  sendCount,
}

/// The **confirm box** of one platform family: the modal every intake route
/// leads to on desktop and web, as plain values the sheet policy carries.
@immutable
final class ConfirmBoxStyle {
  /// A confirm box style.
  const ConfirmBoxStyle({
    required this.width,
    required this.previewWidth,
    required this.blockSpacing,
    required this.maxHeight,
    required this.radius,
    required this.dimOpacity,
    required this.open,
    required this.close,
    required this.rise,
    required this.dismissesOnOutsideTap,
    required this.options,
    required this.itemActions,
    required this.titles,
    required this.reorders,
    required this.singleMediaMaxHeight,
    required this.fileRowHeight,
    required this.fileThumb,
    required this.dedupesByFacts,
    required this.printableKeyFocusesCaption,
    required this.analysedAtOnce,
  });

  /// The box's width.
  final double width;

  /// The width of its previews.
  final double previewWidth;

  /// The space between preview blocks.
  final double blockSpacing;

  /// The tallest the box grows before it scrolls; null for the window less
  /// its margins.
  final double? maxHeight;

  /// The box's corner radius.
  final double radius;

  /// How dark the scrim behind it gets.
  final double dimOpacity;

  /// The box coming in.
  final MotionSpec open;

  /// The box leaving.
  final MotionSpec close;

  /// How far below its place it starts (a fade only under reduced motion).
  final double rise;

  /// Whether a click outside the box closes it.
  final bool dismissesOnOutsideTap;

  /// Where the send options are.
  final ConfirmBoxOptions options;

  /// How a preview's own actions show.
  final ConfirmBoxItemActions itemActions;

  /// The title rule.
  final ConfirmBoxTitles titles;

  /// Whether thumbs of a media group reorder by drag.
  final bool reorders;

  /// The tallest a single media preview is, as a share of its width, and at
  /// most this many pixels: `min(widthShare * width, cap)`.
  final ({double widthShare, double cap}) singleMediaMaxHeight;

  /// The height of a file or audio row.
  final double fileRowHeight;

  /// The size of a file row's thumbnail.
  final double fileThumb;

  /// Whether an item already in the box (same name, size and modified
  /// time) is not added twice.
  final bool dedupesByFacts;

  /// Whether a printable key pressed outside the caption focuses it.
  final bool printableKeyFocusesCaption;

  /// How many items are analysed at once before the rest stream in.
  final int analysedAtOnce;
}

/// How a thumb in a reordering media group moves.
@immutable
final class ConfirmBoxReorder {
  /// The reorder motion.
  const ConfirmBoxReorder({
    required this.shrink,
    required this.lift,
    required this.neighbours,
    required this.settle,
  });

  /// How much the dragged thumb shrinks on each side.
  final double shrink;

  /// The shrink's timing.
  final MotionSpec lift;

  /// Neighbours sliding out of the way.
  final MotionSpec neighbours;

  /// The dropped thumb settling into its place.
  final MotionSpec settle;
}
