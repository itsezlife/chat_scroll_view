/// The numeric constants of the default media layout: the abstract mosaic
/// span, the single box clamps and the media corner radii.
///
/// They become the values of the message media policy; until then the
/// geometry reads them here. Values are logical pixels except where a row
/// says abstract units. [referenceDisplayMinSide] freezes the display-size
/// rescale the mosaic algorithm applies, so a layout is the same on every
/// host and in tests.
///
/// | Constant | Value | Role |
/// | --- | --- | --- |
/// | [groupedMaxSizeWidth] | 800 | Abstract mosaic width (span units) |
/// | [groupedMaxSizeHeight] | 814 | Abstract mosaic height (span units) |
/// | [firstSpanAdditionalSize] | 200 | Pad on the edge cells' span size |
/// | [minMediaHeight] | 120 | Single box and mosaic minimum height |
/// | [noDimensionsSide] | 150 | A box side the picture gives no size for |
/// | [minGroupedLineHeight] | 100 | Minimum mosaic line height |
/// | [singlePhotoHeightExtra] | 100 | Single box max height over its max width |
/// | [photoSizeCap] | 1280 | Soft cap on a single box side |
/// | [mediaOuterRadiusInset] | 2 | Outer media corner inset from the bubble radius |
/// | [mediaInnerRadius] | 4 | Corner between two mosaic cells |
/// | [mediaNearRadiusCap] | 3 | Outer corner next to a grouped neighbour bubble |
/// | [cellGap] | 1 | Seam between adjacent mosaic cells |
/// | [referenceDisplayMinSide] | 360 | Display short side the mosaic rescales by |
abstract final class MediaLayoutMetrics {
  /// Abstract mosaic width: the line budget of [GroupedMessages.calculate],
  /// in span units.
  static const double groupedMaxSizeWidth = 800;

  /// Abstract mosaic height; [GroupedMessagePosition.ph] is a fraction of
  /// this value.
  static const double groupedMaxSizeHeight = 814;

  /// Added to an edge cell's [GroupedMessagePosition.spanSize], so a grid
  /// that maps `spanSize / 1000` of its width fills the row.
  static const int firstSpanAdditionalSize = 200;

  /// Floor height after the aspect scale in [SingleMediaLayout.compute].
  static const double minMediaHeight = 120;

  /// The side of a single box whose picture gives no usable size, and of a
  /// side that truncates to zero.
  static const double noDimensionsSide = 150;

  /// Floor for a mosaic line's height before it is normalised.
  static const double minGroupedLineHeight = 100;

  /// A single box's max height is its max width plus this.
  static const double singlePhotoHeightExtra = 100;

  /// Soft upper bound on a single box's width and height.
  static const double photoSizeCap = 1280;

  /// Subtracted from the bubble radius, when it is above 2, to give the
  /// outer media corner.
  static const double mediaOuterRadiusInset = 2;

  /// Corner radius of a mosaic cell's corner that does not lie on the
  /// mosaic's outer edge (see [GroupedPositionFlags]).
  static const double mediaInnerRadius = 4;

  /// Cap [mediaNearRadius] applies to an outer corner the bubble shares with
  /// a grouped neighbour.
  static const double mediaNearRadiusCap = 3;

  /// Seam between adjacent mosaic cells in [MosaicLayout.project], half of
  /// it taken from each side of a shared edge.
  static const double cellGap = 1;

  /// Display short side, in logical pixels, that the mosaic algorithm's
  /// minimum width and paddings are rescaled by. Frozen so the layout does
  /// not depend on the host's screen.
  static const double referenceDisplayMinSide = 360;

  /// The outer media corner for [bubbleRadius]: the bubble radius less
  /// [mediaOuterRadiusInset] (17 gives 15), or the bubble radius itself when
  /// it is 2 or less.
  static double mediaOuterRadius({double bubbleRadius = 17}) {
    if (bubbleRadius > 2) {
      return bubbleRadius - mediaOuterRadiusInset;
    }
    return bubbleRadius;
  }

  /// The outer corner next to a grouped neighbour bubble:
  /// `min(mediaNearRadiusCap, mediaOuterRadius)`.
  static double mediaNearRadius({double bubbleRadius = 17}) {
    final outer = mediaOuterRadius(bubbleRadius: bubbleRadius);
    return mediaNearRadiusCap < outer ? mediaNearRadiusCap : outer;
  }
}
