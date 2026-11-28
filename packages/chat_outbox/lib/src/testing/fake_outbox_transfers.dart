import 'dart:async';
import 'dart:typed_data';

import 'package:chat_outbox/src/transfers/outbox_transfers.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// An [OutboxTransfers] with no engine behind it, for tests of the outbox
/// and of hosts that drive one: it records every request, and each job
/// stays in the state the test scripts until the test moves it.
///
/// A new job starts at its first stage, each item `waiting`: `preparing`
/// when an item needs preparing, `uploading` when one is ready to upload,
/// `publishing` when there is nothing to upload (no items, or only remote
/// ones). [setState] moves a job (and, given, its
/// items); [remove] takes it away, as the engine does with a cancelled job.
/// [seed] puts a job in as an earlier run's journal holds it, for a
/// simulated restart, and [payloadOf] answers each job's payload.
/// Watchers get the current list on listen and the list again after each
/// change, asynchronously, as the engine's do.
///
/// A job of a registered publisher publishes as the engine's does: when it
/// reaches `publishing` (made so, moved there by [setState], or waiting
/// there when [registerPublisher] names its publisher) the publisher is
/// called with the job's payload, an item reference per item (none for a
/// `remote` one) and the job's idempotency key, and its answer ends the
/// job: `published` completes it, `rejected` fails it at the publish stage,
/// a throw fails it as `publisherError`. A `reuploadItems` answer is
/// recorded in [reuploadsOf] and the job publishes again at once, as if the
/// items had uploaded; a second one fails it as `reuploadRefused`. With no
/// publisher registered a job at `publishing` stays there until the test
/// moves it (`awaitingPublisher` is the test's to script).
///
/// The owner's verbs act as the engine's: [cancel] takes the job away,
/// [removeItem] drops an item (the last one leaves the job
/// `awaitingOwner`), and [commit] lets a job waiting for its owner publish
/// what it has left; each is recorded ([cancelled], [removedItems],
/// [committed]). [cancelUpload] drops an item as the status control's
/// cancel of its upload does, which the owner reads from the jobs.
final class FakeOutboxTransfers implements OutboxTransfers {
  /// A fake with no jobs.
  FakeOutboxTransfers();

  final List<PublishRequest> _requests = [];
  final Map<PublishJobId, PublishRequest> _$requestOf = {};
  final Map<String, Publisher> _$publishers = {};
  final Set<PublishJobId> _$attempting = {};
  final Map<PublishJobId, List<Set<String>>> _$reuploads = {};
  final Map<PublishJobId, int> _$attempts = {};
  final List<PublishJobSnapshot> _jobs = [];
  final Set<_Watcher> _$watchers = {};
  DateTime _$clock = DateTime.utc(2026);

  /// Every request so far, in order.
  List<PublishRequest> get requests => List.unmodifiable(_requests);

  /// The jobs the fake holds now, oldest first.
  List<PublishJobSnapshot> get jobs => List.unmodifiable(_jobs);

  /// How many watchers are listening now.
  int get watcherCount => _$watchers.length;

  /// The publisher registered under [id], or null.
  Publisher? publisherOf(String id) => _$publishers[id];

  /// How many times job [id]'s publisher was called.
  int attemptsOf(PublishJobId id) => _$attempts[id] ?? 0;

  /// The item ids of each `reuploadItems` answer for job [id], in order.
  List<Set<String>> reuploadsOf(PublishJobId id) =>
      List.unmodifiable(_$reuploads[id] ?? const <Set<String>>[]);

  @override
  void registerPublisher(String id, Publisher publisher) {
    _$publishers[id] = publisher;
    for (final job in [..._jobs]) {
      if (job.publisher != id) continue;
      if (job.state
          case PublishJobState$Publishing() ||
              PublishJobState$AwaitingPublisher()) {
        _attempt(job.id);
      }
    }
  }

  @override
  PublishJobId publish(PublishRequest request) {
    _requests.add(request);
    final id = PublishJobId.parse('job-${_requests.length}');
    _jobs.add(
      PublishJobSnapshot(
        id: id,
        tag: request.tag,
        publisher: request.publisher,
        createdAt: _$clock = _$clock.add(const Duration(seconds: 1)),
        state: _firstStateOf(request),
        items: [
          for (final item in request.items)
            PublishItemSnapshot(
              itemId: item.itemId,
              key: item.key,
              state: const PublishItemState.waiting(),
            ),
        ],
      ),
    );
    _$requestOf[id] = request;
    _changed();
    if (_jobs.last.state is PublishJobState$Publishing) _attempt(id);
    return id;
  }

