/// What a Lottie file uses that the renderer does not draw.
///
/// A bitmask over the wrapper's `features` field. Informational: a file that
/// uses these still loads and renders, minus the feature, and the host decides
/// whether that is acceptable. An extension type, not an enum set, because the
/// value crosses the C boundary as one integer and costs nothing to wrap.
extension type const LottieFeatures(int bits) {
  /// No unrendered feature is used.
  static const none = LottieFeatures(0);

  /// Layer effects.
  static const effects = LottieFeatures(1);

  /// Expressions.
  static const expressions = LottieFeatures(2);

  /// Image layers or image assets.
  static const imageLayers = LottieFeatures(4);

  /// Text layers.
  static const textLayers = LottieFeatures(8);

  /// Whether no feature is used.
  bool get isEmpty => bits == 0;

  /// Whether every flag of [other] is set here.
  bool contains(LottieFeatures other) => bits & other.bits == other.bits;

  /// The flags of both.
  LottieFeatures operator |(LottieFeatures other) =>
      LottieFeatures(bits | other.bits);
}
