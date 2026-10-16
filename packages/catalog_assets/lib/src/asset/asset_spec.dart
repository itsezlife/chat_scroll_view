import 'package:meta/meta.dart';

/// How a decoder treats the colours of an asset.
enum AssetDecodeMode {
  /// The asset keeps its own colours.
  original,

  /// Only the alpha is kept and the surface tints it at paint time, so a
  /// text-coloured emoji is one cache entry however many colours it is drawn
  /// in. It is a decode choice, hence part of the entry identity.
  template,
}

/// How much of an asset a surface wants decoded.
enum AssetVariant {
  /// The whole asset: every frame of an animation.
  full,

  /// Only the first frame, as a plain still. A separate, cheaper entry than
  /// the full asset, and final as soon as it exists.
  firstFrame,
}

/// What is decoded for an entry: a pixel size, a decode mode and a variant.
///
/// A spec together with a `ContentKey` is the identity of a cache entry, so
/// two surfaces that ask for the same pixels share one decode, and the same
/// content at two sizes is two entries. It carries pixels rather than a
/// surface name on purpose: "34 dp at density 3" and "102 px" are the same
/// request, and no closed list of surface classes can say either.
///
/// What a surface does with an entry (animate it, loop it, round it) is an
/// `AssetProfile`; profiles never split entries.
@immutable
final class AssetSpec {
  /// Creates a spec for a decode of [pixelWidth] x [pixelHeight] pixels.
  const AssetSpec({
    required this.pixelWidth,
    required this.pixelHeight,
    this.decodeMode = AssetDecodeMode.original,
    this.variant = AssetVariant.full,
  }) : assert(
         pixelWidth > 0 && pixelHeight > 0,
         'An AssetSpec needs a positive size.',
       );

  /// The spec of a [logicalWidth] x [logicalHeight] box shown at
  /// [devicePixelRatio], rounded up to whole pixels so the decode is never
  /// smaller than the box it fills.
  factory AssetSpec.atDensity({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    AssetDecodeMode decodeMode = AssetDecodeMode.original,
    AssetVariant variant = AssetVariant.full,
  }) => AssetSpec(
    pixelWidth: (logicalWidth * devicePixelRatio).ceil(),
    pixelHeight: (logicalHeight * devicePixelRatio).ceil(),
    decodeMode: decodeMode,
    variant: variant,
  );

  /// Decoded width in pixels.
  final int pixelWidth;

  /// Decoded height in pixels.
  final int pixelHeight;

  /// Whether colours are kept or only alpha.
  final AssetDecodeMode decodeMode;

  /// Whether the whole asset or only its first frame is wanted.
  final AssetVariant variant;

  /// Bytes of one decoded RGBA frame at this size. A producer that holds more
  /// (frame buffers of an animation) reports its own cost.
  int get estimatedBytes => pixelWidth * pixelHeight * 4;

  @override
  bool operator ==(Object other) =>
      other is AssetSpec &&
      other.pixelWidth == pixelWidth &&
      other.pixelHeight == pixelHeight &&
      other.decodeMode == decodeMode &&
      other.variant == variant;

  @override
  int get hashCode => Object.hash(pixelWidth, pixelHeight, decodeMode, variant);

  @override
  String toString() =>
      'AssetSpec(${pixelWidth}x$pixelHeight, ${decodeMode.name}, '
      '${variant.name})';
}
