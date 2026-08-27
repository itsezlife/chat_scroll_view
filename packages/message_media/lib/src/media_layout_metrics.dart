/// TRACE’d layout constants from Telegram Java (`MessageObject.GroupedMessages`,
/// `ChatMessageCell` photo measure / round radius).
///
/// Owns: frozen numeric contracts for abstract mosaic span, single-media
/// clamps, and media corner radii. Does not own: host bubble theme objects or
/// density-dependent Android `DisplayMetrics` — [referenceDisplayMinSide]
/// freezes that rescale for deterministic tests.
///
/// Values are logical pixels (Flutter) matching Android `dp(N)` at density 1
/// for measure inputs, and abstract span units where noted.
///
/// | Flutter | Java | Role | Trace |
/// | --- | --- | --- | --- |
/// | [groupedMaxSizeWidth] `800` | `maxSizeWidth = 800` | Abstract mosaic span | `GroupedMessages.calculate` |
/// | [groupedMaxSizeHeight] `814` | `maxSizeHeight = 814f` | Abstract mosaic height | same |
/// | [firstSpanAdditionalSize] `200` | `firstSpanAdditionalSize = 200` | Edge span pad toward `/1000` map | same |
/// | [minMediaHeight] `120` | `dp(120)` | Single + group min height | `getMessageSize` / calculate |
/// | [minGroupedLineHeight] `100` | `dp(100)` → `minH` | Min ph fraction | calculate |
/// | [singlePhotoHeightExtra] `100` | `photoHeight = photoWidth + dp(100)` | Single max height budget | ChatMessageCell |
/// | [photoSizeCap] `1280` | `AndroidUtilities.getPhotoSize()` | Soft cap on single box | AndroidUtilities |
/// | [mediaOuterRadiusInset] `2` | `bubbleRadius - 2` | Outer media radius inset | setRoundRadius |
/// | [mediaInnerRadius] `4` | `minRad = dp(4)` | Inner mosaic corners | setRoundRadius |
/// | [mediaNearRadiusCap] `3` | `nearRad = min(dp(3), rad)` | Clustered outer media | setRoundRadius |
/// | [cellGap] `1` | ≈1dp background seam between cells | Mosaic cell gap | visual / cell insets |
/// | [referenceDisplayMinSide] `360` | typical phone `min(displaySize)` logical | `minWidth` / paddings | calculate |
abstract final class MediaLayoutMetrics {
  /// Abstract mosaic width unit used as the `pw` / line budget in calculate.
  static const double groupedMaxSizeWidth = 800;

  /// Abstract mosaic height unit; [GroupedMessagePosition.ph] is a fraction of
  /// this value.
  static const double groupedMaxSizeHeight = 814;

  /// Added to edge [GroupedMessagePosition.spanSize] so chat-cell
  /// `pw / 1000 * width` mapping fills the available row.
  static const int firstSpanAdditionalSize = 200;

  /// Floor height after aspect scale in [computeSingleMediaSize] (`dp(120)`).
  static const double minMediaHeight = 120;

  /// Floor for grouped line `ph` before normalize (`dp(100) / maxSizeHeight`).
  static const double minGroupedLineHeight = 100;

  /// Single-media max height budget is `maxWidth + singlePhotoHeightExtra`.
  static const double singlePhotoHeightExtra = 100;

  /// Soft upper bound on single-media width/height (non-HQ photo size).
  static const double photoSizeCap = 1280;

  /// Subtracted from host bubble radius when `bubbleRadius > 2` to get the
  /// large (outer) media corner.
  static const double mediaOuterRadiusInset = 2;

  /// Corner radius on mosaic edges that do **not** carry the corresponding
  /// [GroupedPositionFlags] bit (inner seams).
  static const double mediaInnerRadius = 4;

  /// Cap applied by [mediaNearRadius] for clustered outer corners (pinned
  /// neighbor runs), independent of the full outer radius.
  static const double mediaNearRadiusCap = 3;

  /// Inset seam between adjacent mosaic cells in [MosaicLayout.project]
  /// (half applied on each shared edge).
  static const double cellGap = 1;

  /// Frozen `min(displaySize.x, displaySize.y)` in logical px so
  /// [GroupedMessages.calculate]’s `minWidth` / `paddingsWidth` rescale is
  /// deterministic across hosts.
  static const double referenceDisplayMinSide = 360;

  /// Large (solitary / outer-flag) media corner for [bubbleRadius].
  ///
  /// Default bubble radius 17 → 15. When `bubbleRadius ≤ 2`, returns
  /// [bubbleRadius] unchanged (Java branch).
  static double mediaOuterRadius({double bubbleRadius = 17}) {
    if (bubbleRadius > 2) {
      return bubbleRadius - mediaOuterRadiusInset;
    }
    return bubbleRadius;
  }

  /// Clustered (“near”) outer media corner: `min(mediaNearRadiusCap, outer)`.
  ///
  /// Used when a host bubble is pinned to a neighbor on that corner; mosaic
  /// placeholders that ignore run clustering keep [mediaOuterRadius] instead.
  static double mediaNearRadius({double bubbleRadius = 17}) {
    final outer = mediaOuterRadius(bubbleRadius: bubbleRadius);
    return mediaNearRadiusCap < outer ? mediaNearRadiusCap : outer;
  }
}
