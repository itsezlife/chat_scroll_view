import 'package:catalog_assets/src/asset/asset_cache_budgets.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/pipeline/cancellation_token.dart';
import 'package:catalog_assets/src/pipeline/content_fetcher.dart';
import 'package:catalog_assets/src/pipeline/decoder.dart';
import 'package:catalog_assets/src/pipeline/descriptor_directory.dart';
import 'package:catalog_assets/src/pipeline/priority_lane.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// How much the pipeline does at once, and how much it remembers.
@immutable
final class AssetPipelineLimits {
  /// Creates limits; the defaults are described on each field.
  const AssetPipelineLimits({
    this.maxConcurrentFetches = 6,
    this.maxConcurrentDecodes = 2,
    this.maxFetchedAwaitingDecode = 16,
    this.knownDescriptors = 4096,
  }) : assert(
         maxConcurrentFetches > 0 &&
             maxConcurrentDecodes > 0 &&
             maxFetchedAwaitingDecode > 0 &&
             knownDescriptors > 0,
         'every limit is at least one',
       );

  /// Fetches running at once. The reference client runs 5 small and 2 large
  /// file loads; one lane of 6 serves both, because the size of a download
  /// is not known before it starts.
  final int maxConcurrentFetches;

  /// Decodes running at once. Decoders may work off the UI isolate, but a
  /// screenful of them would still compete with the frames that show the
  /// result.
  final int maxConcurrentDecodes;

  /// Fetched content that may wait for a decode slot before new fetches are
  /// held back. Bounds the bytes sitting in memory when decoding is slower
  /// than the network.
  final int maxFetchedAwaitingDecode;

  /// Descriptors remembered (host-given and resolved); the least recently
  /// used one is forgotten first and asked for again if it is needed.
  final int knownDescriptors;
}

/// Why the pipeline could not make an entry, when the cause is not a fetch or
/// decode failure.
final class AssetPipelineError implements Exception {
  /// Creates an error about [key] explained by [message].
  const AssetPipelineError(this.key, this.message);

  /// The content that could not be made.
  final ContentKey key;

  /// What is missing.
  final String message;

  @override
  String toString() => 'AssetPipelineError($key): $message';
}

/// The `AssetProducer` that makes the entries of an `AssetCacheScope` by
/// fetching and decoding: resolve what is unknown, fetch through the host's
/// [ContentFetcher], decode with the [Decoder] of the content's media form,
/// and report stages.
///
/// The scope already runs one attempt per entry and cancels it when the last
/// binding leaves; the pipeline adds what a screenful of entries needs on top:
///
/// - **Priority.** Work is served in classes: a thumbnail (the stand-in)
///   before content a surface is waiting for (`AssetPriority.visible`), and
///   that before content only kept attached (`AssetPriority.preload`); oldest
///   first within a class. The class of content work follows the entry's
///   `AssetDemand` while it waits. Running work is never preempted.
/// - **Caps.** At most `AssetPipelineLimits.maxConcurrentFetches` fetches and
///   `maxConcurrentDecodes` decodes run; fetched content waits for a decode
///   slot, and fetching is held back when too much waits.
/// - **Cancel.** Work still queued is dropped, a running fetch gets its
///   token cancelled and a running decode its task cancelled, and the slot is
///   free at once.
/// - **Unknown descriptors.** A key the pipeline has no descriptor for (see
///   [know]) goes to the host's [ContentResolver], batched with the others
///   asked for in the same turn; the entry stays at `AssetStage.none` until
///   it resolves.
///
/// ## Failure
///
/// None of it is shown: a failed attempt ends and the entry keeps its stage.
/// A failed fetch is transient or permanent as the fetcher says (anything but
/// a `FetchFailure` counts as transient); a resolver that throws is
/// transient; a key the resolver leaves out, no resolver, no decoder for the
/// media form and a decode failure are permanent. A failed thumbnail is
/// ignored: the content may still arrive.
///
/// ## Not the glyph path
///
/// Unicode glyphs bind to baked sprites through the scope's glyph source and
/// never reach the pipeline, so its caps and queues never delay them; the
/// baker is paced by frames on the root isolate, not by this queue.
///
/// Single-threaded on the UI isolate, like the scope.
final class AssetPipeline implements AssetProducer {
  /// Creates a pipeline over [fetcher] and [decoders].
  AssetPipeline({
    required ContentFetcher fetcher,
    required DecoderRegistry decoders,
    ContentResolver? resolver,
    AssetPipelineLimits limits = const AssetPipelineLimits(),
  }) : _fetcher = fetcher,
       _decoders = decoders,
       _directory = DescriptorDirectory(
         capacity: limits.knownDescriptors,
         resolver: resolver,
       ) {
    _decodeLane = PriorityLane(
      capacity: limits.maxConcurrentDecodes,
      start: _startDecode,
    );
    _fetchLane = PriorityLane(
      capacity: limits.maxConcurrentFetches,
      start: _startFetch,
      canStart: () =>
          _decodeLane.waitingCount < limits.maxFetchedAwaitingDecode,
    );
  }

