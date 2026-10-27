import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// One painted piece of a message surface that is not one outline, such as the
/// art of a sticker or the time pill beside it.
///
/// [rect] is in the coordinates of the box the surface is reported for
/// (`ChatMessageSurfaceBounds`): its top left is the box's top left.
@immutable
class ChatMessageSurfacePart {
  /// Creates a part covering [rect] in [shape].
  ///
  /// The default [shape] is the square rectangle: a sticker's art or a
  /// glyph run has no outline of its own to round.
  const ChatMessageSurfacePart({required this.rect, this.shape = const RoundedRectangleBorder()});

  /// Where the part is, in the reported box's coordinates.
  final Rect rect;

  /// The outline of the part inside [rect]. A directional shape resolves
  /// against the menu overlay's [Directionality], like every surface shape.
  final ShapeBorder shape;

  @override
  bool operator ==(Object other) => other is ChatMessageSurfacePart && other.rect == rect && other.shape == shape;

  @override
  int get hashCode => Object.hash(rect, shape);
}

/// The outline of a message surface made of separate painted parts, for the
/// message menu's scrim hole.
///
/// A message with a bubble is one outline. One without (an emoji-only message,
/// a sticker, a round video) paints a few unrelated pieces: the art, a time
/// pill laid over it, a reply panel above it, a row of reactions under it. The
/// reference clients redraw the message itself above the dim, so exactly those
/// pieces stay bright and what lies between them stays dimmed. One rounded
/// rectangle around the lot reads as a bubble that is not there and lights the
/// wallpaper in the gaps; this shape leaves the gaps dim.
///
/// Pass it as `ChatMessageSurfaceBounds.shape` around a box that holds every
/// part. The path is the union of the parts moved to the box's origin, so it
/// follows the live box while the list scrolls. It only describes an outline:
/// [paint] draws nothing, and the box rect still decides Inside versus
/// Outside for the menu request.
@immutable
class ChatMessageSurfaceParts extends ShapeBorder {
  /// Creates a surface of [parts].
  const ChatMessageSurfaceParts(this.parts);

  /// The painted pieces, in the reported box's coordinates.
  final List<ChatMessageSurfacePart> parts;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path();
    for (final part in parts) {
      path.addPath(part.shape.getOuterPath(part.rect.shift(rect.topLeft), textDirection: textDirection), Offset.zero);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => ChatMessageSurfaceParts(<ChatMessageSurfacePart>[
    for (final part in parts)
      ChatMessageSurfacePart(
        rect: Rect.fromLTRB(part.rect.left * t, part.rect.top * t, part.rect.right * t, part.rect.bottom * t),
        shape: part.shape.scale(t),
      ),
  ]);

  @override
  bool operator ==(Object other) => other is ChatMessageSurfaceParts && listEquals(other.parts, parts);

  @override
  int get hashCode => Object.hashAll(parts);
}
