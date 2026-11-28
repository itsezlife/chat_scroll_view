import 'dart:typed_data';

import 'package:mpx_transfer/mpx_transfer.dart';

/// What the outbox uses of the transfer engine: making a publish job,
/// watching a chat's jobs, registering the chat's publisher, and the owner's
/// verbs on a job (cancel it, remove an item, commit it once it waits for
/// its owner, retry it after a failure). The host passes
/// [OutboxTransfers.of] its one `Transfers` facade.
///
/// The outbox reaches the engine through this seam rather than through
/// `Transfers` itself because `Transfers` and its `PublishJob` handles are
/// final and built only by the engine: a test of the outbox, or of a host
/// that drives one, could not stand in for them. The seam names only what
/// the outbox calls, and grows with it.
abstract interface class OutboxTransfers {
  /// The seam over [transfers], the host's facade.
  factory OutboxTransfers.of(Transfers transfers) = _OutboxTransfers$Engine;

  /// Makes a publish job for [request] and answers its id.
  ///
  /// Throws as `Transfers.publish` does: for an item that needs preparation
  /// on a facade without it, an item id given twice, or a facade that runs
  /// no uploads.
  PublishJobId publish(PublishRequest request);

  /// Snapshots of every publish job [filter] passes, oldest first: the
  /// current list on listen, then the list again whenever one of its jobs
  /// changes, as `Transfers.watchJobs` gives them.
  Stream<List<PublishJobSnapshot>> watchJobs(PublishJobFilter filter);

  /// Registers [publisher] under [id], replacing any registered before; the
  /// jobs waiting for it publish, as `Transfers.registerPublisher` does.
  void registerPublisher(String id, Publisher publisher);

  /// Cancels job [id] in any state, as `PublishJob.cancel` does: its
  /// preparations and uploads stop and the job leaves [watchJobs]; the jobs
  /// behind it in its ordering group go on. Answers false for a job the
  /// engine no longer has.
  bool cancel(PublishJobId id);

  /// Removes item [itemId] from job [id], as `PublishJob.removeItem` does:
  /// its uploads stop and the job goes on with the other items. Removing
  /// the last one leaves the job `awaitingOwner`, publishing nothing until
  /// it is [commit]ted or [cancel]led. Answers false for an unknown item or
  /// a job that ended.
  bool removeItem(PublishJobId id, String itemId);

  /// Lets job [id], waiting for its owner, publish what it has left, as
  /// `PublishJob.commit` does; the job takes its place at the end of its
  /// ordering group. Answers false for any other job.
  bool commit(PublishJobId id);

  /// Retries job [id] after a failure, as `PublishJob.retry` does: only what
  /// failed repeats (a finished preparation and every journaled upload are
  /// kept; a job failed at publish publishes again, with the same
  /// idempotency key, and uploads nothing), and a job of an ordering group
  /// joins the end of its group. Answers false when there is nothing to
  /// retry: an unknown or completed job, or one with no failure.
  bool retry(PublishJobId id);

  /// Retries item [itemId] of job [id] alone, as `PublishJob.retryItem`
  /// does; with [source] the item's file uploads again from it, from zero
  /// (the way back from a lost source). Answers false for an item that has
  /// not failed, or a job that ended any other way than failed.
  bool retryItem(PublishJobId id, String itemId, {SourceBytes? source});

  /// The payload job [id] was made with, as its journal holds it; null for
  /// a job the engine no longer has.
  ///
  /// The outbox reads it after a restart, when the job's message is known
  /// only from the journal: it decodes the payload into the host's model to
  /// build the message's row again.
  Uint8List? payloadOf(PublishJobId id);
}

final class _OutboxTransfers$Engine implements OutboxTransfers {
  _OutboxTransfers$Engine(this._transfers);

  final Transfers _transfers;

  @override
  PublishJobId publish(PublishRequest request) =>
      _transfers.publish(request).id;

  @override
  Stream<List<PublishJobSnapshot>> watchJobs(PublishJobFilter filter) =>
      _transfers.watchJobs(filter);

  @override
  void registerPublisher(String id, Publisher publisher) =>
      _transfers.registerPublisher(id, publisher);

  @override
  bool cancel(PublishJobId id) => _transfers.publishJob(id)?.cancel() ?? false;

  @override
  bool removeItem(PublishJobId id, String itemId) =>
      _transfers.publishJob(id)?.removeItem(itemId) ?? false;

  @override
  bool commit(PublishJobId id) => _transfers.publishJob(id)?.commit() ?? false;

  @override
  bool retry(PublishJobId id) => _transfers.publishJob(id)?.retry() ?? false;

  @override
  bool retryItem(PublishJobId id, String itemId, {SourceBytes? source}) =>
      _transfers.publishJob(id)?.retryItem(itemId, source: source) ?? false;

  @override
  Uint8List? payloadOf(PublishJobId id) => _transfers.publishJob(id)?.payload;
}
