import 'package:mpx_transfer/mpx_transfer.dart';

/// What the outbox uses of the transfer engine: making a publish job,
/// watching a chat's jobs, registering the chat's publisher, and the owner's
/// verbs on a job (cancel it, remove an item, commit it once it waits for
/// its owner). The host passes [OutboxTransfers.of] its one `Transfers`
/// facade.
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
}
