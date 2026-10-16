import 'package:meta/meta.dart';

/// How far an asset has come, in order. There is no failed stage: an asset
/// that cannot be produced stays at the stage it reached (usually
/// [placeholder]) and is retried; see `AssetBinding.lastError`.
enum AssetStage {
  /// Nothing is known to draw yet; the binding paints the scope's placeholder.
  none,

  /// A cheap stand-in is available (a thumbnail, or for a glyph its circle
  /// until the glyph is baked).
  placeholder,

  /// The first frame, as a plain still, is available.
  firstFrame,

  /// The whole asset is available.
  full,
}

/// A binding's [stage] and whether it is [isFinal].
///
/// Final means nothing better will arrive for this entry, so a surface can
/// stop waiting: `full`, or `firstFrame` for a spec that asked for the first
/// frame only. A stage short of final is not an error, only unfinished.
@immutable
final class AssetReadiness {
  /// Creates a readiness at [stage].
  const AssetReadiness(this.stage, {this.isFinal = false});

  /// The best stage reached.
  final AssetStage stage;

  /// Whether no later stage will come.
  final bool isFinal;

  @override
  bool operator ==(Object other) =>
      other is AssetReadiness &&
      other.stage == stage &&
      other.isFinal == isFinal;

  @override
  int get hashCode => Object.hash(stage, isFinal);

  @override
  String toString() => 'AssetReadiness(${stage.name}, isFinal: $isFinal)';
}
