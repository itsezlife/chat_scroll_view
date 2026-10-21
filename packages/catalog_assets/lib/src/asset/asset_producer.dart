import 'package:catalog_assets/src/asset/asset_cache_budgets.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// What a producer is asked to make: the entry's identity.
@immutable
final class AssetRequest {
  /// Creates a request for [key] decoded as [spec].
  const AssetRequest(this.key, this.spec);

  /// Which content.
  final ContentKey key;

  /// Which pixels.
  final AssetSpec spec;

  @override
  bool operator ==(Object other) =>
      other is AssetRequest && other.key == key && other.spec == spec;

  @override
  int get hashCode => Object.hash(key, spec);

  @override
  String toString() => 'AssetRequest($key, $spec)';
}

/// How soon work for an entry is wanted. Producers that queue work order it by
/// this class, highest first.
enum AssetPriority {
  /// Nothing shows the entry: it is kept attached for later (a page beside
  /// the visible one). Served after everything a surface is waiting for.
  preload,

  /// A surface that shows the entry is waiting for it.
  visible,

  /// A cheap stand-in (a thumbnail) for an entry. Small and what the surface
  /// shows first, so served before the entries' full content; an attached
  /// entry's [AssetDemand] never reports it, a producer assigns it to the
  /// work it knows is a stand-in.
  placeholder,
}

/// What the surfaces attached to an entry want from its producer, read live:
/// the scope updates it as bindings attach, detach and show or hide.
abstract interface class AssetDemand {
  /// [AssetPriority.visible] while any attached binding shows the entry,
  /// [AssetPriority.preload] when all are hidden. Never
  /// [AssetPriority.placeholder].
  AssetPriority get priority;
}

/// Whether a failed attempt is worth repeating when the network comes back.
enum AssetFailureKind {
  /// The attempt may succeed later (offline, timeout, server busy). The scope
  /// repeats it for attached bindings when the host reports connectivity.
  transient,

  /// The attempt will not succeed by itself (undecodable data, missing
  /// content). Only a re-attach or an explicit `AssetBinding.retry` repeats it.
  permanent,
}

/// Where a producer reports what it makes for one entry. The scope hands one
/// to [AssetProducer.produce] per attempt.
///
/// Calls after the attempt ended (a final stage, [fail], [cancelled], or the
/// scope cancelling the task) are ignored, and a paintable passed to [advance]
/// then is disposed at once, so a late result cannot leak or corrupt a newer
/// attempt.
abstract interface class AssetProgress {
  /// Offers a better stage: [paintable] is the picture at [stage] and costs
  /// [bytes] while the entry keeps it. The cache owns [paintable] from this
  /// call on. A stage lower than the entry's current one is dropped (and its
  /// paintable disposed); an equal one replaces the current.
  ///
  /// The attempt ends when [stage] is final for the spec (`full`, or
  /// `firstFrame` for a first-frame-only spec). [tier] picks the budget the
  /// bytes count against.
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  });

  /// Ends the attempt without a result. The entry keeps its stage: a failure
  /// is never shown. [error] and [stackTrace] are kept for diagnostics
  /// (`AssetBinding.lastError`); [kind] tells whether connectivity helps.
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]);

  /// Ends the attempt because it was cancelled, which is not a failure: no
  /// error is recorded.
  void cancelled();
}

/// A running attempt, as the scope sees it.
abstract interface class AssetTask {
  /// Stops the attempt if it is still running and releases what it holds
  /// (network request, decode job). The scope calls it when the last binding
  /// of the entry leaves; it never reports through [AssetProgress] afterwards.
  void cancel();
}

/// Makes the paintables of the entries a scope does not make itself.
///
/// The seam between the cache core and whatever fetches, decodes and renders;
/// `AssetPipeline` is the implementation that fetches and decodes through the
/// host's `ContentFetcher` and `Decoder`s. The scope owns
/// everything else about an entry: one attempt at a time per entry, stage
/// bookkeeping, budgets, pinning, retry, cancellation when the last binding
/// leaves.
///
/// [produce] runs on the UI isolate and must return promptly; real work
/// happens elsewhere and reports through [progress], on the UI isolate too,
/// synchronously from [produce] if the result is already at hand. It never
/// throws for a failed attempt: it calls [AssetProgress.fail].
abstract interface class AssetProducer {
  /// Starts making [request], reporting to [progress]. [demand] stays valid
  /// for the whole attempt and says how urgent the work is.
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  );
}
