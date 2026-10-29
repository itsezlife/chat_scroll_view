import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Marks the line inside a message row where the **text part** ends and a
/// **continuation** begins (cards, a gallery, any tall block that the reader
/// reads on by scrolling down, not as part of the message text).
///
/// Follow-tail pins the newest row's bottom to the bottom of the scroll
/// band. When a continuation is appended below the text of the newest row,
/// that pull would carry the reader past the end of the text they were
/// reading. A row that contains a fold keeps the reader on the fold line
/// instead:
///
/// - The reader is at the fold (its line sits on the band's bottom edge, or
///   the row was at the tail when the fold first appeared) and the row grows
///   **below** the fold: the viewport stays put.
/// - The row grows **above** the fold (the text keeps streaming): the fold
///   line is pinned to the band's bottom edge, as the row's bottom would be.
/// - The reader scrolls down into the continuation: the fold no longer
///   holds anything; the row's real bottom is the tail again, so a
///   continuation that grows while the reader is at its end is followed.
///
/// Only the **newest** row's fold matters, and only for growth of that row
/// while the viewport follows the tail. Jumps, the scroll-to-end animate,
/// scroll limits, the scrollbar and [ChatScrollController.isAtTail] keep
/// using the row's real bottom: with a continuation below the fold,
/// `isAtTail` stays `false` until the reader reaches the real end, so a
/// "scroll to end" affordance still shows.
///
/// The marker is zero-sized and paints nothing. Place it as a direct layout
/// sibling between the two parts of one row, for example in a `Column`
/// between the text and the cards. A row without a marker behaves exactly
/// as before. Keep the marker mounted for as long as the text part can
/// still grow, even while the continuation is empty: then the viewport has
/// seen the previous fold line. A marker that first appears together with
/// the continuation is read as "the row's previous bottom was the end of the
/// text", which is the same thing when the text did not change in that frame.
///
/// This is not a way to pin arbitrary lines: one marker per row is read (the
/// topmost), it has no effect off the newest row, and it never moves the
/// viewport by itself.
final class ChatTailFold extends LeafRenderObjectWidget {
  /// Marks the end of the text part of the row it is placed in.
  const ChatTailFold({super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderChatTailFold();
}

/// Implemented by the viewport render object so a [RenderChatTailFold]
/// finds the tracker of the viewport it lives in.
@internal
abstract interface class ChatTailFoldHost {
  /// Folds currently attached under this viewport.
  ChatTailFoldTracker get tailFolds;
}

/// Zero-size box behind [ChatTailFold]; registers with the enclosing viewport
/// while attached.
@internal
final class RenderChatTailFold extends RenderBox {
  ChatTailFoldTracker? _tracker;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var ancestor = parent;
    while (ancestor != null && ancestor is! ChatTailFoldHost) {
      ancestor = ancestor.parent;
    }
    final tracker = (ancestor as ChatTailFoldHost?)?.tailFolds;
    _tracker = tracker?..add(this);
  }

  @override
  void detach() {
    _tracker?.remove(this);
    _tracker = null;
    super.detach();
  }
}

/// The folds attached under one viewport, and the fold line of a row.
@internal
final class ChatTailFoldTracker {
  final Set<RenderChatTailFold> _folds = <RenderChatTailFold>{};

  /// Whether any fold is attached; lets the hot path skip the lookup.
  bool get isEmpty => _folds.isEmpty;

  /// Attach [fold].
  void add(RenderChatTailFold fold) => _folds.add(fold);

  /// Detach [fold].
  void remove(RenderChatTailFold fold) => _folds.remove(fold);

  /// Y of the topmost fold inside [row], in [row]'s coordinates, or `null`
  /// when [row] holds none (or the fold is not laid out yet).
  double? lineWithin(RenderBox row) {
    if (_folds.isEmpty) return null;
    double? line;
    for (final fold in _folds) {
      if (!fold.attached || !fold.hasSize || !_isInside(fold, row)) continue;
      final dy = MatrixUtils.transformPoint(
        fold.getTransformTo(row),
        Offset.zero,
      ).dy;
      if (line == null || dy < line) line = dy;
    }
    return line;
  }

  static bool _isInside(RenderObject node, RenderObject row) {
    for (var p = node.parent; p != null; p = p.parent) {
      if (identical(p, row)) return true;
    }
    return false;
  }
}

/// What a growing newest row asks of follow-tail, given its fold line.
@internal
enum ChatTailFoldHold {
  /// No fold in play: the usual repin to the row's bottom.
  none,

  /// The row grew below the fold: leave the viewport where it is.
  stay,

  /// The row grew above the fold: pin the fold line to the band's bottom.
  pinFold,
}

/// Decides how a newest row that grew follows the tail when it holds a fold.
///
/// All lines are row-relative Y except [previousLineY], which is the line's
/// absolute Y in the viewport at the end of the previous layout.
///
/// [previousLine] is the fold line the previous layout sampled, or the row's
/// previous height when the row held no fold then. The reader holds the fold
/// when that line was within [slop] of [bottomEdge] (it sat at the band's
/// bottom); a reader who had scrolled past it, or who is far above it, gets
/// [ChatTailFoldHold.none].
@internal
ChatTailFoldHold resolveTailFoldHold({
  required double? line,
  required double previousLine,
  required double previousLineY,
  required double bottomEdge,
  required double slop,
}) {
  if (line == null) return ChatTailFoldHold.none;
  if ((previousLineY - bottomEdge).abs() > slop) return ChatTailFoldHold.none;
  return line > previousLine + 0.5
      ? ChatTailFoldHold.pinFold
      : ChatTailFoldHold.stay;
}