  final ContentFetcher _fetcher;
  final DecoderRegistry _decoders;
  final DescriptorDirectory _directory;
  late final PriorityLane<_Work> _fetchLane;
  late final PriorityLane<_Work> _decodeLane;
  final Set<_Job> _jobs = {};
  bool _disposed = false;

  /// Tells the pipeline what the host already knows about content, so its
  /// entries need no resolver round trip. Replaces what was known for the
  /// descriptor's key.
  void know(ContentDescriptor descriptor) => _directory.add(descriptor);

  /// Cancels every attempt and forgets every descriptor. Idempotent. The
  /// fetcher, the decoders and the resolver stay the host's to dispose.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in List<_Job>.of(_jobs)) {
      job.cancel();
    }
    _directory.dispose();
  }

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    if (_disposed) throw StateError('AssetPipeline.produce after dispose.');
    final job = _Job(this, request, progress, demand);
    _jobs.add(job);
    job.start();
    return job;
  }

  void _startFetch(_Work work) {
    work.phase = _Phase.fetching;
    final token = work.token = CancellationToken();
    Future<FetchedContent> result;
    try {
      result = _fetcher.fetch(
        FetchRequest(
          descriptor: work.job.descriptor!,
          part: work.part,
          priority: work.priority,
          cancellation: token,
        ),
      );
    } on Object catch (error, stackTrace) {
      result = Future<FetchedContent>.error(error, stackTrace);
    }
    result.then(work.fetched, onError: work.fetchFailed);
  }

  void _startDecode(_Work work) {
    // Fetching may be waiting for the room this start made.
    work.phase = _Phase.decoding;
    final progress = work.decodeProgress = _DecodeProgress(work);
    try {
      final task = work.decoder.decode(
        DecodeRequest(
          descriptor: work.job.descriptor!,
          spec: work.job.request.spec,
          part: work.part,
          content: work.content!,
        ),
        progress,
      );
      if (progress.ended) {
        task.cancel();
      } else {
        progress.task = task;
      }
    } on Object catch (error, stackTrace) {
      progress.fail(error, stackTrace);
    }
    _fetchLane.pump();
  }
}

enum _Phase { queuedFetch, fetching, queuedDecode, decoding, done }

/// One attempt at one entry.
final class _Job implements AssetTask {
  _Job(this.pipeline, this.request, this.progress, this.demand);

  final AssetPipeline pipeline;
  final AssetRequest request;
  final AssetProgress progress;
  final AssetDemand demand;
  ContentDescriptor? descriptor;
  _Work? _thumbnail;
  _Work? _content;
  bool _ended = false;
  bool _resolving = false;

  void start() {
    final known = pipeline._directory.lookup(request.key);
    if (known != null) {
      _begin(known);
    } else if (pipeline._directory.canResolve) {
      _resolving = true;
      pipeline._directory.resolve(request.key, _resolved);
    } else {
      _fail(
        AssetPipelineError(
          request.key,
          'no descriptor is known and the pipeline has no ContentResolver',
        ),
        null,
        AssetFailureKind.permanent,
      );
    }
  }

  void _resolved(
    ContentDescriptor? resolved,
    Object? error,
    StackTrace? stackTrace,
  ) {
    _resolving = false;
    if (_ended) return;
    if (error != null) {
      _fail(error, stackTrace, AssetFailureKind.transient);
    } else if (resolved == null) {
      _fail(
        AssetPipelineError(request.key, 'the resolver does not know it'),
        null,
        AssetFailureKind.permanent,
      );
    } else {
      _begin(resolved);
    }
  }

  void _begin(ContentDescriptor known) {
    final decoder = pipeline._decoders.decoderFor(known.mediaForm);
    if (decoder == null) {
      _fail(
        AssetPipelineError(
          request.key,
          'no decoder is registered for ${known.mediaForm.name}',
        ),
        null,
        AssetFailureKind.permanent,
      );
      return;
    }
    descriptor = known;
    final content = _content = _Work(this, FetchPart.content, decoder);
    final thumbnail = switch (known.thumbnail) {
      null => null,
      _ => _thumbnail = _Work(this, FetchPart.thumbnail, decoder),
    };
    // The lane picks by priority, so the order of these two only breaks ties.
    if (thumbnail != null) pipeline._fetchLane.enqueue(thumbnail);
    if (!_ended) pipeline._fetchLane.enqueue(content);
    // enqueue may end the job when a fetcher answers by throwing.
  }

