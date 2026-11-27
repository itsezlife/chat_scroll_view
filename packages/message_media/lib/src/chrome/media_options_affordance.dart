import 'dart:math' as math;

import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/policy/media_layout_policy.dart';

/// Where a cell's options affordance is and what a tap on it takes: the
/// three dots that open the message menu for the item.
@immutable
final class MediaOptionsAffordance {
  /// An affordance drawn in [iconRect] and hit in [hitRect].
  const MediaOptionsAffordance({required this.iconRect, required this.hitRect});

  /// The dots' rect, in the coordinates of the cell rect it was placed from.
  final Rect iconRect;

  /// The area a tap opens the menu from, larger than the dots and free to
  /// overflow the cell: the `options` hit part's rect.
  final Rect hitRect;

  /// This affordance moved by [offset].
  MediaOptionsAffordance shift(Offset offset) => MediaOptionsAffordance(
    iconRect: iconRect.shift(offset),
    hitRect: hitRect.shift(offset),
  );

  @override
  bool operator ==(Object other) =>
      other is MediaOptionsAffordance &&
      other.iconRect == iconRect &&
      other.hitRect == hitRect;

  @override
  int get hashCode => Object.hash(iconRect, hitRect);

  @override
  String toString() => 'MediaOptionsAffordance($iconRect, hit: $hitRect)';
}

/// What a message's media is drawn in, as the chrome slots weigh it.
@immutable
final class MediaChromeContext {
  /// The context of a message drawn in a chat.
  const MediaChromeContext({this.compact = false, this.preview = false});

  /// An ordinary message in a regular chat list.
  static const none = MediaChromeContext();

  /// Whether the chat is in its compact mode, where the message's own menu
  /// covers what the options affordance offers.
  final bool compact;

  /// Whether the message is a preview (not yet sent, or shown inside another
  /// surface), which has no message menu.
  final bool preview;

  @override
  bool operator ==(Object other) =>
      other is MediaChromeContext &&
      other.compact == compact &&
      other.preview == preview;

  @override
  int get hashCode => Object.hash(compact, preview);
}

/// Which cells carry the options affordance and where, per platform.
///
/// On Android a video or animation box has three vertical dots near its
/// top-right corner ([boxIconOffset] from the box's top-right, [boxIconSize]),
/// and the first row of a file stack has them at the row's top-right
/// ([rowIconOffset], [rowIconSize]). A tap within [hitArea] of the icon's
/// top-left opens the message menu. iOS and desktop have none
/// ([MediaOptionsPlacement.none]).
///
/// [affordanceOf] hides it in the chat's compact mode, on a preview, on a
/// file row below the first of its stack, under a spoiler not yet revealed
/// and on a small image.
@immutable
final class MediaOptionsPlacement {
  /// A placement on boxes of [boxKinds] and, when [onRows], on file rows.
  const MediaOptionsPlacement({
    this.boxKinds = const [],
    this.onRows = false,
    this.boxIconOffset = const Offset(-14, 8.1),
    this.boxIconSize = const Size(6, 18),
    this.rowIconOffset = const Offset(-27, 4),
    this.rowIconSize = const Size(24, 24),
    this.hitArea = const Rect.fromLTRB(-20, -4, 20, 30),
  });

  /// Video and animation boxes and file rows.
  const MediaOptionsPlacement.android()
    : this(
        boxKinds: const [MediaItemKind.video, MediaItemKind.animation],
        onRows: true,
      );

  /// No affordance on any cell: the message menu is reached the message's
  /// own way.
  static const none = MediaOptionsPlacement();

  /// The box kinds that carry the affordance.
  final List<MediaItemKind> boxKinds;

  /// Whether a file stack's first row carries it.
  final bool onRows;

  /// The icon's top-left from a box's top-right corner.
  final Offset boxIconOffset;

  /// The icon's size on a box.
  final Size boxIconSize;

  /// The icon's top-left from a row's top-right corner.
  final Offset rowIconOffset;

  /// The icon's size on a row.
  final Size rowIconSize;

  /// The hit area around the icon's top-left corner.
  final Rect hitArea;

  /// Whether no cell carries the affordance.
  bool get isNone => boxKinds.isEmpty && !onRows;

  /// The affordance of [cell] in [block], in layout coordinates, or null
  /// when the cell has none.
  ///
  /// [spoilerHidden] is whether a spoiler not yet revealed covers the item
  /// (a tap there only reveals); [smallImage] whether the cell is drawn as a
  /// small image (a link preview card's thumbnail).
  MediaOptionsAffordance? affordanceOf(
    MediaCell cell,
    MediaBlock block, {
    MediaChromeContext context = MediaChromeContext.none,
    bool spoilerHidden = false,
    bool smallImage = false,
  }) {
    if (context.compact || context.preview || spoilerHidden || smallImage) {
      return null;
    }
    final (offset, size) = switch (MediaLayoutPolicy.isBox(cell.kind)) {
      true when boxKinds.contains(cell.kind) => (boxIconOffset, boxIconSize),
      false when onRows && _isFirstRow(cell, block) => (
        rowIconOffset,
        rowIconSize,
      ),
      _ => (null, null),
    };
    if (offset == null || size == null) return null;
    final icon = (cell.rect.topRight + offset) & size;
    return MediaOptionsAffordance(
      iconRect: icon,
      hitRect: hitArea.shift(icon.topLeft),
    );
  }

  static bool _isFirstRow(MediaCell cell, MediaBlock block) => switch (block) {
    MediaBlock$FileStack(cells: [final first, ...]) =>
      first.itemId == cell.itemId,
    _ => true,
  };

  @override
  bool operator ==(Object other) =>
      other is MediaOptionsPlacement &&
      listEquals(other.boxKinds, boxKinds) &&
      other.onRows == onRows &&
      other.boxIconOffset == boxIconOffset &&
      other.boxIconSize == boxIconSize &&
      other.rowIconOffset == rowIconOffset &&
      other.rowIconSize == rowIconSize &&
      other.hitArea == hitArea;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(boxKinds),
    onRows,
    boxIconOffset,
    boxIconSize,
    rowIconOffset,
    rowIconSize,
    hitArea,
  );
}

/// The default options affordance: three vertical dots centred in its rect, white
/// with a soft shadow over a picture.
class MediaOptionsDots extends StatelessWidget {
  /// Dots of [color].
  const MediaOptionsDots({this.color = const Color(0xFFFFFFFF), super.key});

  /// The dots' colour.
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DotsPainter(color));
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Three dots of radius 2, 6 apart, centred in the rect, which may be
    // larger than the dots (a row's icon box).
    const spacing = 6.0;
    final radius = math.min(2, size.shortestSide / 2).toDouble();
    final centre = size.center(Offset.zero);
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    final fill = Paint()..color = color;
    for (var i = -1; i <= 1; i++) {
      final dot = centre + Offset(0, i * spacing);
      canvas
        ..drawCircle(dot, radius + 0.5, shadow)
        ..drawCircle(dot, radius, fill);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.color != color;
}
