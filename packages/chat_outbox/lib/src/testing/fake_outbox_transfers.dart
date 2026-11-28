import 'dart:async';

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
/// Watchers get the current list on listen and the list again after each
/// change, asynchronously, as the engine's do.
final class FakeOutboxTransfers implements OutboxTransfers {
  /// A fake with no jobs.
  FakeOutboxTransfers();

  final List<PublishRequest> _requests = [];
  final List<PublishJobSnapshot> _jobs = [];
  final Set<_Watcher> _$watchers = {};
  DateTime _$clock = DateTime.utc(2026);

  /// Every request so far, in order.
  List<PublishRequest> get requests => List.unmodifiable(_requests);

  /// The jobs the fake holds now, oldest first.
  List<PublishJobSnapshot> get jobs => List.unmodifiable(_jobs);

  /// How many watchers are listening now.
  int get watcherCount => _$watchers.length;

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
    _changed();
    return id;
  }

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
  }

  /// Takes job [id] away, as the engine does with a cancelled job.
  void remove(PublishJobId id) {
    _jobs.removeAt(_indexOf(id));
    _changed();
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
