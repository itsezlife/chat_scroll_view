import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/src/pipeline/content_fetcher.dart';
import 'package:catalog_assets/src/pipeline/testing/manual_clock.dart';
import 'package:content_model/content_model.dart';

/// One fetch a [FakeFetcher] was asked for; a test plays the network by
/// calling [complete] and [fail].
final class FakeFetch {
  FakeFetch._(this.request, this._fetcher);

  /// What was asked for.
  final FetchRequest request;

  final FakeFetcher _fetcher;
  final Completer<FetchedContent> _completer = Completer();

  /// Whether the pipeline cancelled this fetch.
  bool get isCancelled => request.cancellation.isCancelled;

  /// Whether the fetch has an outcome (a result, a failure or a cancel).
  bool get isSettled => _completer.isCompleted;

  /// Completes with [content], or with what the fetcher serves for this
  /// request (a permanent failure when it serves nothing). Does nothing once
  /// settled.
  void complete([FetchedContent? content]) {
    if (isSettled) return;
    final served = content ?? _fetcher._served(request);
    if (served == null) {
      fail(const FetchFailure.permanent('not found'));
      return;
    }
    _fetcher._settled(this);
    _completer.complete(served);
  }

  /// Fails with [failure]. Does nothing once settled.
  void fail(FetchFailure failure) => failWith(failure);

  /// Fails with any [error], as a fetcher that does not follow the contract
  /// would. Does nothing once settled.
  void failWith(Object error) {
    if (isSettled) return;
    _fetcher._settled(this);
    _completer.completeError(error);
  }

  /// A fetcher stops on cancel and settles its future.
  void _onCancel() => fail(const FetchFailure.transient('cancelled'));
}

/// An in-memory [ContentFetcher] for tests: it serves fixed content, can go
/// offline, and either answers by itself or waits for the test.
///
/// Follows the whole seam contract: a missing thing is a permanent failure,
/// being offline a transient one, and a cancelled fetch settles at once.
final class FakeFetcher implements ContentFetcher {
  /// Creates a fetcher that serves [contents] (by key) and [thumbnails] (by
  /// reference).
  ///
  /// With [autoRespond] every fetch is answered [latency] later on [clock]
  /// (the next microtask without a clock); without it each waits for
  /// [FakeFetch.complete] or [FakeFetch.fail].
  FakeFetcher({
    Map<ContentKey, FetchedContent> contents = const {},
    Map<ThumbnailRef, FetchedContent> thumbnails = const {},
    this.autoRespond = true,
    this.latency = Duration.zero,
    this.clock,
  }) : _contents = {...contents},
       _thumbnails = {...thumbnails};

  final Map<ContentKey, FetchedContent> _contents;
  final Map<ThumbnailRef, FetchedContent> _thumbnails;

  /// Whether fetches answer by themselves.
  final bool autoRespond;

  /// How long an automatic answer takes on [clock].
  final Duration latency;

  /// The clock automatic answers wait on, or null for the next microtask.
  final ManualClock? clock;

  /// Whether the network is there. While false, every new fetch fails with a
  /// transient failure.
  bool online = true;

  /// Every fetch, oldest first.
  final List<FakeFetch> fetches = [];
  int _active = 0;
  int _peak = 0;

  /// Serves [content] for [key] from now on.
  void serve(ContentKey key, FetchedContent content) =>
      _contents[key] = content;

  /// Serves [content] as the thumbnail [ref] from now on.
  void serveThumbnail(ThumbnailRef ref, FetchedContent content) =>
      _thumbnails[ref] = content;

  /// Fetches that have no outcome yet.
  List<FakeFetch> get pending => [
    for (final fetch in fetches)
      if (!fetch.isSettled) fetch,
  ];

  /// How many fetches are unsettled right now.
  int get active => _active;

  /// The most fetches that were ever unsettled at once.
  int get peakConcurrency => _peak;

  /// The fetches made for [part] of [key].
  List<FakeFetch> fetchesOf(ContentKey key, [FetchPart? part]) => [
    for (final fetch in fetches)
      if (fetch.request.descriptor.key == key &&
          (part == null || fetch.request.part == part))
        fetch,
  ];

  @override
  Future<FetchedContent> fetch(FetchRequest request) {
    final fetch = FakeFetch._(request, this);
    fetches.add(fetch);
    _peak = math.max(_peak, ++_active);
    request.cancellation.onCancel(fetch._onCancel);
    if (!online) {
      scheduleMicrotask(
        () => fetch.fail(const FetchFailure.transient('offline')),
      );
    } else if (autoRespond) {
      final wait = clock?.delay(latency) ?? Future<void>.value();
      unawaited(wait.then((_) => fetch.complete()));
    }
    return fetch._completer.future;
  }

  FetchedContent? _served(FetchRequest request) => switch (request.part) {
    FetchPart.thumbnail => _thumbnails[request.descriptor.thumbnail],
    FetchPart.content => _contents[request.descriptor.key],
  };

  void _settled(FakeFetch fetch) => _active--;
}