  /// Puts a job for [request] in the fake as an earlier run's journal holds
  /// it, in [state] (its first stage unless given), [items] giving its
  /// items' states by item id (each `waiting` unless given), and answers
  /// its id: the jobs an outbox finds after a restart.
  ///
  /// Unlike [publish], it calls no publisher: a seeded job at its publish
  /// stage waits for [registerPublisher], as a restored one does.
  PublishJobId seed(
    PublishRequest request, {
    PublishJobState? state,
    Map<String, PublishItemState> items = const {},
  }) {
    _requests.add(request);
    final id = PublishJobId.parse('job-${_requests.length}');
    _jobs.add(
      PublishJobSnapshot(
        id: id,
        tag: request.tag,
        publisher: request.publisher,
        createdAt: _$clock = _$clock.add(const Duration(seconds: 1)),
        state: state ?? _firstStateOf(request),
        items: [
          for (final item in request.items)
            PublishItemSnapshot(
              itemId: item.itemId,
              key: item.key,
              state: items[item.itemId] ?? const PublishItemState.waiting(),
            ),
        ],
      ),
    );
    _$requestOf[id] = request;
    _changed();
    return id;
  }

  @override
  Uint8List? payloadOf(PublishJobId id) =>
      _jobs.any((job) => job.id == id) ? _$requestOf[id]?.payload : null;

  /// Moves job [id] to [state]; [items] gives the new state of the items
  /// it names by item id, the others keeping theirs.
  ///
  /// Throws a [StateError] for a job the fake does not hold.
  void setState(
    PublishJobId id,
    PublishJobState state, {
    Map<String, PublishItemState> items = const {},
  }) {
    final index = _indexOf(id);
    final job = _jobs[index];
    _jobs[index] = PublishJobSnapshot(
      id: job.id,
      tag: job.tag,
      publisher: job.publisher,
      createdAt: job.createdAt,
      state: state,
      items: [
        for (final item in job.items)
          PublishItemSnapshot(
            itemId: item.itemId,
            key: item.key,
            state: items[item.itemId] ?? item.state,
          ),
      ],
    );
    _changed();
    if (state is PublishJobState$Publishing) _attempt(id);
  }

  /// Takes job [id] away, as the engine does with a cancelled job.
  void remove(PublishJobId id) {
    _jobs.removeAt(_indexOf(id));
    _changed();
  }

  /// The jobs the owner cancelled through [cancel], in order.
  List<PublishJobId> get cancelled => List.unmodifiable(_$cancelled);

  /// The items the owner removed through [removeItem], in order, as (job,
  /// item id).
  List<(PublishJobId, String)> get removedItems =>
      List.unmodifiable(_$removedItems);

  /// The jobs the owner committed through [commit], in order.
  List<PublishJobId> get committed => List.unmodifiable(_$committed);

  final List<PublishJobId> _$cancelled = [];
  final List<(PublishJobId, String)> _$removedItems = [];
  final List<PublishJobId> _$committed = [];

  @override
  bool cancel(PublishJobId id) {
    if (!_jobs.any((job) => job.id == id)) return false;
    _$cancelled.add(id);
    remove(id);
    return true;
  }

  @override
  bool removeItem(PublishJobId id, String itemId) {
    if (!_drop(id, itemId)) return false;
    _$removedItems.add((id, itemId));
    return true;
  }

  /// The status control's cancel of item [itemId]'s upload in job [id]
  /// (`TrackedTransfers.cancel` by its key): the item leaves the job as
  /// with [removeItem], without the owner asking, so the owner reads it
  /// from [watchJobs]. Answers false as [removeItem] does.
  bool cancelUpload(PublishJobId id, String itemId) => _drop(id, itemId);