  /// The content reached its final stage.
  void contentDone() {
    if (_ended) return;
    _ended = true;
    _thumbnail?.cancel();
    pipeline._jobs.remove(this);
  }

  void _fail(Object error, StackTrace? stackTrace, AssetFailureKind kind) {
    if (_ended) return;
    _ended = true;
    pipeline._jobs.remove(this);
    _content?.cancel();
    _thumbnail?.cancel();
    progress.fail(error, stackTrace, kind);
  }

  /// A part failed. A thumbnail's failure is only its own.
  void workFailed(
    _Work work,
    Object error,
    StackTrace? stackTrace,
    AssetFailureKind kind,
  ) {
    if (work.part == FetchPart.content) _fail(error, stackTrace, kind);
  }

  /// The decoder gave up by itself (`AssetProgress.cancelled`).
  void contentCancelled() {
    if (_ended) return;
    _ended = true;
    pipeline._jobs.remove(this);
    _thumbnail?.cancel();
    progress.cancelled();
  }

  @override
  void cancel() {
    if (_ended) return;
    _ended = true;
    pipeline._jobs.remove(this);
    if (_resolving) pipeline._directory.cancel(request.key, _resolved);
    _content?.cancel();
    _thumbnail?.cancel();
  }
}

/// One part of an attempt on its way through the lanes.
final class _Work implements LaneWork {
  _Work(this.job, this.part, this.decoder);

  final _Job job;
  final FetchPart part;
  final Decoder decoder;
  _Phase phase = _Phase.queuedFetch;
  CancellationToken? token;
  FetchedContent? content;
  _DecodeProgress? decodeProgress;
  bool _cancelled = false;

  AssetPipeline get _pipeline => job.pipeline;

  @override
  AssetPriority get priority => part == FetchPart.thumbnail
      ? AssetPriority.placeholder
      : job.demand.priority;

  void fetched(FetchedContent fetchedContent) {
    if (_cancelled) return;
    content = fetchedContent;
    phase = _Phase.queuedDecode;
    _pipeline._decodeLane.enqueue(this);
    _pipeline._fetchLane.release(this);
  }

  void fetchFailed(Object error, StackTrace stackTrace) {
    if (_cancelled) return;
    phase = _Phase.done;
    _pipeline._fetchLane.release(this);
    final kind = switch (error) {
      FetchFailure(:final kind) => kind,
      _ => AssetFailureKind.transient,
    };
    job.workFailed(this, error, stackTrace, kind);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final was = phase;
    phase = _Phase.done;
    switch (was) {
      case _Phase.queuedFetch:
        _pipeline._fetchLane.remove(this);
      case _Phase.fetching:
        token?.cancel();
        _pipeline._fetchLane.release(this);
      case _Phase.queuedDecode:
        _pipeline._decodeLane.remove(this);
        _pipeline._fetchLane.pump();
      case _Phase.decoding:
        decodeProgress?.stop();
        _pipeline._decodeLane.release(this);
      case _Phase.done:
        break;
    }
  }
}

/// What a decoder reports to; relays to the scope's progress.
final class _DecodeProgress implements AssetProgress {
  _DecodeProgress(this._work);

  final _Work _work;
  AssetTask? task;
  bool ended = false;

  bool get _live => !ended && !_work._cancelled;

  /// Ends the decode from our side: cancels the decoder's task.
  void stop() {
    if (ended) return;
    ended = true;
    task?.cancel();
  }

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) {
    if (!_live) {
      paintable.dispose();
      return;
    }
    final job = _work.job;
    job.progress.advance(stage, paintable, bytes: bytes, tier: tier);
    final spec = job.request.spec;
    final isFinal =
        _work.part == FetchPart.thumbnail ||
        stage == AssetStage.full ||
        (stage == AssetStage.firstFrame &&
            spec.variant == AssetVariant.firstFrame);
    if (!isFinal) return;
    _end();
    if (_work.part == FetchPart.content) job.contentDone();
  }

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) {
    if (!_live) return;
    _end();
    // Decoding the same data again cannot succeed, whatever the network does.
    _work.job.workFailed(_work, error, stackTrace, AssetFailureKind.permanent);
  }

  @override
  void cancelled() {
    if (!_live) return;
    _end();
    if (_work.part == FetchPart.content) _work.job.contentCancelled();
  }

  void _end() {
    ended = true;
    _work.phase = _Phase.done;
    _work._pipeline._decodeLane.release(_work);
  }
}
