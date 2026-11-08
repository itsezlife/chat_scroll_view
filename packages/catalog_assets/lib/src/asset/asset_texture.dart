import 'package:meta/meta.dart';

/// A platform texture that holds an asset's current frame: the paint
/// capability `AssetPaintable.texture`.
///
/// A surface that composites adds a texture layer of [id] at the rectangle
/// [width] x [height] fits into; the whole texture is the frame, transparent
/// where the asset does not cover it. Read it when painting and never keep
/// it: the asset can give its texture back between two frames.
@immutable
final class AssetTexture {
  /// Describes texture [id] of [width] x [height] pixels.
  const AssetTexture({
    required this.id,
    required this.width,
    required this.height,
  });

  /// The engine's id of the texture (what a texture layer takes).
  final int id;

  /// Pixels of a row of the texture.
  final int width;

  /// Rows of the texture.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is AssetTexture &&
      other.id == id &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(id, width, height);

  @override
  String toString() => 'AssetTexture($id, ${width}x$height)';
}
