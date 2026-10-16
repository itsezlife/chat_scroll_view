import 'package:catalog_assets/src/asset/asset_cache_budgets.dart';
import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/testing/fake_asset_paintable.dart';

/// One attempt a [FakeAssetProducer] was asked to make; the test plays the
/// producer by calling [advance], [fail] and [cancelled].
final class FakeAssetAttempt implements AssetTask {
  FakeAssetAttempt._(this.request, this._progress);

  /// What was asked for.
  final AssetRequest request;

  final AssetProgress _progress;

  /// Whether the scope cancelled this attempt.
  bool isCancelled = false;

  /// Paintables handed to the cache by this attempt.
  final List<FakeAssetPaintable> paintables = [];

  /// Reports [stage] with a fresh paintable and returns it.
  FakeAssetPaintable advance(
    AssetStage stage, {
    int bytes = 100,
    AssetTier tier = AssetTier.still,
    bool animated = false,
  }) {
    final paintable = FakeAssetPaintable(
      label: '${request.key}@${stage.name}',
      isAnimated: animated,
    );
    paintables.add(paintable);
    _progress.advance(stage, paintable, bytes: bytes, tier: tier);
    return paintable;
  }

  /// Reports a failed attempt.
  void fail(
    Object error, {
    AssetFailureKind kind = AssetFailureKind.transient,
  }) => _progress.fail(error, StackTrace.current, kind);

  /// Reports that the work was cancelled by its own side.
  void cancelled() => _progress.cancelled();

  @override
  void cancel() => isCancelled = true;
}

/// An [AssetProducer] that does nothing by itself: every attempt waits for the
/// test to report.
final class FakeAssetProducer implements AssetProducer {
  /// Every attempt started, oldest first.
  final List<FakeAssetAttempt> attempts = [];

  /// Called inside [produce] for each new attempt, to answer synchronously
  /// like a memory hit.
  void Function(FakeAssetAttempt attempt)? onProduce;

  /// The attempts made for [request].
  List<FakeAssetAttempt> attemptsFor(AssetRequest request) => [
    for (final attempt in attempts)
      if (attempt.request == request) attempt,
  ];

  /// The attempt started last.
  FakeAssetAttempt get last => attempts.last;

  @override
  AssetTask produce(AssetRequest request, AssetProgress progress) {
    final attempt = FakeAssetAttempt._(request, progress);
    attempts.add(attempt);
    onProduce?.call(attempt);
    return attempt;
  }
}