  @override
  bool commit(PublishJobId id) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0 || _jobs[index].state is! PublishJobState$AwaitingOwner) {
      return false;
    }
    _$committed.add(id);
    setState(id, const PublishJobState.publishing());
    return true;
  }

  /// Takes item [itemId] out of job [id]: the last one leaves the job
  /// waiting for its owner, unless its publisher runs (the engine shows a
  /// job publishing then, and the publisher's answer ends it).
  bool _drop(PublishJobId id, String itemId) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return false;
    final job = _jobs[index];
    if (job.state
        case PublishJobState$Completed() || PublishJobState$Failed()) {
      return false;
    }
    if (!job.items.any((item) => item.itemId == itemId)) return false;
    final left = [
      for (final item in job.items)
        if (item.itemId != itemId) item,
    ];
    _jobs[index] = PublishJobSnapshot(
      id: job.id,
      tag: job.tag,
      publisher: job.publisher,
      createdAt: job.createdAt,
      state: left.isEmpty && !_$attempting.contains(id)
          ? const PublishJobState.awaitingOwner()
          : job.state,
      items: left,
    );
    _changed();
    return true;
  }

  @override
  Stream<List<PublishJobSnapshot>> watchJobs(PublishJobFilter filter) {
    late final _Watcher watcher;
    final controller = StreamController<List<PublishJobSnapshot>>(
      onListen: () {
        _$watchers.add(watcher);
        watcher.send(_jobs);
      },
      onCancel: () {
        _$watchers.remove(watcher);
        return watcher.controller.close();
      },
    );
    watcher = _Watcher(filter, controller);
    return controller.stream;
  }

  void _attempt(PublishJobId id) {
    final request = _$requestOf[id];
    final publisher = switch (request?.publisher) {
      final name? => _$publishers[name],
      null => null,
    };
    if (request == null || publisher == null || !_$attempting.add(id)) return;
    _$attempts[id] = attemptsOf(id) + 1;
    final left = {for (final item in _jobs[_indexOf(id)].items) item.itemId};
    final refs = {
      for (final item in request.items)
        if (left.contains(item.itemId))
          item.itemId: switch (item.source) {
            PublishSource$Remote() => PublishItemRefs(key: item.key),
            _ => PublishItemRefs(
              key: item.key,
              file: RemoteRef('remote-${item.itemId}'),
            ),
          },
    };
    // Later, as the engine's attempt runs after its journal write: the
    // caller that made the job sees it before its publisher does.
    unawaited(
      Future(
        () => publisher.publish(
          request.payload,
          refs,
          request.idempotencyKey ?? request.tag ?? '$id',
        ),
      ).then(
        (outcome) => _answered(id, outcome),
        onError: (Object _) => _end(
          id,
          const PublishJobState.failed(
            stage: PublishStage.publish,
            reason: PublishFailureReason.publisherError,
            retryable: true,
          ),
        ),
      ),
    );
  }

  void _answered(PublishJobId id, PublishOutcome outcome) {
    switch (outcome) {
      case PublishOutcome$Published(:final result):
        _end(id, PublishJobState.completed(result));
      case PublishOutcome$Rejected(:final reason, :final retryable):
        _end(
          id,
          PublishJobState.failed(
            stage: PublishStage.publish,
            reason: PublishFailureReason(reason),
            retryable: retryable,
          ),
        );
      case PublishOutcome$ReuploadItems(:final itemIds):
        final reuploads = _$reuploads[id] ??= [];
        final refused = reuploads.isNotEmpty;
        reuploads.add(itemIds);
        if (refused) {
          _end(
            id,
            const PublishJobState.failed(
              stage: PublishStage.publish,
              reason: PublishFailureReason.reuploadRefused,
              retryable: false,
            ),
          );
        } else {
          _$attempting.remove(id);
          _attempt(id);
        }
    }
  }

  void _end(PublishJobId id, PublishJobState state) {
    _$attempting.remove(id);
    // A job removed (cancelled) while its publisher ran has no state left.
    if (!_jobs.any((job) => job.id == id)) return;
    setState(id, state);
  }

  static PublishJobState _firstStateOf(PublishRequest request) {
    final sources = [for (final item in request.items) item.source];
    if (sources.whereType<PublishSource$Prepare>().isNotEmpty) {
      return const PublishJobState.preparing();
    }
    if (sources.whereType<PublishSource$Prepared>().isNotEmpty) {
      return const PublishJobState.uploading();
    }
    return const PublishJobState.publishing();
  }

  int _indexOf(PublishJobId id) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) throw StateError('No fake publish job $id.');
    return index;
  }

  void _changed() {
    for (final watcher in [..._$watchers]) {
      watcher.send(_jobs);
    }
  }
}

final class _Watcher {
  _Watcher(this.filter, this.controller);

  final PublishJobFilter filter;
  final StreamController<List<PublishJobSnapshot>> controller;

  void send(List<PublishJobSnapshot> jobs) => controller.add([
    for (final job in jobs)
      if (filter.matches(job)) job,
  ]);
}
