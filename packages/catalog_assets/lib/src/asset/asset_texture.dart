import 'package:meta/meta.dart';

/// A platform texture that holds an asset's current frame: the paint
/// capability `AssetPaintable.texture`.
///
/// The frame is [frameWidth] x [frameHeight] pixels, centred in the texture
/// of [width] x [height]; the margins are transparent. A surface that
/// composites adds a texture layer of [id] where `AssetFit.placeTexture`
/// puts it, so the frame lands where a still of the same frame would. Read
/// it when painting and never keep it: the asset can give its texture back
/// between two frames.
@immutable
final class AssetTexture {
  /// Describes texture [id] of [width] x [height] pixels holding a frame of
  /// [frameWidth] x [frameHeight] (the whole texture when they are null).
  const AssetTexture({
    required this.id,
    required this.width,
    required this.height,
    int? frameWidth,
    int? frameHeight,
  }) : frameWidth = frameWidth ?? width,
       frameHeight = frameHeight ?? height;

  /// The engine's id of the texture (what a texture layer takes).
  final int id;

  /// Pixels of a row of the texture.
  final int width;

  /// Rows of the texture.
  final int height;

  /// Pixels of a row of the frame, centred in the texture.
  final int frameWidth;

  /// Rows of the frame, centred in the texture.
  final int frameHeight;

  @override
  bool operator ==(Object other) =>
      other is AssetTexture &&
      other.id == id &&
      other.width == width &&
      other.height == height &&
      other.frameWidth == frameWidth &&
      other.frameHeight == frameHeight;

  @override
  int get hashCode => Object.hash(id, width, height, frameWidth, frameHeight);

  @override
  String toString() =>
      'AssetTexture($id, ${width}x$height, frame '
      '${frameWidth}x$frameHeight)';
}
