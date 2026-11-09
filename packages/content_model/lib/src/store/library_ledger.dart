import 'dart:async';

import 'package:content_model/src/data/content_library.dart';
import 'package:content_model/src/data/library_storage.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/pack/pack.dart';
import 'package:content_model/src/store/library_rules.dart';
import 'package:content_model/src/value_equality.dart';
import 'package:listen/listen.dart';

/// Commits one edit with the committed state after it.
typedef LibraryCommit =
    Future<void> Function(LibraryEdit edit, LibraryState state);

/// The [ContentLibrary] contract without a storage of its own: the shown
/// lists, the edits inside their undo windows, and the order of commits.
///
/// The reference library and the fake both delegate here and add only where
/// a commit goes, so the undo and ordering rules have one implementation.
///
/// The lists shown are the committed state with the pending edits replayed
/// over it in order. An edit leaves the pending queue only from its front
/// (once its window ended), so commits reach [LibraryCommit] in the order the
/// edits were applied, one at a time.
final class LibraryLedger implements ContentLibrary {
  /// Creates a ledger shown from [committed], cut to [limits].
  LibraryLedger({
    required LibraryState committed,
    required this.limits,
    required LibraryCommit commit,
  }) : _committed = LibraryRules.fit(committed, limits),
       _commit = commit {
    _shown = _committed;
    _recent = ValueNotifier(_shown.recentStickers);
    _favourite = ValueNotifier(_shown.favouriteStickers);
    _saved = ValueNotifier(_shown.savedGifs);
    for (final kind in PackKind.values) {
      _installed[kind] = ValueNotifier(_shown.installedPacks(kind));
      _archived[kind] = ValueNotifier(_shown.archivedPacks(kind));
    }
  }

  @override
  final LibraryLimits limits;

  final LibraryCommit _commit;
  LibraryState _committed;
  late LibraryState _shown;
  final _$pending = <_PendingEdit>[];
  var _$writes = Future<void>.value();
  var _$disposed = false;

  late final ValueNotifier<List<ContentKey>> _recent;
  late final ValueNotifier<List<ContentKey>> _favourite;
  late final ValueNotifier<List<ContentKey>> _saved;
  final _installed = <PackKind, ValueNotifier<List<PackId>>>{};
  final _archived = <PackKind, ValueNotifier<List<PackId>>>{};

  @override
  ValueListenable<List<ContentKey>> get recentStickers => _recent;

  @override
  ValueListenable<List<ContentKey>> get favouriteStickers => _favourite;

  @override
  ValueListenable<List<ContentKey>> get savedGifs => _saved;

  @override
  ValueListenable<List<PackId>> installedPacks(PackKind kind) =>
      _installed[kind]!;

  @override
  ValueListenable<List<PackId>> archivedPacks(PackKind kind) =>
      _archived[kind]!;

  @override
  PackInstallState installStateOf(PackId id) {
    for (final kind in PackKind.values) {
      if (_shown.installedPacks(kind).contains(id)) {
        return PackInstallState.installed;
      }
    }
    for (final kind in PackKind.values) {
      if (_shown.archivedPacks(kind).contains(id)) {
        return PackInstallState.archived;
      }
    }
    return PackInstallState.notInstalled;
  }

  @override
  AppliedEdit apply(LibraryEdit edit, {Duration undoWindow = Duration.zero}) {
    if (_$disposed) return _UnchangedEdit(edit);
    final before = _shown;
    final after = LibraryRules.apply(before, edit, limits);
    if (after == before) return _UnchangedEdit(edit);
    final pending = _PendingEdit(
      this,
      edit,
      LibraryRules.evicted(before, after, edit),
    );
    _$pending.add(pending);
    _show(after);
    if (undoWindow > Duration.zero) {
      pending.timer = Timer(undoWindow, () => _release(pending));
    } else {
      pending.released = true;
    }
    _drain();
    return pending;
  }

  @override
  void dispose() {
    if (_$disposed) return;
    for (final pending in _$pending) {
      pending.timer?.cancel();
      pending.released = true;
    }
    _drain();
    _$disposed = true;
    _recent.dispose();
    _favourite.dispose();
    _saved.dispose();
    for (final notifier in [..._installed.values, ..._archived.values]) {
      notifier.dispose();
    }
  }

  bool _undo(_PendingEdit pending) {
    if (!_$pending.remove(pending)) return false;
    pending.timer?.cancel();
    pending.settle(EditOutcome.undone);
    _show(_replay());
    _drain();
    return true;
  }

  void _release(_PendingEdit pending) {
    if (!_$pending.contains(pending)) return;
    pending.timer?.cancel();
    pending.released = true;
    _drain();
  }

  // Commits the released edits at the front of the queue, in order. An edit
  // released behind one still in its window waits for it.
  void _drain() {
    while (_$pending.isNotEmpty && _$pending.first.released) {
      final pending = _$pending.removeAt(0);
      _committed = LibraryRules.apply(_committed, pending.edit, limits);
      final state = _committed;
      _$writes = _$writes.then((_) => _write(pending, state));
    }
  }

  Future<void> _write(_PendingEdit pending, LibraryState state) async {
    try {
      await _commit(pending.edit, state);
      pending.settle(EditOutcome.committed);
    } on Object catch (error, stackTrace) {
      pending.settle(EditOutcome.failed(error, stackTrace));
    }
  }

  LibraryState _replay() => _$pending.fold(
    _committed,
    (state, pending) => LibraryRules.apply(state, pending.edit, limits),
  );

  void _show(LibraryState state) {
    _shown = state;
    if (_$disposed) return;
    _assign(_recent, state.recentStickers);
    _assign(_favourite, state.favouriteStickers);
    _assign(_saved, state.savedGifs);
    for (final kind in PackKind.values) {
      _assign(_installed[kind]!, state.installedPacks(kind));
      _assign(_archived[kind]!, state.archivedPacks(kind));
    }
  }

  // A ValueNotifier compares lists by identity; assign only a list whose
  // contents changed, so a list an edit did not touch stays silent.
  static void _assign<T>(ValueNotifier<List<T>> notifier, List<T> value) {
    if (ValueEquality.lists(notifier.value, value)) return;
    notifier.value = value;
  }
}

final class _PendingEdit implements AppliedEdit {
  _PendingEdit(this._ledger, this.edit, this.evicted);

  final LibraryLedger _ledger;
  final _outcome = Completer<EditOutcome>();
  Timer? timer;
  bool released = false;

  @override
  final LibraryEdit edit;

  @override
  final ContentKey? evicted;

  @override
  bool get isPending => _ledger._$pending.contains(this);

  @override
  bool undo() => _ledger._undo(this);

  @override
  void commit() => _ledger._release(this);

  @override
  Future<EditOutcome> get outcome => _outcome.future;

  void settle(EditOutcome outcome) {
    if (!_outcome.isCompleted) _outcome.complete(outcome);
  }
}

final class _UnchangedEdit implements AppliedEdit {
  _UnchangedEdit(this.edit);

  @override
  final LibraryEdit edit;

  @override
  ContentKey? get evicted => null;

  @override
  bool get isPending => false;

  @override
  bool undo() => false;

  @override
  void commit() {}

  @override
  Future<EditOutcome> get outcome => Future.value(EditOutcome.unchanged);
}
